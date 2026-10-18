//
//  VideoTrimSheet.swift
//  Wallpaper engine
//

import SwiftUI
import AVFoundation

/// Interactive modal sheet that allows users to trim any video wallpaper to a custom
/// time range with frame-accurate start/end controls and looping preview.
struct VideoTrimSheet: View {
    let item: GalleryItem
    @Bindable var galleryManager: WallpaperGalleryManager
    @Bindable var playbackManager: WallpaperPlaybackManager
    var onDismiss: () -> Void
    
    @State private var player: AVQueuePlayer?
    @State private var timeObserverToken: Any?
    
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var startTime: Double = 0.0
    @State private var endTime: Double = 1.0
    @State private var totalDuration: Double = 1.0
    
    @State private var isLoopPreviewing: Bool = false
    @State private var isTrimming: Bool = false
    @State private var trimProgress: Double = 0.0
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header: Always visible and never cropped
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text("Trim Video Wallpaper")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    Text(item.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                Button {
                    cleanupPlayer()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTrimming)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
            
            // Scrollable / Flexible Middle Body to accommodate all screen heights
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Video Player Area
                    ZStack(alignment: .bottom) {
                        VideoPreviewView(player: player)
                            .frame(height: 190)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // Mini transport controls overlay
                        HStack(spacing: 12) {
                            Button {
                                togglePlayPause()
                            } label: {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            
                            Text("\(formatTime(currentTime)) / \(formatTime(totalDuration))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                            
                            Spacer()
                            
                            Button {
                                isLoopPreviewing.toggle()
                                if isLoopPreviewing {
                                    seek(to: startTime)
                                    player?.play()
                                    isPlaying = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isLoopPreviewing ? "repeat.circle.fill" : "repeat.circle")
                                    Text(isLoopPreviewing ? "Looping Cut" : "Loop Cut")
                                }
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(isLoopPreviewing ? .white : .white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isLoopPreviewing ? Color.accentColor : Color.black.opacity(0.45), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                    }
                    
                    // Trim Range & Scrubber Controls
                    VStack(spacing: 10) {
                        // Visual range progress bar
                        GeometryReader { geo in
                            let w = geo.size.width
                            let startFraction = totalDuration > 0 ? (startTime / totalDuration) : 0
                            let endFraction = totalDuration > 0 ? (endTime / totalDuration) : 1
                            let currentFraction = totalDuration > 0 ? (currentTime / totalDuration) : 0
                            
                            ZStack(alignment: .leading) {
                                // Total duration track
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.25))
                                    .frame(height: 8)
                                
                                // Selected active trim range
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.85))
                                    .frame(width: max(4, (endFraction - startFraction) * w), height: 8)
                                    .offset(x: startFraction * w)
                                
                                // Playhead indicator
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 2, height: 16)
                                    .shadow(radius: 2)
                                    .offset(x: min(w - 2, max(0, currentFraction * w - 1)))
                            }
                        }
                        .frame(height: 16)
                        
                        // Time range summary badge
                        HStack {
                            Label("Start: \(formatTime(startTime))", systemImage: "arrow.right.to.line")
                                .font(.caption2.monospacedDigit())
                            Spacer()
                            Text("Duration: \(formatDuration(endTime - startTime))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Spacer()
                            Label("End: \(formatTime(endTime))", systemImage: "arrow.left.to.line")
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(.horizontal, 4)
                        
                        Divider()
                        
                        // Start & End Steppers and Sliders
                        HStack(spacing: 16) {
                            // Start Point Controls
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("In-Point (Start)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button("To Playhead") {
                                        setStartToPlayhead()
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                }
                                
                                Slider(value: $startTime, in: 0.0...max(0.01, endTime - 0.2)) { _ in
                                    seek(to: startTime)
                                }
                                .controlSize(.small)
                                .disabled(isTrimming)
                                
                                HStack(spacing: 4) {
                                    Button("-1s") { adjustStart(by: -1.0) }.controlSize(.mini)
                                    Button("-0.1s") { adjustStart(by: -0.1) }.controlSize(.mini)
                                    Button("+0.1s") { adjustStart(by: 0.1) }.controlSize(.mini)
                                    Button("+1s") { adjustStart(by: 1.0) }.controlSize(.mini)
                                    Spacer()
                                    Button("Reset") { startTime = 0.0; seek(to: 0.0) }.controlSize(.mini)
                                }
                            }
                            
                            Divider()
                            
                            // End Point Controls
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Out-Point (End)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Button("To Playhead") {
                                        setEndToPlayhead()
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                }
                                
                                Slider(value: $endTime, in: min(totalDuration, startTime + 0.2)...totalDuration) { _ in
                                    seek(to: endTime)
                                }
                                .controlSize(.small)
                                .disabled(isTrimming)
                                
                                HStack(spacing: 4) {
                                    Button("-1s") { adjustEnd(by: -1.0) }.controlSize(.mini)
                                    Button("-0.1s") { adjustEnd(by: -0.1) }.controlSize(.mini)
                                    Button("+0.1s") { adjustEnd(by: 0.1) }.controlSize(.mini)
                                    Button("+1s") { adjustEnd(by: 1.0) }.controlSize(.mini)
                                    Spacer()
                                    Button("Reset") { endTime = totalDuration; seek(to: totalDuration) }.controlSize(.mini)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary.opacity(0.35))
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.12))
            }
            
            // Progress Bar when trimming
            if isTrimming {
                VStack(spacing: 4) {
                    ProgressView(value: trimProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("Trimming with Apple Silicon hardware acceleration… \(Int(trimProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Pinned Footer Action Buttons: Always visible, never clipped
            HStack {
                Button("Cancel") {
                    cleanupPlayer()
                    onDismiss()
                }
                .buttonStyle(.plain)
                .disabled(isTrimming)
                
                Spacer()
                
                Button {
                    startTrimming()
                } label: {
                    Label(
                        isTrimming ? "Trimming…" : "Trim & Save to Gallery",
                        systemImage: "scissors"
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isTrimming)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: 700)
        .frame(minHeight: 460, idealHeight: 510, maxHeight: 560)
        .background(.background)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    // MARK: - Player Setup & Loop Handling
    
    private func setupPlayer() {
        guard let url = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            errorMessage = "Could not access video file for preview."
            return
        }
        
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = true
        
        self.player = queuePlayer
        self.totalDuration = max(1.0, item.durationSeconds)
        self.startTime = 0.0
        self.endTime = max(1.0, item.durationSeconds)
        
        // Time observer for real-time playhead and looping preview
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = queuePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak queuePlayer] time in
            let sec = CMTimeGetSeconds(time)
            guard sec.isFinite else { return }
            self.currentTime = sec
            
            if self.isLoopPreviewing {
                if sec >= self.endTime || sec < self.startTime {
                    queuePlayer?.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
        
        queuePlayer.play()
        self.isPlaying = true
    }
    
    private func cleanupPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        SecurityScopedResourceManager.shared.stopAccess(for: item)
    }
    
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }
    
    private func seek(to seconds: Double) {
        let clamped = max(0.0, min(totalDuration, seconds))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
    
    private func setStartToPlayhead() {
        let newStart = max(0.0, min(endTime - 0.2, currentTime))
        startTime = newStart
        seek(to: newStart)
    }
    
    private func setEndToPlayhead() {
        let newEnd = min(totalDuration, max(startTime + 0.2, currentTime))
        endTime = newEnd
        seek(to: newEnd)
    }
    
    private func adjustStart(by delta: Double) {
        let target = max(0.0, min(endTime - 0.2, startTime + delta))
        startTime = target
        seek(to: target)
    }
    
    private func adjustEnd(by delta: Double) {
        let target = min(totalDuration, max(startTime + 0.2, endTime + delta))
        endTime = target
        seek(to: target)
    }
    
    // MARK: - Trimming Execution
    
    private func startTrimming() {
        guard let sourceURL = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            errorMessage = "Could not resolve file access for '\(item.fileName)'."
            return
        }
        
        isTrimming = true
        errorMessage = nil
        trimProgress = 0.0
        player?.pause()
        isPlaying = false
        
        let destinationURL = galleryManager.trimmedWallpapersDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let start = startTime
        let end = endTime
        let originalFileName = item.fileName
        
        Task {
            defer {
                SecurityScopedResourceManager.shared.stopAccess(for: item)
            }
            
            do {
                try await VideoTrimService.trimVideo(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    startTime: start,
                    endTime: end
                ) { progress in
                    Task { @MainActor in
                        self.trimProgress = progress
                    }
                }
                
                // Import the newly trimmed wallpaper into local gallery
                if let newItem = await galleryManager.importTrimmedWallpaper(
                    trimmedFileURL: destinationURL,
                    originalFileName: originalFileName
                ) {
                    playbackManager.selectForPreview(item: newItem)
                }
                
                cleanupPlayer()
                isTrimming = false
                onDismiss()
            } catch {
                errorMessage = "Trimming failed: \(error.localizedDescription)"
                isTrimming = false
            }
        }
    }
    
    // MARK: - Formatters
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00.0" }
        let mins = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%04.1f", mins, secs)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0.0s" }
        return String(format: "%.1fs", seconds)
    }
}
