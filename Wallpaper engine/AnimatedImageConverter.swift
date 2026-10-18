//
//  AnimatedImageConverter.swift
//  Wallpaper engine
//

import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import AVFoundation

/// Converts animated images (GIF, Animated WebP, APNG) into hardware-accelerated MP4 loops
/// using native Apple ImageIO and AVAssetWriter (Zero external dependencies).
final class AnimatedImageConverter {
    
    enum ConversionError: LocalizedError {
        case unreadableImage
        case noFramesFound
        case writerInitializationFailed(String)
        case writingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "The image file could not be read by ImageIO."
            case .noFramesFound:
                return "No animation frames were found in the file."
            case .writerInitializationFailed(let reason):
                return "Failed to initialize AVAssetWriter: \(reason)"
            case .writingFailed(let reason):
                return "Frame encoding failed: \(reason)"
            }
        }
    }
    
    /// Frame data extracted from ImageIO.
    private struct ImageAnimationFrame {
        let image: CGImage
        let durationSeconds: Double
    }
    
    /// Converts an animated GIF, WebP, or APNG to a looping MP4 video file.
    static func convertToMP4(sourceURL: URL, outputURL: URL, minLoopDuration: Double = 2.0) async throws {
        // Remove existing destination file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // 1. Read frames using ImageIO
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ConversionError.unreadableImage
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else {
            throw ConversionError.noFramesFound
        }
        
        var frames: [ImageAnimationFrame] = []
        var totalAnimationDuration: Double = 0
        
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) else {
                continue
            }
            let duration = frameDuration(at: i, in: imageSource)
            frames.append(ImageAnimationFrame(image: cgImage, durationSeconds: duration))
            totalAnimationDuration += duration
        }
        
        guard !frames.isEmpty, let firstFrame = frames.first?.image else {
            throw ConversionError.noFramesFound
        }
        
        // Determine video dimensions (minimum 16x16 and even numbers for H.264 macroblock encoding)
        var width = max(firstFrame.width, 16)
        var height = max(firstFrame.height, 16)
        if width % 2 != 0 { width += 1 }
        if height % 2 != 0 { height += 1 }
        
        // Calculate repeat count to ensure video is long enough for smooth AVPlayerLooper looping (at least minLoopDuration)
        let loopCount = totalAnimationDuration > 0 ? max(1, Int(ceil(minLoopDuration / totalAnimationDuration))) : 1
        
        // 2. Setup AVAssetWriter for H.264 video
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ConversionError.writerInitializationFailed(error.localizedDescription)
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAverageBitRateKey: max(width * height * 4, 1_000_000)
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        guard writer.canAdd(writerInput) else {
            throw ConversionError.writerInitializationFailed("Cannot add video input to AVAssetWriter.")
        }
        writer.add(writerInput)
        
        guard writer.startWriting() else {
            throw ConversionError.writingFailed(writer.error?.localizedDescription ?? "Start writing failed.")
        }
        writer.startSession(atSourceTime: .zero)
        
        // 3. Write repeated frames
        var currentTime = CMTime.zero
        let timescale: CMTimeScale = 600
        
        for _ in 0..<loopCount {
            for frame in frames {
                var waitAttempts = 0
                while !writerInput.isReadyForMoreMediaData && waitAttempts < 100 {
                    try await Task.sleep(nanoseconds: 5_000_000) // 5ms sleep
                    waitAttempts += 1
                }
                
                guard let pool = adaptor.pixelBufferPool,
                      let pixelBuffer = createPixelBuffer(from: frame.image, in: pool, width: width, height: height) else {
                    continue
                }
                
                adaptor.append(pixelBuffer, withPresentationTime: currentTime)
                
                let frameDurationCM = CMTime(seconds: frame.durationSeconds, preferredTimescale: timescale)
                currentTime = CMTimeAdd(currentTime, frameDurationCM)
            }
        }
        
        writerInput.markAsFinished()
        await writer.finishWriting()
        
        if writer.status != .completed {
            let errorMsg = writer.error?.localizedDescription ?? "Unknown AVAssetWriter failure."
            throw ConversionError.writingFailed(errorMsg)
        }
    }
    
    // MARK: - Frame Helpers
    
    private static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
        var duration = 0.1 // Default 100ms
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return duration
        }
        
        // GIF properties
        if let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                duration = unclamped
            } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                duration = delay
            }
        }
        
        // WebP properties
        if let webpProperties = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webpProperties[kCGImagePropertyWebPUnclampedDelayTime] as? Double, unclamped > 0 {
                duration = unclamped
            } else if let delay = webpProperties[kCGImagePropertyWebPDelayTime] as? Double, delay > 0 {
                duration = delay
            }
        }
        
        // PNG properties (APNG)
        if let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let unclamped = pngProperties[kCGImagePropertyAPNGUnclampedDelayTime] as? Double, unclamped > 0 {
                duration = unclamped
            } else if let delay = pngProperties[kCGImagePropertyAPNGDelayTime] as? Double, delay > 0 {
                duration = delay
            }
        }
        
        // Clamp to browser/standard minimum duration (10ms)
        return max(duration, 0.02)
    }
    
    private static func createPixelBuffer(
        from cgImage: CGImage,
        in pool: CVPixelBufferPool,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}
