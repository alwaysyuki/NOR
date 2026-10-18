//
//  WallpaperWindowController.swift
//  Wallpaper engine
//

import AppKit
import AVFoundation

/// Backing view for the wallpaper window that hosts an AVPlayerLayer.
/// Using makeBackingLayer() ensures that AVPlayerLayer is the direct backing layer,
/// avoiding redundant CoreAnimation sublayer hierarchies and guaranteeing zero-copy
/// hardware-accelerated video presentation on Apple Silicon.
final class WallpaperPlayerView: NSView {
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Optimization: Never trigger software redraw passes; AVPlayerLayer handles video drawing directly
        layerContentsRedrawPolicy = .never
        layer?.drawsAsynchronously = true
        layer?.isOpaque = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.drawsAsynchronously = true
        layer?.isOpaque = true
    }
    
    override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.drawsAsynchronously = true
        playerLayer.isOpaque = true
        return playerLayer
    }
    
    var playerLayer: AVPlayerLayer {
        guard let layer = self.layer as? AVPlayerLayer else {
            fatalError("WallpaperPlayerView backing layer is not an AVPlayerLayer.")
        }
        return layer
    }
}

/// Manages the borderless desktop-level window positioned behind desktop icons.
@MainActor
final class WallpaperWindowController {
    
    private var window: NSWindow?
    private var playerView: WallpaperPlayerView?
    private var screenChangeObserver: NSObjectProtocol?
    
    var currentWindow: NSWindow? {
        window
    }
    
    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
    
    init() {
        setupScreenChangeObserver()
    }
    
    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Prepares or retrieves the wallpaper window on the target screen.
    func showWindow(player: AVPlayer, on screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) {
        let frame = screen.frame
        
        let targetWindow: NSWindow
        let view: WallpaperPlayerView
        
        if let existingWindow = self.window, let existingView = self.playerView {
            targetWindow = existingWindow
            targetWindow.setFrame(frame, display: true)
            view = existingView
        } else {
            targetWindow = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            
            // Critical desktop integration:
            // 1. Level: kCGDesktopWindowLevelKey sits below desktopIconWindow (-2147483603)
            //    and normal application windows (0).
            targetWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            
            // 2. Collection behaviors:
            //    - canJoinAllSpaces: Appears seamlessly across all virtual desktops/Spaces.
            //    - stationary: Stays anchored during Mission Control / Exposé.
            //    - ignoresCycle: Excluded from Cmd+` window cycling.
            //    - fullScreenAuxiliary: Stays visible when another display or app enters full screen.
            targetWindow.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenAuxiliary
            ]
            
            // 3. Event Handling:
            //    Must ignore all mouse clicks so Finder icons, drag selections,
            //    and desktop context menus work unhindered with 0 hit-test overhead.
            targetWindow.ignoresMouseEvents = true
            
            // 4. Window appearance:
            targetWindow.canHide = false
            targetWindow.hasShadow = false
            targetWindow.isOpaque = true
            targetWindow.backgroundColor = .black
            targetWindow.isReleasedWhenClosed = false
            
            let pView = WallpaperPlayerView(frame: NSRect(origin: .zero, size: frame.size))
            pView.autoresizingMask = [.width, .height]
            targetWindow.contentView = pView
            
            self.window = targetWindow
            self.playerView = pView
            view = pView
        }
        
        view.playerLayer.player = player
        targetWindow.orderFrontRegardless()
    }
    
    /// Hides and dismantles the wallpaper window.
    func hideWindow() {
        playerView?.playerLayer.player = nil
        window?.orderOut(nil)
        window = nil
        playerView = nil
    }
    
    private func setupScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }
    
    private func handleScreenChange() {
        guard let window = self.window,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        window.setFrame(screen.frame, display: true)
    }
}
