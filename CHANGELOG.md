# Changelog

All notable changes to **NŌR (Live Wallpaper Engine for macOS)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-10-18

### Added
- **Native Live Wallpaper Engine**:
  - Full-screen desktop rendering positioned behind desktop icons using custom `NSWindow` and direct `AVPlayerLayer` backing.
  - Seamless zero-stutter video looping with hardware acceleration on Apple Silicon and Intel GPUs.
- **Intelligent Resource & Battery Management (`FullScreenAppMonitor`)**:
  - Automatically suspends video rendering and decoding when full-screen apps, games, or presentations cover the display, saving 100% GPU/CPU overhead.
  - Automatic audio ducking: Mutes wallpaper audio when any application window is active on the display, and smoothly resumes audio when returning to a clear desktop.
- **Built-in Video Editing Tools**:
  - **Non-destructive Video Trimmer**: Interactive scrubbing sheet with millisecond precision, start/end trimming, and immediate live preview.
  - **Interactive Video Crop Tool**: Aspect ratio cropping with quick presets (16:9, 16:10, 21:9 Ultrawide) and manual bounding box adjustment.
- **Universal Media Converter**:
  - **Zero-Dependency Animated Image Converter**: Converts GIF, animated WebP, and APNG files directly to hardware-accelerated MP4 loops via native Apple `ImageIO` and `AVAssetWriter`.
  - **High-speed Transcoder / Remuxer**: Seamless support for MKV, WebM, AVI, and FLV containers with automatic FFmpeg detection and Apple Silicon VideoToolbox acceleration.
- **macOS Menu Bar Companion (`MenuBarManager`)**:
  - Status item offering one-click playback toggles, mute controls, wallpaper switching, preferences access, and quit options.
- **Modern SwiftUI Interface**:
  - Two-pane split design featuring a responsive local gallery on the left and dynamic video preview with comprehensive desktop controls on the right.
  - Support for custom wallpaper metadata, display modes, launch-at-login integration, and volume control.
  - Secure permission persistence across app launches via macOS Security-Scoped Bookmarks.
