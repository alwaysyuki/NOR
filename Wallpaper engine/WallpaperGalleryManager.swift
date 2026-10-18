//
//  WallpaperGalleryManager.swift
//  Wallpaper engine
//

import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import Observation

/// Model representing a video or animated wallpaper stored in the user's local gallery.
struct GalleryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let bookmarkData: Data
    let fileName: String
    var originalFormat: String
    var isConverted: Bool
    let fileSizeString: String
    let resolutionWidth: Double
    let resolutionHeight: Double
    let durationSeconds: Double
    let hasAudioTrack: Bool
    let audioTrackCount: Int
    let dateAdded: Date
    
    init(
        id: UUID,
        bookmarkData: Data,
        fileName: String,
        originalFormat: String = "MP4",
        isConverted: Bool = false,
        fileSizeString: String,
        resolutionWidth: Double,
        resolutionHeight: Double,
        durationSeconds: Double,
        hasAudioTrack: Bool,
        audioTrackCount: Int,
        dateAdded: Date
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.fileName = fileName
        self.originalFormat = originalFormat
        self.isConverted = isConverted
        self.fileSizeString = fileSizeString
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.durationSeconds = durationSeconds
        self.hasAudioTrack = hasAudioTrack
        self.audioTrackCount = audioTrackCount
        self.dateAdded = dateAdded
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        fileName = try container.decode(String.self, forKey: .fileName)
        originalFormat = try container.decodeIfPresent(String.self, forKey: .originalFormat) ?? "MP4"
        isConverted = try container.decodeIfPresent(Bool.self, forKey: .isConverted) ?? false
        fileSizeString = try container.decode(String.self, forKey: .fileSizeString)
        resolutionWidth = try container.decode(Double.self, forKey: .resolutionWidth)
        resolutionHeight = try container.decode(Double.self, forKey: .resolutionHeight)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        hasAudioTrack = try container.decode(Bool.self, forKey: .hasAudioTrack)
        audioTrackCount = try container.decode(Int.self, forKey: .audioTrackCount)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
    }
    
    var resolutionDescription: String {
        if resolutionWidth > 0 && resolutionHeight > 0 {
            return "\(Int(resolutionWidth)) × \(Int(resolutionHeight))"
        }
        return "Unknown"
    }
    
    var durationDescription: String {
        guard durationSeconds > 0 else { return "0:00" }
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var audioDescription: String {
        if !hasAudioTrack {
            return "No Audio"
        }
        return audioTrackCount > 1 ? "\(audioTrackCount) Audio Tracks" : "Stereo Audio"
    }
}

/// Manages local gallery persistence, multi-format media import,
/// and video cropping & trimming additions.
@Observable
@MainActor
final class WallpaperGalleryManager {
    
    var items: [GalleryItem] = []
    var isImporting: Bool = false
    var errorMessage: String?
    var conversionStatusMessage: String?
    
    @ObservationIgnored
    private let persistenceKey = "LocalWallpaperGalleryItems_v1"
    
    @ObservationIgnored
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    var convertedWallpapersDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WallpaperEngine/ConvertedWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var croppedWallpapersDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WallpaperEngine/CroppedWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var trimmedWallpapersDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WallpaperEngine/TrimmedWallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {
        thumbnailCache.countLimit = 30
        thumbnailCache.totalCostLimit = 25 * 1024 * 1024 // 25 MB RAM limit
        loadPersistedGallery()
    }
    
    // MARK: - Import Wallpapers via File Picker
    
    func promptToAddVideos() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Add Wallpapers to Local Gallery"
        panel.prompt = "Add to Gallery"
        
        var contentTypes: [UTType] = [
            .mpeg4Movie,
            .quickTimeMovie,
            .movie,
            .video,
            .gif
        ]
        if let aviType = UTType("public.avi") { contentTypes.append(aviType) }
        if let webmType = UTType("org.webmproject.webm") { contentTypes.append(webmType) }
        if let mkvType = UTType(filenameExtension: "mkv") { contentTypes.append(mkvType) }
        if let webpType = UTType("org.webmproject.webp") { contentTypes.append(webpType) }
        
        panel.allowedContentTypes = contentTypes
        
        guard panel.runModal() == .OK else { return }
        let selectedURLs = panel.urls
        guard !selectedURLs.isEmpty else { return }
        
        isImporting = true
        errorMessage = nil
        
        Task {
            for url in selectedURLs {
                await importMediaFile(from: url)
            }
            self.isImporting = false
            self.conversionStatusMessage = nil
        }
    }
    
    private func importMediaFile(from url: URL) async {
        let ext = url.pathExtension.lowercased()
        let formatLabel = ext.uppercased()
        
        let animatedImageExtensions = ["gif", "webp", "apng"]
        let isAnimatedImage = animatedImageExtensions.contains(ext)
        let nonNativeVideoExtensions = ["mkv", "webm", "avi", "flv", "wmv"]
        let isNonNativeVideo = nonNativeVideoExtensions.contains(ext)
        
        do {
            var playableURL: URL = url
            var isConverted = false
            
            if isAnimatedImage {
                conversionStatusMessage = "Converting animated \(formatLabel) into hardware H.264 video…"
                let outputURL = convertedWallpapersDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                try await AnimatedImageConverter.convertToMP4(sourceURL: url, outputURL: outputURL)
                playableURL = outputURL
                isConverted = true
            } else {
                let tempAsset = AVURLAsset(url: url)
                let isNativelyPlayable = (try? await tempAsset.load(.isPlayable)) ?? false
                
                if !isNativelyPlayable || isNonNativeVideo {
                    conversionStatusMessage = "Optimizing \(formatLabel) for M1 hardware acceleration…"
                    let outputURL = convertedWallpapersDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                    try await VideoFormatConverter.convertToMP4(sourceURL: url, outputURL: outputURL)
                    playableURL = outputURL
                    isConverted = true
                }
            }
            
            let asset = AVURLAsset(url: playableURL)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                errorMessage = "The file '\(url.lastPathComponent)' could not be prepared for playback."
                return
            }
            
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let primaryTrack = videoTracks.first else {
                errorMessage = "No video track found in '\(url.lastPathComponent)'."
                return
            }
            
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !audioTracks.isEmpty
            
            let naturalSize = try await primaryTrack.load(.naturalSize)
            let preferredTransform = try await primaryTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            var fileSizeString = ""
            if let attributes = try? FileManager.default.attributesOfItem(atPath: playableURL.path),
               let bytes = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSizeString = formatter.string(fromByteCount: bytes)
            }
            
            guard let bookmarkData = createBookmark(for: playableURL) else {
                errorMessage = "Could not create security bookmark for '\(url.lastPathComponent)'."
                return
            }
            
            let id = UUID()
            let item = GalleryItem(
                id: id,
                bookmarkData: bookmarkData,
                fileName: url.lastPathComponent,
                originalFormat: formatLabel,
                isConverted: isConverted,
                fileSizeString: fileSizeString,
                resolutionWidth: displaySize.width,
                resolutionHeight: displaySize.height,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                hasAudioTrack: hasAudio,
                audioTrackCount: audioTracks.count,
                dateAdded: Date()
            )
            
            if let thumbnail = await generateThumbnail(for: asset) {
                thumbnailCache.setObject(thumbnail, forKey: id.uuidString as NSString)
            }
            
            if !items.contains(where: { $0.fileName == item.fileName }) {
                items.insert(item, at: 0)
                persistGallery()
            }
        } catch {
            errorMessage = "Failed to import '\(url.lastPathComponent)': \(error.localizedDescription)"
        }
    }
    
    // MARK: - Import Cropped Wallpaper
    
    /// Imports a newly cropped video file directly into the local gallery.
    @discardableResult
    func importCroppedWallpaper(croppedFileURL: URL, originalFileName: String) async -> GalleryItem? {
        do {
            let asset = AVURLAsset(url: croppedFileURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let primaryTrack = videoTracks.first else {
                errorMessage = "No video track found in cropped file."
                return nil
            }
            
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let naturalSize = try await primaryTrack.load(.naturalSize)
            let preferredTransform = try await primaryTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            var fileSizeString = ""
            if let attributes = try? FileManager.default.attributesOfItem(atPath: croppedFileURL.path),
               let bytes = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSizeString = formatter.string(fromByteCount: bytes)
            }
            
            guard let bookmarkData = createBookmark(for: croppedFileURL) else {
                errorMessage = "Could not create security bookmark for cropped wallpaper."
                return nil
            }
            
            let id = UUID()
            let baseName = (originalFileName as NSString).deletingPathExtension
            let newFileName = "\(baseName) (Cropped).mp4"
            
            let item = GalleryItem(
                id: id,
                bookmarkData: bookmarkData,
                fileName: newFileName,
                originalFormat: "Cropped",
                isConverted: true,
                fileSizeString: fileSizeString,
                resolutionWidth: displaySize.width,
                resolutionHeight: displaySize.height,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                hasAudioTrack: !audioTracks.isEmpty,
                audioTrackCount: audioTracks.count,
                dateAdded: Date()
            )
            
            if let thumbnail = await generateThumbnail(for: asset) {
                thumbnailCache.setObject(thumbnail, forKey: id.uuidString as NSString)
            }
            
            items.insert(item, at: 0)
            persistGallery()
            return item
        } catch {
            errorMessage = "Failed to import cropped wallpaper: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - Import Trimmed Wallpaper
    
    /// Imports a newly trimmed video file directly into the local gallery.
    @discardableResult
    func importTrimmedWallpaper(trimmedFileURL: URL, originalFileName: String) async -> GalleryItem? {
        do {
            let asset = AVURLAsset(url: trimmedFileURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let primaryTrack = videoTracks.first else {
                errorMessage = "No video track found in trimmed file."
                return nil
            }
            
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let naturalSize = try await primaryTrack.load(.naturalSize)
            let preferredTransform = try await primaryTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            var fileSizeString = ""
            if let attributes = try? FileManager.default.attributesOfItem(atPath: trimmedFileURL.path),
               let bytes = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                fileSizeString = formatter.string(fromByteCount: bytes)
            }
            
            guard let bookmarkData = createBookmark(for: trimmedFileURL) else {
                errorMessage = "Could not create security bookmark for trimmed wallpaper."
                return nil
            }
            
            let id = UUID()
            let baseName = (originalFileName as NSString).deletingPathExtension
            let newFileName = "\(baseName) (Trimmed).mp4"
            
            let item = GalleryItem(
                id: id,
                bookmarkData: bookmarkData,
                fileName: newFileName,
                originalFormat: "Trimmed",
                isConverted: true,
                fileSizeString: fileSizeString,
                resolutionWidth: displaySize.width,
                resolutionHeight: displaySize.height,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                hasAudioTrack: !audioTracks.isEmpty,
                audioTrackCount: audioTracks.count,
                dateAdded: Date()
            )
            
            if let thumbnail = await generateThumbnail(for: asset) {
                thumbnailCache.setObject(thumbnail, forKey: id.uuidString as NSString)
            }
            
            items.insert(item, at: 0)
            persistGallery()
            return item
        } catch {
            errorMessage = "Failed to import trimmed wallpaper: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - Remove
    
    func removeItem(_ item: GalleryItem) {
        if item.isConverted, let url = resolveURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        
        items.removeAll { $0.id == item.id }
        thumbnailCache.removeObject(forKey: item.id.uuidString as NSString)
        persistGallery()
    }
    
    // MARK: - Thumbnail Management
    
    func thumbnail(for item: GalleryItem) async -> NSImage? {
        if let cached = thumbnailCache.object(forKey: item.id.uuidString as NSString) {
            return cached
        }
        
        guard let url = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            return nil
        }
        defer {
            SecurityScopedResourceManager.shared.stopAccess(for: item)
        }
        
        let asset = AVURLAsset(url: url)
        if let generated = await generateThumbnail(for: asset) {
            thumbnailCache.setObject(generated, forKey: item.id.uuidString as NSString)
            return generated
        }
        return nil
    }
    
    private func generateThumbnail(for asset: AVAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Constrain to exact gallery card display size to reduce memory footprint by >50%
        generator.maximumSize = CGSize(width: 320, height: 180)
        // Keyframe extraction avoids expensive multi-frame seeking and decoding overhead
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            let fallbackTime = CMTime(seconds: 0.0, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: fallbackTime) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            return nil
        }
    }
    
    // MARK: - URL & Bookmark Resolution
    
    func resolveURL(for item: GalleryItem) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return url
    }
    
    private func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
    
    // MARK: - Persistence
    
    private func persistGallery() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: persistenceKey)
        }
    }
    
    private func loadPersistedGallery() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode([GalleryItem].self, from: data) else {
            return
        }
        self.items = decoded
    }
}
