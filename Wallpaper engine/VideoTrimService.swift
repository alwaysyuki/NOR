//
//  VideoTrimService.swift
//  Wallpaper engine
//

import Foundation
import AVFoundation

/// High-speed video trimming service powered by Apple Silicon VideoToolbox
/// and AVAssetExportSession.
final class VideoTrimService {
    
    enum TrimError: LocalizedError {
        case invalidTimeRange
        case exportSessionCreationFailed
        case exportFailed(String)
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .invalidTimeRange:
                return "The selected trim range is invalid (duration must be greater than 0.2s)."
            case .exportSessionCreationFailed:
                return "Failed to initialize export session for video trimming."
            case .exportFailed(let reason):
                return "Video trimming failed: \(reason)"
            case .cancelled:
                return "Trimming operation was cancelled."
            }
        }
    }
    
    /// Trims a video file between `startTime` and `endTime` (in seconds) and exports an optimized MP4.
    ///
    /// - Parameters:
    ///   - sourceURL: URL of the source video file.
    ///   - destinationURL: Output destination URL.
    ///   - startTime: In-point in seconds.
    ///   - endTime: Out-point in seconds.
    ///   - progressHandler: Closure receiving progress values from 0.0 to 1.0.
    static func trimVideo(
        sourceURL: URL,
        destinationURL: URL,
        startTime: Double,
        endTime: Double,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        let duration = endTime - startTime
        guard duration >= 0.2 else {
            throw TrimError.invalidTimeRange
        }
        
        // Remove existing destination file if present
        try? FileManager.default.removeItem(at: destinationURL)
        
        let asset = AVURLAsset(url: sourceURL)
        
        // Create hardware-accelerated export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        
        // Specify precise time range
        let startCMTime = CMTime(seconds: max(0, startTime), preferredTimescale: 600)
        let durationCMTime = CMTime(seconds: duration, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)
        
        // Monitor export progress
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
            throw TrimError.exportFailed(msg)
        case .cancelled:
            throw TrimError.cancelled
        default:
            throw TrimError.exportFailed("Unexpected export session status: \(exportSession.status.rawValue)")
        }
    }
}
