//
//  FullScreenAppMonitor.swift
//  Wallpaper engine
//

import AppKit
import Foundation

/// Monitors system-wide space transitions, frontmost applications, window occlusion,
/// and on-screen application windows to detect:
/// 1. When a full-screen application covers the display (to suspend video decoding and save 100% GPU/CPU).
/// 2. When any application window is open on the display (to automatically pause wallpaper sound,
///    and resume sound when on the desktop with no open apps).
final class FullScreenAppMonitor {
    
    // MARK: - Callbacks & State
    
    /// Called on the MainActor with `true` when a full-screen app is active/covering the display,
    /// or `false` when the user is back on the desktop.
    var onFullScreenStateChanged: (@MainActor (Bool) -> Void)?
    
    /// Called on the MainActor with `true` when any app window is open/visible on the display,
    /// or `false` when no app windows are open on the main screen (clean desktop).
    var onAppDisplayStateChanged: (@MainActor (Bool) -> Void)?
    
    /// Current evaluated full-screen occlusion state.
    private(set) var isFullScreenCovered: Bool = false
    
    /// Current evaluated state of whether any application window is open on the display.
    private(set) var isAppOpenOnDisplay: Bool = false
    
    // MARK: - Private Observers & Timers
    
    private var workspaceObservers: [NSObjectProtocol] = []
    private var windowOcclusionObserver: NSObjectProtocol?
    private var fallbackTimer: Timer?
    private var delayedCheckTask: Task<Void, Never>?
    
    private weak var targetWindow: NSWindow?
    
    init() {}
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Start / Stop Monitoring
    
    /// Starts monitoring space changes, app activations, and occlusion for the given wallpaper window.
    func startMonitoring(for window: NSWindow?) {
        stopMonitoring()
        self.targetWindow = window
        
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        // Notification triggers that alter application/window visibility on display
        let workspaceNotifications: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        
        for name in workspaceNotifications {
            let observer = wsCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleStateTransitionTrigger()
            }
            workspaceObservers.append(observer)
        }
        
        // Screen layout or resolution changes
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleStateTransitionTrigger()
        }
        workspaceObservers.append(screenObserver)
        
        // Window occlusion notifications (WindowServer hardware occlusion state)
        if let window = window {
            windowOcclusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateCurrentState()
            }
        }
        
        // Fallback timer (1.0s interval with 0.5s tolerance) to catch in-app window close/minimize (Cmd+W, Cmd+M)
        // Setting tolerance allows macOS Apple Silicon power manager to coalesce CPU wakeups efficiently
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluateCurrentState()
        }
        timer.tolerance = 0.5
        fallbackTimer = timer
        
        // Perform initial evaluation immediately
        evaluateCurrentState()
    }
    
    /// Stops all observers and timers.
    func stopMonitoring() {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        
        if let observer = windowOcclusionObserver {
            NotificationCenter.default.removeObserver(observer)
            windowOcclusionObserver = nil
        }
        
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        
        delayedCheckTask?.cancel()
        delayedCheckTask = nil
        
        targetWindow = nil
        isFullScreenCovered = false
        isAppOpenOnDisplay = false
    }
    
    // MARK: - State Evaluation & Transition Handling
    
    /// Handles rapid space swipes and triggers both immediate and post-animation evaluations.
    private func handleStateTransitionTrigger() {
        // Evaluate immediately
        evaluateCurrentState()
        
        // macOS space sliding animation takes ~300ms. Check again right after transition ends
        delayedCheckTask?.cancel()
        delayedCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
            guard !Task.isCancelled else { return }
            self?.evaluateCurrentState()
        }
    }
    
    /// Evaluates whether the desktop is currently obscured by a full-screen app or has any open app windows.
    func evaluateCurrentState() {
        let isCovered = checkIsFullScreenCovered()
        let isAppOpen = isCovered || checkIsAppOpenOnDisplay()
        
        if isCovered != isFullScreenCovered {
            isFullScreenCovered = isCovered
            let callback = onFullScreenStateChanged
            Task { @MainActor in
                callback?(isCovered)
            }
        }
        
        if isAppOpen != isAppOpenOnDisplay {
            isAppOpenOnDisplay = isAppOpen
            let appCallback = onAppDisplayStateChanged
            Task { @MainActor in
                appCallback?(isAppOpen)
            }
        }
    }
    
    /// Checks whether an on-screen window is in full-screen mode covering the target screen.
    private func checkIsFullScreenCovered() -> Bool {
        let targetScreen = targetWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return false }
        
        // 1. Fast-Path: Check WindowServer hardware occlusion state
        // When completely obscured by an opaque window on the active space,
        // macOS WindowServer sets occlusionState visible flag to false with 0 CPU cost.
        if let win = targetWindow, !win.occlusionState.contains(.visible) {
            return true
        }
        
        // 2. Fast-Path: If frontmost application is Finder, user is directly on the desktop
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == "com.apple.finder" {
            return false
        }
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // 3. Fallback: Query WindowServer only if fast paths don't conclude
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        for window in windowList {
            // Only inspect normal application level windows (layer 0)
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            
            // Ignore transparent / invisible windows
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.9 else {
                continue
            }
            
            // Ignore Wallpaper engine's own windows
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard ownerPID != currentPID else {
                continue
            }
            
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner != "Wallpaper engine" && owner != "NŌR" else {
                continue
            }
            
            // Check window bounds against screen dimensions
            if let dict = window[kCGWindowBounds as String] as? [String: Any],
               let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) {
                
                // Allow a small tolerance (6 points) for menu bar auto-hide edges or dock boundaries
                let matchesFullFrame = abs(bounds.width - screenFrame.width) <= 6 && abs(bounds.height - screenFrame.height) <= 6
                let matchesVisibleFrame = abs(bounds.width - visibleFrame.width) <= 6 && abs(bounds.height - visibleFrame.height) <= 6
                
                if matchesFullFrame || matchesVisibleFrame {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Checks whether any application window is currently open and visible on the target display.
    private func checkIsAppOpenOnDisplay() -> Bool {
        let targetScreen = targetWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return false }
        
        // Quartz coordinate system has origin at top-left of primary screen (screens[0])
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenQuartzBounds = CGRect(
            x: screen.frame.origin.x,
            y: primaryScreenHeight - screen.frame.origin.y - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let systemOwners: Set<String> = [
            "Window Server",
            "Dock",
            "SystemUIServer",
            "ControlCenter",
            "NotificationCenter",
            "Spotlight"
        ]
        
        for window in windowList {
            // Normal application windows are layer 0; floating utility panels are layer 3
            guard let layer = window[kCGWindowLayer as String] as? Int, (layer == 0 || layer == 3) else {
                continue
            }
            
            // Ignore transparent / invisible windows
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.5 else {
                continue
            }
            
            // Ignore Wallpaper engine's own windows
            let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard ownerPID != currentPID else {
                continue
            }
            
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner != "Wallpaper engine" && owner != "NŌR" && !systemOwners.contains(owner) else {
                continue
            }
            
            // Check window bounds
            guard let dict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
                continue
            }
            
            // Filter out tiny helper, status, or invisible tracking windows (< 50x50)
            guard bounds.width >= 50 && bounds.height >= 50 else {
                continue
            }
            
            // Ensure window intersects the target display with meaningful visible area
            let intersection = bounds.intersection(screenQuartzBounds)
            guard !intersection.isNull && intersection.width >= 50 && intersection.height >= 50 else {
                continue
            }
            
            // A visible application window is open on this display!
            return true
        }
        
        return false
    }
}
