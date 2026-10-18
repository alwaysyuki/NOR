//
//  WallpaperPlaybackManager.swift
//  Wallpaper engine
//

import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import Observation

/// Playback states for the desktop live wallpaper pipeline.
enum DesktopWallpaperState: Equatable {
    case idle
    case active
    case failed(reason: String)
}

/// Central coordinator for in-app video preview, desktop live wallpaper playback,
/// and intelligent full-screen app occlusion detection with Apple Silicon resource optimizations.
@Observable
@MainActor
final class WallpaperPlaybackManager {
    
    // MARK: - State Properties
    
    var desktopState: DesktopWallpaperState = .idle
    var activeDesktopItem: GalleryItem?
    var selectedPreviewItem: GalleryItem?
    
    /// True when wallpaper playback is automatically paused because a full-screen app is active.
    var isDesktopSuspendedForFullScreen: Bool = false
    
    /// User preference: whether to automatically pause sound when any application is open on the display.
    var autoPauseSoundWhenAppOpen: Bool {
        didSet {
            UserDefaults.standard.set(autoPauseSoundWhenAppOpen, forKey: "autoPauseSoundWhenAppOpen")
            updateDesktopAudioState()
        }
    }
    
    /// True when sound is currently auto-paused because an application window is open on the display.
    var isSoundAutoPausedForApp: Bool = false
    
    /// True if desktop audio is currently silenced (either manually muted or auto-paused by an open app).
    var isDesktopAudioSilenced: Bool {
        isDesktopMuted || (autoPauseSoundWhenAppOpen && isSoundAutoPausedForApp)
    }
    
    // In-Window Preview State & Controls (Observable by SwiftUI)
    var previewPlayer: AVQueuePlayer?
    var isPreviewPlaying: Bool = false
    var isPreviewMuted: Bool = true {
        didSet {
            previewPlayer?.isMuted = isPreviewMuted
        }
    }
    var previewVolume: Float = 0.8 {
        didSet {
            previewPlayer?.volume = previewVolume
        }
    }
    
    // Desktop Wallpaper Controls
    var isDesktopMuted: Bool = false {
        didSet {
            updateDesktopAudioState()
        }
    }
    var desktopVolume: Float = 1.0 {
        didSet {
            desktopPlayer?.volume = desktopVolume
        }
    }
    
    var errorMessage: String?
    
    // MARK: - Private Pipeline Resources
    
    @ObservationIgnored
    private var previewLooper: AVPlayerLooper?
    
    @ObservationIgnored
    private var desktopPlayer: AVQueuePlayer?
    @ObservationIgnored
    private var desktopLooper: AVPlayerLooper?
    
    @ObservationIgnored
    private let windowController = WallpaperWindowController()
    
    @ObservationIgnored
    private let fullScreenMonitor = FullScreenAppMonitor()
    
    @ObservationIgnored
    private var terminationObserver: NSObjectProtocol?
    
    var isDesktopActive: Bool {
        desktopState == .active
    }
    
    var isDesktopPlaying: Bool {
        desktopPlayer?.timeControlStatus == .playing
    }
    
    init() {
        if UserDefaults.standard.object(forKey: "autoPauseSoundWhenAppOpen") != nil {
            self.autoPauseSoundWhenAppOpen = UserDefaults.standard.bool(forKey: "autoPauseSoundWhenAppOpen")
        } else {
            self.autoPauseSoundWhenAppOpen = true
        }
        setupTerminationObserver()
        setupFullScreenMonitoring()
    }
    
    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        fullScreenMonitor.stopMonitoring()
    }
    
    private func setupTerminationObserver() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cleanup()
            }
        }
    }
    
    // MARK: - Full-Screen App Occlusion & Display App Coordinator
    
    private func setupFullScreenMonitoring() {
        fullScreenMonitor.onFullScreenStateChanged = { [weak self] isCovered in
            MainActor.assumeIsolated {
                self?.handleFullScreenStateChange(isCovered: isCovered)
            }
        }
        fullScreenMonitor.onAppDisplayStateChanged = { [weak self] isAppOpen in
            MainActor.assumeIsolated {
                self?.handleAppDisplayStateChange(isAppOpen: isAppOpen)
            }
        }
    }
    
    /// Intelligently pauses wallpaper when a full-screen app is active to eliminate GPU/CPU decode overhead,
    /// and restarts immediately upon returning to the main desktop without any lag or break.
    private func handleFullScreenStateChange(isCovered: Bool) {
        guard desktopState == .active, let player = desktopPlayer else { return }
        
        if isCovered {
            // Full-screen app is covering the screen: pause player to free 100% GPU/CPU & stop audio
            if !isDesktopSuspendedForFullScreen {
                player.pause()
                isDesktopSuspendedForFullScreen = true
            }
        } else {
            // Returned to desktop / main display: resume playback instantly from current frame
            if isDesktopSuspendedForFullScreen {
                player.play()
                isDesktopSuspendedForFullScreen = false
            }
        }
    }
    
    /// Automatically pauses wallpaper sound when an app is open on the display,
    /// and resumes sound when on the desktop with no open apps.
    private func handleAppDisplayStateChange(isAppOpen: Bool) {
        guard desktopState == .active else { return }
        self.isSoundAutoPausedForApp = isAppOpen
        updateDesktopAudioState()
    }
    
    /// Updates hardware mute state on the desktop player based on manual and automatic settings.
    func updateDesktopAudioState() {
        guard desktopState == .active, let player = desktopPlayer else { return }
        let shouldMute = isDesktopMuted || (autoPauseSoundWhenAppOpen && isSoundAutoPausedForApp)
        player.isMuted = shouldMute
    }
    
    // MARK: - In-Window Preview Pipeline (Glitch-Free & Low Resource)
    
    /// Loads and starts the in-app preview for the specified gallery item.
    func selectForPreview(item: GalleryItem) {
        // If this item is already previewing and the player is active, do nothing
        if selectedPreviewItem?.id == item.id && previewPlayer != nil {
            return
        }
        
        let oldItemID = selectedPreviewItem?.id
        let oldPlayer = previewPlayer
        let oldLooper = previewLooper
        
        // Acquire coordinated security-scoped access
        guard let url = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            errorMessage = "Unable to resolve file path for '\(item.fileName)'."
            return
        }
        
        let asset = AVURLAsset(url: url)
        let templateItem = AVPlayerItem(asset: asset)
        
        // Resource optimization: Limit forward buffer to 1.5 seconds for looping local files
        templateItem.preferredForwardBufferDuration = 1.5
        templateItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        let newPlayer = AVQueuePlayer()
        newPlayer.actionAtItemEnd = .none
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        
        // Keep preview muted if desktop is active to prevent audio collision
        newPlayer.isMuted = isDesktopActive ? true : isPreviewMuted
        newPlayer.volume = previewVolume
        
        let newLooper = AVPlayerLooper(player: newPlayer, templateItem: templateItem)
        
        // Atomically update preview state
        self.selectedPreviewItem = item
        self.previewPlayer = newPlayer
        self.previewLooper = newLooper
        self.isPreviewPlaying = true
        
        newPlayer.play()
        
        // Clean up previous preview resources after new pipeline is live
        oldLooper?.disableLooping()
        oldPlayer?.pause()
        oldPlayer?.removeAllItems()
        if let oldID = oldItemID {
            SecurityScopedResourceManager.shared.stopAccess(forItemID: oldID)
        }
    }
    
    /// Toggles play/pause state of the in-window preview player.
    func togglePreviewPlayback() {
        guard let player = previewPlayer else { return }
        if isPreviewPlaying {
            player.pause()
            isPreviewPlaying = false
        } else {
            player.play()
            isPreviewPlaying = true
        }
    }
    
    /// Pauses preview player to conserve 100% CPU/GPU decode cycles when window is closed or occluded.
    func pausePreview() {
        if isPreviewPlaying {
            previewPlayer?.pause()
            isPreviewPlaying = false
        }
    }
    
    /// Resumes preview player when window returns to visible state.
    func resumePreviewIfAvailable() {
        guard let player = previewPlayer, !isDesktopActive else { return }
        if !isPreviewPlaying {
            player.play()
            isPreviewPlaying = true
        }
    }
    
    /// Toggles audio mute state for the in-window preview player.
    func togglePreviewMute() {
        isPreviewMuted.toggle()
    }
    
    private func teardownPreviewPipeline() {
        let oldItemID = selectedPreviewItem?.id
        previewLooper?.disableLooping()
        previewLooper = nil
        
        if let player = previewPlayer {
            player.pause()
            player.removeAllItems()
        }
        previewPlayer = nil
        isPreviewPlaying = false
        
        if let id = oldItemID {
            SecurityScopedResourceManager.shared.stopAccess(forItemID: id)
        }
    }
    
    // MARK: - Desktop Live Wallpaper Pipeline (Seamless Hand-off & Optimized)
    
    /// Applies the currently previewed item to the desktop behind desktop icons.
    func applyCurrentPreviewToDesktop() {
        guard let item = selectedPreviewItem else {
            errorMessage = "No video selected to apply."
            return
        }
        applyToDesktop(item: item)
    }
    
    /// Applies a specific gallery item directly as the live desktop wallpaper.
    func applyToDesktop(item: GalleryItem) {
        // If this item is already actively running on the desktop, simply resume
        if activeDesktopItem?.id == item.id && desktopPlayer != nil {
            fullScreenMonitor.evaluateCurrentState()
            if fullScreenMonitor.isFullScreenCovered {
                desktopPlayer?.pause()
                isDesktopSuspendedForFullScreen = true
            } else {
                desktopPlayer?.play()
                isDesktopSuspendedForFullScreen = false
            }
            self.isSoundAutoPausedForApp = fullScreenMonitor.isAppOpenOnDisplay
            updateDesktopAudioState()
            desktopState = .active
            return
        }
        
        let oldItemID = activeDesktopItem?.id
        let oldPlayer = desktopPlayer
        let oldLooper = desktopLooper
        
        // Acquire coordinated security-scoped access
        guard let url = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            errorMessage = "Could not resolve file path for '\(item.fileName)'."
            desktopState = .failed(reason: "File resolution failed.")
            return
        }
        
        let asset = AVURLAsset(url: url)
        let templateItem = AVPlayerItem(asset: asset)
        
        // Resource optimization: Limit forward buffer to 2.0s to minimize RAM footprint
        templateItem.preferredForwardBufferDuration = 2.0
        templateItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        let newPlayer = AVQueuePlayer()
        newPlayer.actionAtItemEnd = .none
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        // Critical: Allow macOS display to enter sleep mode normally when idle
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        
        let newLooper = AVPlayerLooper(player: newPlayer, templateItem: templateItem)
        
        self.desktopPlayer = newPlayer
        self.desktopLooper = newLooper
        self.activeDesktopItem = item
        
        // Attach new player directly to the desktop window backing layer
        windowController.showWindow(player: newPlayer)
        fullScreenMonitor.startMonitoring(for: windowController.currentWindow)
        
        if fullScreenMonitor.isFullScreenCovered {
            newPlayer.pause()
            self.isDesktopSuspendedForFullScreen = true
        } else {
            newPlayer.play()
            self.isDesktopSuspendedForFullScreen = false
        }
        
        self.isSoundAutoPausedForApp = fullScreenMonitor.isAppOpenOnDisplay
        let shouldMute = isDesktopMuted || (autoPauseSoundWhenAppOpen && isSoundAutoPausedForApp)
        newPlayer.isMuted = shouldMute
        newPlayer.volume = desktopVolume
        
        self.desktopState = .active
        
        // Resource optimization: Pause preview player so M1 decoder runs ONE stream, not two!
        pausePreview()
        self.isPreviewMuted = true
        
        // Clean up previous desktop player only after new player is active
        oldLooper?.disableLooping()
        oldPlayer?.pause()
        oldPlayer?.removeAllItems()
        if let oldID = oldItemID {
            SecurityScopedResourceManager.shared.stopAccess(forItemID: oldID)
        }
    }
    
    /// Toggles play/pause state for the desktop wallpaper.
    func toggleDesktopPlayback() {
        guard desktopState == .active, let player = desktopPlayer else { return }
        if player.timeControlStatus == .paused {
            player.play()
            isDesktopSuspendedForFullScreen = false
        } else {
            player.pause()
        }
    }
    
    /// Stops the live desktop wallpaper and releases the desktop window.
    func stopDesktopWallpaper() {
        fullScreenMonitor.stopMonitoring()
        isDesktopSuspendedForFullScreen = false
        isSoundAutoPausedForApp = false
        
        let oldItemID = activeDesktopItem?.id
        
        desktopLooper?.disableLooping()
        desktopLooper = nil
        
        if let player = desktopPlayer {
            player.pause()
            player.removeAllItems()
        }
        desktopPlayer = nil
        
        windowController.hideWindow()
        self.activeDesktopItem = nil
        self.desktopState = .idle
        
        if let id = oldItemID {
            SecurityScopedResourceManager.shared.stopAccess(forItemID: id)
        }
    }
    
    // MARK: - Full Teardown & Cleanup
    
    /// Tears down all pipelines, closes windows, and releases all sandbox file access tokens.
    func cleanup() {
        stopDesktopWallpaper()
        teardownPreviewPipeline()
        SecurityScopedResourceManager.shared.releaseAll()
    }
}
