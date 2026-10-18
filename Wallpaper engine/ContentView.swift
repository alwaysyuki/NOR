//
//  ContentView.swift
//  Wallpaper engine
//

import SwiftUI
import AppKit
import AVFoundation

/// Discriminated active modal sheet to eliminate race conditions and multiple sheet conflicts.
enum ActiveSheet: Identifiable {
    case crop(GalleryItem)
    case trim(GalleryItem)
    
    var id: String {
        switch self {
        case .crop(let item): return "crop-\(item.id.uuidString)"
        case .trim(let item): return "trim-\(item.id.uuidString)"
        }
    }
}

struct ContentView: View {
    @Bindable var playbackManager: WallpaperPlaybackManager
    @Bindable var galleryManager: WallpaperGalleryManager
    
    @State private var activeSheet: ActiveSheet?
    
    var body: some View {
        HSplitView {
            // Left Pane: Local Gallery
            gallerySidebar
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            
            // Right Pane: Video Preview & Desktop Controls
            previewAndControlsPane
                .frame(minWidth: 460, idealWidth: 560)
        }
        .frame(minWidth: 840, idealWidth: 980, minHeight: 580, idealHeight: 650)
        .background(
            WindowAccessor { window in
                MenuBarManager.shared.registerMainWindow(window)
            }
        )
        // Single unified sheet modifier prevents macOS AppKit window presentation drops
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .crop(let item):
                VideoCropSheet(
                    item: item,
                    galleryManager: galleryManager,
                    playbackManager: playbackManager,
                    onDismiss: { activeSheet = nil }
                )
            case .trim(let item):
                VideoTrimSheet(
                    item: item,
                    galleryManager: galleryManager,
                    playbackManager: playbackManager,
                    onDismiss: { activeSheet = nil }
                )
            }
        }
        .onAppear {
            // Auto-select first item if available and none selected
            if playbackManager.selectedPreviewItem == nil, let first = galleryManager.items.first {
                playbackManager.selectForPreview(item: first)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notif in
            if let window = notif.object as? NSWindow {
                if !window.occlusionState.contains(.visible) {
                    playbackManager.pausePreview()
                }
            }
        }
    }
    
    // MARK: - Gallery Sidebar
    
    private var gallerySidebar: some View {
        VStack(spacing: 0) {
            // Gallery Header
            HStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("NŌR")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("\(galleryManager.items.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text("Live Wallpaper Engine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    galleryManager.promptToAddVideos()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(16)
            
            // Background conversion progress banner
            if let status = galleryManager.conversionStatusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.purple.opacity(0.12))
                .transition(.opacity)
            }
            
            Divider()
            
            // Gallery Items List / Empty State
            if galleryManager.items.isEmpty && !galleryManager.isImporting {
                emptyGalleryView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(galleryManager.items) { item in
                            galleryCard(for: item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(.background)
    }
    
    private var emptyGalleryView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 6) {
                Text("Your Gallery is Empty")
                    .font(.headline)
                Text("Add videos or animated media to set as your live desktop wallpaper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Text("Supports MP4, MOV, MKV, WebM, AVI, and animated GIF / WebP.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Button {
                galleryManager.promptToAddVideos()
            } label: {
                Label("Add Wallpapers to Gallery…", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            Spacer()
        }
    }
    
    private func galleryCard(for item: GalleryItem) -> some View {
        let isSelected = playbackManager.selectedPreviewItem?.id == item.id
        let isDesktopActive = playbackManager.activeDesktopItem?.id == item.id
        
        return Button {
            playbackManager.selectForPreview(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail container
                ZStack(alignment: .topTrailing) {
                    GalleryThumbnailView(item: item, galleryManager: galleryManager)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Format badge top-left
                    VStack {
                        HStack {
                            Text(item.isConverted ? "\(item.originalFormat) ➔ M1" : item.originalFormat)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    item.originalFormat == "Cropped" ? Color.teal.opacity(0.9) :
                                    (item.originalFormat == "Trimmed" ? Color.orange.opacity(0.9) :
                                    (item.isConverted ? Color.purple.opacity(0.85) : Color.blue.opacity(0.85))),
                                    in: Capsule()
                                )
                            Spacer()
                        }
                        .padding(6)
                        Spacer()
                    }
                    
                    // Desktop active badge top-right
                    if isDesktopActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(playbackManager.isDesktopSuspendedForFullScreen ? Color.orange : Color.green)
                                .frame(width: 6, height: 6)
                            Text(playbackManager.isDesktopSuspendedForFullScreen ? "FULL SCREEN PAUSED" : "ACTIVE DESKTOP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(8)
                    }
                    
                    // Audio badge & duration bottom
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: item.hasAudioTrack ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(item.hasAudioTrack ? .white : .orange)
                                .padding(5)
                                .background(.black.opacity(0.65), in: Circle())
                            
                            Spacer()
                            
                            Text(item.durationDescription)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(6)
                    }
                }
                
                // Item Details
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text("\(item.resolutionDescription) • \(item.fileSizeString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Quick Apply button
                    Button {
                        playbackManager.selectForPreview(item: item)
                        playbackManager.applyToDesktop(item: item)
                    } label: {
                        Image(systemName: isDesktopActive ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isDesktopActive ? (playbackManager.isDesktopSuspendedForFullScreen ? .orange : .green) : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(isDesktopActive ? (playbackManager.isDesktopSuspendedForFullScreen ? "Paused for full-screen app" : "Currently active on desktop") : "Apply as Live Wallpaper")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Apply to Desktop") {
                playbackManager.selectForPreview(item: item)
                playbackManager.applyToDesktop(item: item)
            }
            Button("Select for Preview") {
                playbackManager.selectForPreview(item: item)
            }
            Divider()
            Button {
                activeSheet = .trim(item)
            } label: {
                Label("Trim Video…", systemImage: "scissors")
            }
            Button {
                activeSheet = .crop(item)
            } label: {
                Label("Crop Video…", systemImage: "crop")
            }
            Divider()
            Button("Reveal in Finder") {
                if let url = galleryManager.resolveURL(for: item) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Remove from Gallery", role: .destructive) {
                if playbackManager.activeDesktopItem?.id == item.id {
                    playbackManager.stopDesktopWallpaper()
                }
                if playbackManager.selectedPreviewItem?.id == item.id {
                    playbackManager.selectedPreviewItem = nil
                }
                galleryManager.removeItem(item)
            }
        }
    }
    
    // MARK: - Preview & Controls Pane
    
    private var previewAndControlsPane: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let item = playbackManager.selectedPreviewItem {
                    selectedItemPreviewCard(item: item)
                    desktopControlsCard(item: item)
                } else {
                    noSelectionPlaceholder
                }
                
                if let error = playbackManager.errorMessage ?? galleryManager.errorMessage {
                    errorBanner(error)
                }
                
                watermarkFooter
            }
            .padding(20)
        }
        .background(.background)
    }
    
    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Wallpaper Selected")
                .font(.headline)
            Text("Select a wallpaper from the gallery on the left or add new files (MP4, MKV, WebM, GIF, WebP).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(.tertiary)
        )
    }
    
    // MARK: - Selected Item Preview Card
    
    private func selectedItemPreviewCard(item: GalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row 1: Video Title on left, Action Buttons & Status Badge on right
            HStack(alignment: .center, spacing: 10) {
                Text(item.fileName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 8)
                
                // Right controls: Fixed size so they NEVER squeeze or break into vertical letters
                HStack(spacing: 8) {
                    // Trim Video Button
                    Button {
                        activeSheet = .trim(item)
                    } label: {
                        Label("Trim", systemImage: "scissors")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Trim video in-point and out-point to create an ideal looping wallpaper")
                    
                    // Crop Video Button
                    Button {
                        activeSheet = .crop(item)
                    } label: {
                        Label("Crop", systemImage: "crop")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Crop and frame this video for Mac display (16:10), widescreen, or custom aspect ratios")
                    
                    // Status Badge
                    statusBadge(for: item)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            
            // Row 2: Metadata Info Badges
            HStack(spacing: 8) {
                // Format tag
                Text(item.isConverted ? "\(item.originalFormat) ➔ M1" : item.originalFormat)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        item.originalFormat == "Cropped" ? Color.teal.opacity(0.85) :
                        (item.originalFormat == "Trimmed" ? Color.orange.opacity(0.85) :
                        (item.isConverted ? Color.purple.opacity(0.85) : Color.blue.opacity(0.85))),
                        in: Capsule()
                    )
                
                metaBadge(icon: "display", text: item.resolutionDescription)
                metaBadge(icon: "clock", text: item.durationDescription)
                metaBadge(icon: "internaldrive", text: item.fileSizeString)
                
                Spacer()
            }
            .lineLimit(1)
            
            // Video Preview View with explicit item identity to cleanly reload layers on change
            ZStack(alignment: .bottom) {
                VideoPreviewView(player: playbackManager.previewPlayer)
                    .id(item.id)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Bottom control overlay bar
                HStack(spacing: 12) {
                    Button {
                        playbackManager.togglePreviewPlayback()
                    } label: {
                        Image(systemName: playbackManager.isPreviewPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help(playbackManager.isPreviewPlaying ? "Pause Preview" : "Play Preview")
                    
                    Divider()
                        .frame(height: 14)
                    
                    Button {
                        playbackManager.togglePreviewMute()
                    } label: {
                        Image(systemName: playbackManager.isPreviewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(item.hasAudioTrack ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.hasAudioTrack)
                    .help(playbackManager.isPreviewMuted ? "Unmute Preview Audio" : "Mute Preview Audio")
                    
                    if item.hasAudioTrack && !playbackManager.isPreviewMuted {
                        Slider(value: $playbackManager.previewVolume, in: 0.0...1.0)
                            .frame(width: 80)
                            .controlSize(.mini)
                    }
                    
                    Spacer()
                    
                    Text(item.audioDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.3))
        )
    }
    
    // MARK: - Status Badge & Meta Pill Helpers
    
    private func statusBadge(for item: GalleryItem) -> some View {
        Group {
            if playbackManager.activeDesktopItem?.id == item.id {
                if playbackManager.isDesktopSuspendedForFullScreen {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                        Text("Paused (Full Screen)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Desktop Active")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                    Text("Previewing")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func metaBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Desktop Controls Card
    
    private func desktopControlsCard(item: GalleryItem) -> some View {
        let isDesktopActive = playbackManager.activeDesktopItem?.id == item.id
        
        return VStack(spacing: 16) {
            // Apply / Stop Buttons
            HStack(spacing: 12) {
                Button {
                    playbackManager.applyToDesktop(item: item)
                } label: {
                    Label(
                        isDesktopActive ? "Restart Desktop Wallpaper" : "Apply as Live Wallpaper",
                        systemImage: isDesktopActive ? "arrow.clockwise" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(role: .destructive) {
                    playbackManager.stopDesktopWallpaper()
                } label: {
                    Label("Stop Desktop", systemImage: "stop.fill")
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!playbackManager.isDesktopActive)
            }
            
            // Desktop Audio Controls
            HStack(spacing: 14) {
                Button {
                    playbackManager.isDesktopMuted.toggle()
                } label: {
                    Image(systemName: playbackManager.isDesktopAudioSilenced ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .disabled(!item.hasAudioTrack || !playbackManager.isDesktopActive)
                .help(playbackManager.isDesktopMuted ? "Unmute Desktop Audio" : (playbackManager.isSoundAutoPausedForApp ? "Sound auto-paused by open app" : "Mute Desktop Audio"))
                
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Slider(value: $playbackManager.desktopVolume, in: 0.0...1.0)
                        .disabled(playbackManager.isDesktopAudioSilenced || !item.hasAudioTrack || !playbackManager.isDesktopActive)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("\(Int(playbackManager.desktopVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            
            Divider()
            
            // Auto-Pause Sound with Open Apps Setting
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Toggle(isOn: $playbackManager.autoPauseSoundWhenAppOpen) {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.badge.waveform")
                                .foregroundStyle(playbackManager.autoPauseSoundWhenAppOpen ? Color.accentColor : Color.secondary)
                            
                            Text("Auto-Pause Sound when Apps are Open")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!item.hasAudioTrack)
                    
                    Spacer()
                    
                    // Live Sound State Indicator
                    if playbackManager.isDesktopActive && item.hasAudioTrack && playbackManager.autoPauseSoundWhenAppOpen {
                        if playbackManager.isDesktopMuted {
                            HStack(spacing: 4) {
                                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                Text("Manually Muted")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        } else if playbackManager.isSoundAutoPausedForApp {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Sound Paused (App on Display)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("Playing (Clean Desktop)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                }
                
                Text("Sound automatically plays when on the desktop with no open apps, and pauses when any app window is open on the display.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.3))
        )
    }
    
    // MARK: - Error Banner & Footer
    
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.12))
        )
    }
    
    private var watermarkFooter: some View {
        HStack {
            Spacer()
            Text("Made by Yuki")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .padding(.top, 4)
    }
}

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Gallery Thumbnail View

struct GalleryThumbnailView: View {
    let item: GalleryItem
    let galleryManager: WallpaperGalleryManager
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.black.opacity(0.2)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task(id: item.id) {
            thumbnailImage = await galleryManager.thumbnail(for: item)
        }
    }
}
