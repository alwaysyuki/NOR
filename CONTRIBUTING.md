# Contributing to NŌR 🎨

Thank you for your interest in contributing to **NŌR**! We welcome all contributions — whether it's reporting a bug, improving documentation, designing new features, or optimizing video rendering performance.

---

## Code of Conduct

We are committed to providing a welcoming, diverse, and harassment-free environment for everyone. Please be respectful, constructive, and collaborative in all discussions and pull requests.

---

## Getting Started

### Prerequisites

- **macOS**: Sonoma (14.0) or higher (macOS Sequoia 15+ recommended)
- **Xcode**: 15.0 or higher (supports Swift 5.9+)
- **Hardware**: Apple Silicon (M1/M2/M3/M4) or Intel Mac
- **Optional**: [FFmpeg](https://ffmpeg.org/) for MKV/WebM fast stream transcoding (`brew install ffmpeg`)

### Cloning & Building Locally

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/Wallpaper-Engine-NOR.git
   cd Wallpaper-Engine-NOR
   ```

2. **Open in Xcode:**
   ```bash
   open "Wallpaper engine.xcodeproj"
   ```

3. **Or build via Terminal using `xcodebuild`:**
   ```bash
   xcodebuild -scheme "Wallpaper engine" -configuration Debug build
   ```

---

## Project Architecture Overview

When contributing code, please respect the separation of concerns:

| Source File | Responsibility |
|---|---|
| `Wallpaper_engineApp.swift` | App entry point and window lifecycle management. |
| `ContentView.swift` | Primary SwiftUI UI (Sidebar gallery, main video preview, desktop controls). |
| `WallpaperWindowController.swift` | Desktop-level window orchestration (`kCGDesktopWindowLevel`) and zero-copy `AVPlayerLayer` backing. |
| `WallpaperPlaybackManager.swift` | AVFoundation player state, seamless looping, volume control, and preview coordination. |
| `WallpaperGalleryManager.swift` | Local library persistence, custom metadata, and secure bookmark storage. |
| `FullScreenAppMonitor.swift` | Space transition detection, window occlusion state, automatic video freeze & audio ducking. |
| `AnimatedImageConverter.swift` | Native ImageIO + AVAssetWriter hardware encoder for GIF, WebP, and APNG loops. |
| `VideoFormatConverter.swift` | High-speed remuxing for MKV/WebM via VideoToolbox and FFmpeg. |
| `VideoCropSheet.swift` / `VideoTrimSheet.swift` | Native sheets for non-destructive video clipping and aspect ratio adjustments. |
| `MenuBarManager.swift` | Menu Bar extra companion for instant wallpaper control. |

---

## Coding Standards

- **Swift Concurrency**: Use `async/await` and `@MainActor` for UI-bound state and AppKit window controllers.
- **Resource Management**: Live video rendering must never leak memory or cause excessive CPU usage. Always clean up player observers and layer allocations when tearing down or pausing.
- **No Hardcoded Absolute Paths**: Always use `FileManager`, `URL`, or security-scoped bookmark APIs for user files.
- **Keep User Settings Safe**: Never commit Xcode user data (`xcuserdata/`) or local developer certificates.

---

## Submitting a Pull Request

1. Create a feature branch:
   ```bash
   git checkout -b feature/my-awesome-feature
   ```
2. Commit your changes with clear, descriptive commit messages:
   ```bash
   git commit -m "feat: add multi-monitor independent wallpaper support"
   ```
3. Push to your fork:
   ```bash
   git push origin feature/my-awesome-feature
   ```
4. Open a Pull Request on GitHub against the `main` branch. Describe your changes clearly and link any associated issues.
