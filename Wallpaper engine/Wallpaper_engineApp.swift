//
//  Wallpaper_engineApp.swift
//  Wallpaper engine
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarManager.shared.setup()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarManager.shared.showMainWindow()
        return true
    }
}

@main
struct Wallpaper_engineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var playbackManager = WallpaperPlaybackManager()
    @State private var galleryManager = WallpaperGalleryManager()
    
    var body: some Scene {
        Window("NŌR", id: "main-window") {
            ContentView(
                playbackManager: playbackManager,
                galleryManager: galleryManager
            )
            .onAppear {
                MenuBarManager.shared.configure(
                    playbackManager: playbackManager,
                    galleryManager: galleryManager
                )
            }
        }
        .defaultSize(width: 880, height: 600)
    }
}
