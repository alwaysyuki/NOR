//
//  MenuBarManager.swift
//  Wallpaper engine
//

import AppKit
import Foundation

/// Manages the macOS Menu Bar Status Item with custom Liquid Glass styling,
/// controls dock hiding upon window close (.accessory mode), and provides
/// quick playback controls from the menu bar.
@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate, NSWindowDelegate {
    
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private weak var playbackManager: WallpaperPlaybackManager?
    private weak var galleryManager: WallpaperGalleryManager?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup & Configuration
    
    /// Initializes the NSStatusItem in the system menu bar.
    func setup() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = item.button {
            button.image = LiquidGlassIconFactory.createIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "NŌR"
        }
        
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        
        self.statusItem = item
    }
    
    /// Binds references to the shared playback and gallery managers.
    func configure(playbackManager: WallpaperPlaybackManager, galleryManager: WallpaperGalleryManager) {
        self.playbackManager = playbackManager
        self.galleryManager = galleryManager
    }
    
    /// Registers the main application window to intercept close events.
    func registerMainWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
    }
    
    // MARK: - Window Delegate (Dock Hiding on Close)
    
    /// When the user closes the main window, order it out and switch the app
    /// to `.accessory` activation policy so it disappears from the Dock and
    /// lives exclusively in the Menu Bar.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        
        // Resource optimization: Pause preview player to halt all in-window video decoding
        playbackManager?.pausePreview()
        
        // Hide from macOS Dock (runs as pure menu bar accessory)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    
    /// Restores the app to the macOS Dock, brings the window to the front, and activates it.
    @objc func showMainWindow() {
        // Restore regular activation policy so the app reappears in the Dock
        NSApp.setActivationPolicy(.regular)
        
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Fallback if window reference was not yet registered
            for win in NSApp.windows where win.level == .normal && win.canBecomeKey {
                win.makeKeyAndOrderFront(nil)
                self.mainWindow = win
                break
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSMenuDelegate (Dynamic Menu Construction)
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // 1. Header / Status display item
        let statusTitle: String
        let statusImageName: String
        
        if let pm = playbackManager, pm.isDesktopActive {
            if pm.isDesktopSuspendedForFullScreen {
                statusTitle = "Paused (Full Screen App)"
                statusImageName = "pause.circle.fill"
            } else if pm.isSoundAutoPausedForApp && !pm.isDesktopMuted {
                if let activeItem = pm.activeDesktopItem {
                    statusTitle = "Active (Sound Auto-Paused): \(activeItem.fileName)"
                } else {
                    statusTitle = "Active (Sound Auto-Paused)"
                }
                statusImageName = "play.circle.fill"
            } else if let activeItem = pm.activeDesktopItem {
                statusTitle = "Active: \(activeItem.fileName)"
                statusImageName = "play.circle.fill"
            } else {
                statusTitle = "Wallpaper Active"
                statusImageName = "play.circle.fill"
            }
        } else {
            statusTitle = "NŌR: Idle"
            statusImageName = "stop.circle"
        }
        
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        if let img = NSImage(systemSymbolName: statusImageName, accessibilityDescription: nil) {
            headerItem.image = img
        }
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Open Main Window (reappears in Dock)
        let openItem = NSMenuItem(
            title: "Open NŌR…",
            action: #selector(showMainWindow),
            keyEquivalent: "o"
        )
        openItem.target = self
        if let img = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) {
            openItem.image = img
        }
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Playback Controls
        if let pm = playbackManager, pm.isDesktopActive {
            let isPaused = pm.isDesktopSuspendedForFullScreen || (pm.previewPlayer != nil && !pm.isDesktopPlaying)
            let playPauseTitle = isPaused ? "Resume Live Wallpaper" : "Pause Live Wallpaper"
            let playPauseIcon = isPaused ? "play.fill" : "pause.fill"
            
            let toggleItem = NSMenuItem(
                title: playPauseTitle,
                action: #selector(handleTogglePlayback),
                keyEquivalent: " "
            )
            toggleItem.target = self
            if let img = NSImage(systemSymbolName: playPauseIcon, accessibilityDescription: nil) {
                toggleItem.image = img
            }
            menu.addItem(toggleItem)
            
            let muteTitle = pm.isDesktopMuted ? "Unmute Desktop Audio" : "Mute Desktop Audio"
            let muteIcon = pm.isDesktopMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            let muteItem = NSMenuItem(
                title: muteTitle,
                action: #selector(handleToggleMute),
                keyEquivalent: "m"
            )
            muteItem.target = self
            if let img = NSImage(systemSymbolName: muteIcon, accessibilityDescription: nil) {
                muteItem.image = img
            }
            menu.addItem(muteItem)
            
            let autoPauseItem = NSMenuItem(
                title: "Auto-Pause Sound When Apps Open",
                action: #selector(handleToggleAutoPauseSound),
                keyEquivalent: ""
            )
            autoPauseItem.target = self
            autoPauseItem.state = pm.autoPauseSoundWhenAppOpen ? .on : .off
            if let img = NSImage(systemSymbolName: "speaker.badge.waveform", accessibilityDescription: nil) {
                autoPauseItem.image = img
            }
            menu.addItem(autoPauseItem)
        }
        
        // 4. Wallpaper Selection Submenu
        if let gm = galleryManager, !gm.items.isEmpty {
            let wallpapersMenu = NSMenu(title: "Wallpapers")
            for item in gm.items {
                let menuItem = NSMenuItem(
                    title: item.fileName,
                    action: #selector(handleSelectWallpaper(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item
                if playbackManager?.activeDesktopItem?.id == item.id {
                    menuItem.state = .on
                }
                wallpapersMenu.addItem(menuItem)
            }
            
            let submenuItem = NSMenuItem(title: "Choose Wallpaper", action: nil, keyEquivalent: "")
            submenuItem.submenu = wallpapersMenu
            if let img = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: nil) {
                submenuItem.image = img
            }
            menu.addItem(submenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Quit Application
        let quitItem = NSMenuItem(
            title: "Quit NŌR",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        if let img = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            quitItem.image = img
        }
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc private func handleTogglePlayback() {
        playbackManager?.toggleDesktopPlayback()
    }
    
    @objc private func handleToggleMute() {
        if let pm = playbackManager {
            pm.isDesktopMuted.toggle()
        }
    }
    
    @objc private func handleToggleAutoPauseSound() {
        if let pm = playbackManager {
            pm.autoPauseSoundWhenAppOpen.toggle()
        }
    }
    
    @objc private func handleSelectWallpaper(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? GalleryItem {
            playbackManager?.selectForPreview(item: item)
            playbackManager?.applyToDesktop(item: item)
        }
    }
    
    @objc private func handleQuit() {
        playbackManager?.cleanup()
        NSApp.terminate(nil)
    }
}
