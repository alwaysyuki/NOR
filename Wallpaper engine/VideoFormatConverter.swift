//
//  VideoFormatConverter.swift
//  Wallpaper engine
//

import Foundation
import AVFoundation

/// High-speed transcoder for non-AVFoundation video formats (MKV, WebM, AVI, FLV, WMV)
/// using Apple Silicon VideoToolbox and intelligent fast stream remuxing.
final class VideoFormatConverter {
    
    enum ConverterError: LocalizedError {
        case ffmpegNotFound
        case transcodeFailed(String)
        case outputFileNotFound
        
        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg is required to import MKV/WebM files. Please install it via Homebrew by running 'brew install ffmpeg' in Terminal."
            case .transcodeFailed(let message):
                return "Conversion failed: \(message)"
            case .outputFileNotFound:
                return "Converted video output file was not produced."
            }
        }
    }
    
    /// Common paths where Homebrew or system FFmpeg is installed.
    private static let candidatePaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    
    /// Finds available FFmpeg binary on the system.
    static func locateFFmpeg() -> String? {
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    /// Indicates whether FFmpeg is available on the system.
    static var isFFmpegAvailable: Bool {
        locateFFmpeg() != nil
    }
    
    /// Generates a sanitized environment stripped of any DYLD injection variables.
    private static func cleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("DYLD_") {
            env.removeValue(forKey: key)
        }
        return env
    }
    
    /// Converts an unsupported video into an optimized MP4 video.
    /// Employs a 2-stage pipeline:
    /// 1. Instant Direct Stream Copy (Remuxing) taking ~0.2s if the video stream is already H.264/HEVC.
    /// 2. Multi-threaded Apple Silicon VideoToolbox hardware transcoding with `-prio_speed true` & `-realtime true`.
    static func convertToMP4(sourceURL: URL, outputURL: URL) async throws {
        guard let ffmpegPath = locateFFmpeg() else {
            throw ConverterError.ffmpegNotFound
        }
        
        // Remove output file if it exists already
        try? FileManager.default.removeItem(at: outputURL)
        
        // MARK: - Stage 1: Try Instant Direct Stream Copy (Remuxing in ~0.2s)
        let remuxSucceeded = await attemptFastRemux(
            ffmpegPath: ffmpegPath,
            sourceURL: sourceURL,
            outputURL: outputURL
        )
        
        if remuxSucceeded {
            // Verify remuxed output is valid and playable by AVFoundation
            let testAsset = AVURLAsset(url: outputURL)
            if let isPlayable = try? await testAsset.load(.isPlayable), isPlayable,
               let tracks = try? await testAsset.loadTracks(withMediaType: .video), !tracks.isEmpty {
                return // Fast remux succeeded in fractions of a second!
            }
        }
        
        // Clean failed remux file if needed
        try? FileManager.default.removeItem(at: outputURL)
        
        // MARK: - Stage 2: Hardware-Accelerated VideoToolbox Transcoding with Speed Priority
        try await runHardwareTranscode(
            ffmpegPath: ffmpegPath,
            sourceURL: sourceURL,
            outputURL: outputURL
        )
    }
    
    /// Attempts fast container remuxing without re-encoding video frames.
    private static func attemptFastRemux(ffmpegPath: String, sourceURL: URL, outputURL: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                // -c:v copy copies video stream instantly without decoding or re-encoding
                process.arguments = [
                    "-y",
                    "-i", sourceURL.path,
                    "-c:v", "copy",
                    "-c:a", "aac",
                    "-b:a", "192k",
                    "-movflags", "+faststart",
                    outputURL.path
                ]
                process.environment = cleanEnvironment()
                
                let devNull = Pipe()
                process.standardOutput = devNull
                process.standardError = devNull
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path))
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Executes Apple Silicon VideoToolbox hardware transcoding with multi-threading and speed priority.
    private static func runHardwareTranscode(ffmpegPath: String, sourceURL: URL, outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                
                // Optimized arguments for maximum throughput on Apple Silicon M1:
                // -threads 0: utilizes all M1 CPU cores for input stream decoding
                // -c:v h264_videotoolbox: Apple Silicon hardware video encoder
                // -prio_speed true: instruct encoder to prioritize throughput
                // -realtime true: fast real-time hardware mode
                // -pix_fmt yuv420p: universal hardware compatibility
                process.arguments = [
                    "-y",
                    "-threads", "0",
                    "-i", sourceURL.path,
                    "-c:v", "h264_videotoolbox",
                    "-prio_speed", "true",
                    "-realtime", "true",
                    "-b:v", "6M",
                    "-pix_fmt", "yuv420p",
                    "-c:a", "aac",
                    "-b:a", "192k",
                    "-movflags", "+faststart",
                    outputURL.path
                ]
                process.environment = cleanEnvironment()
                
                let errorPipe = Pipe()
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path) {
                        continuation.resume()
                    } else {
                        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errString = String(data: errData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
                        continuation.resume(throwing: ConverterError.transcodeFailed(errString.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } catch {
                    continuation.resume(throwing: ConverterError.transcodeFailed(error.localizedDescription))
                }
            }
        }
    }
}
