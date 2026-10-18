//
//  VideoCropService.swift
//  Wallpaper engine
//

import Foundation
import AVFoundation
import CoreGraphics

/// Preset aspect ratios for video wallpaper cropping.
enum CropPreset: String, CaseIterable, Identifiable {
    case macScreen = "Mac Display (16:10)"
    case standard16_9 = "16:9 Widescreen"
    case ultraWide21_9 = "21:9 UltraWide"
    case classic4_3 = "4:3 Classic"
    case square1_1 = "1:1 Square"
    case portrait9_16 = "9:16 Vertical"
    case freeform = "Custom / Freeform"
    
    var id: String { rawValue }
    
    /// Aspect ratio width / height, or nil for freeform.
    var aspectRatio: CGFloat? {
        switch self {
        case .macScreen:
            return 16.0 / 10.0
        case .standard16_9:
            return 16.0 / 9.0
        case .ultraWide21_9:
            return 21.0 / 9.0
        case .classic4_3:
            return 4.0 / 3.0
        case .square1_1:
            return 1.0
        case .portrait9_16:
            return 9.0 / 16.0
        case .freeform:
            return nil
        }
    }
}

/// Errors that may occur during video cropping operations.
enum VideoCropError: LocalizedError {
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No valid video track found in the source file."
        case .exportSessionCreationFailed:
            return "Failed to initialize AVAssetExportSession for cropping."
        case .exportFailed(let reason):
            return "Video cropping failed: \(reason)"
        case .cancelled:
            return "Cropping operation was cancelled."
        }
    }
}

/// High-performance video cropping service powered by Apple Silicon VideoToolbox
/// hardware encoding and AVMutableVideoComposition.
final class VideoCropService {
    
    /// Crops a video file to the specified pixel rectangle and exports an optimized MP4 wallpaper loop.
    ///
    /// - Parameters:
    ///   - sourceURL: URL of the source video or converted MP4.
    ///   - destinationURL: Output destination URL.
    ///   - cropRect: The crop rectangle in video pixel coordinates (with origin at top-left).
    ///   - progressHandler: Closure receiving progress values from 0.0 to 1.0.
    static func cropVideo(
        sourceURL: URL,
        destinationURL: URL,
        cropRect: CGRect,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        // Remove existing destination file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        let asset = AVURLAsset(url: sourceURL)
        
        // 1. Inspect video tracks and properties
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoCropError.noVideoTrack
        }
        
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        
        // Compute oriented dimensions
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedWidth = abs(transformedRect.width)
        let orientedHeight = abs(transformedRect.height)
        
        // Clamp crop bounds to video dimensions
        let clampedX = max(0, min(cropRect.origin.x, orientedWidth - 16))
        let clampedY = max(0, min(cropRect.origin.y, orientedHeight - 16))
        let clampedW = max(16, min(cropRect.width, orientedWidth - clampedX))
        let clampedH = max(16, min(cropRect.height, orientedHeight - clampedY))
        
        // Video encoders require dimensions divisible by 2
        let evenWidth = floor(clampedW / 2.0) * 2.0
        let evenHeight = floor(clampedH / 2.0) * 2.0
        let renderSize = CGSize(width: evenWidth, height: evenHeight)
        
        // 2. Build Composition
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoCropError.exportSessionCreationFailed
        }
        
        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
        
        // Preserve audio tracks if available
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
        }
        
        // 3. Configure Transform for Bottom-Left CoreGraphics Coordinates
        var baseTransform = preferredTransform
        if transformedRect.origin.x < 0 {
            baseTransform = baseTransform.concatenating(CGAffineTransform(translationX: abs(transformedRect.origin.x), y: 0))
        }
        if transformedRect.origin.y < 0 {
            baseTransform = baseTransform.concatenating(CGAffineTransform(translationX: 0, y: abs(transformedRect.origin.y)))
        }
        
        // Convert top-left UI Y coordinate to AVFoundation bottom-left Y coordinate
        let cgY = orientedHeight - (clampedY + evenHeight)
        let finalTransform = baseTransform.concatenating(CGAffineTransform(translationX: -clampedX, y: -cgY))
        
        // 4. Video Composition & Layer Instruction
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // 5. Hardware Accelerated Export Session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoCropError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false
        
        // Periodically monitor progress
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let prog = Double(exportSession.progress)
            progressHandler?(prog)
        }
        
        defer {
            timer.invalidate()
        }
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            progressHandler?(1.0)
            return
        case .failed:
            let msg = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw VideoCropError.exportFailed(msg)
        case .cancelled:
            throw VideoCropError.cancelled
        default:
            throw VideoCropError.exportFailed("Unexpected export session status: \(exportSession.status.rawValue)")
        }
    }
}
