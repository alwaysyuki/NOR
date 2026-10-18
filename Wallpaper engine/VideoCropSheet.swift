//
//  VideoCropSheet.swift
//  Wallpaper engine
//

import SwiftUI
import AVFoundation

/// Interactive modal sheet that allows users to crop any video wallpaper to Mac Display (16:10),
/// 16:9, 21:9, 1:1, or custom aspect ratios with real-time visual framing controls.
struct VideoCropSheet: View {
    let item: GalleryItem
    @Bindable var galleryManager: WallpaperGalleryManager
    @Bindable var playbackManager: WallpaperPlaybackManager
    var onDismiss: () -> Void
    
    @State private var selectedPreset: CropPreset = .macScreen
    @State private var panX: Double = 0.5 // 0.0 = Left, 0.5 = Center, 1.0 = Right
    @State private var panY: Double = 0.5 // 0.0 = Top, 0.5 = Center, 1.0 = Bottom
    @State private var zoomScale: Double = 1.0 // 1.0 to 2.5x
    
    @State private var thumbnailImage: NSImage?
    @State private var isCropping: Bool = false
    @State private var cropProgress: Double = 0.0
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header: Always visible, never cropped
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "crop")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text("Crop Video Wallpaper")
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
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isCropping)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            
            Divider()
            
            // Scrollable / Flexible Middle Body to accommodate all window sizes
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    // Left Column: Interactive Visual Crop Canvas
                    VStack(spacing: 8) {
                        cropCanvasView
                            .frame(width: 390, height: 240)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        // Dimension readout
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Original: \(Int(item.resolutionWidth)) × \(Int(item.resolutionHeight))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Cropped: \(Int(computedCropRect.width)) × \(Int(computedCropRect.height)) (\(selectedPreset.rawValue))")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                            
                            Button("Center") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    panX = 0.5
                                    panY = 0.5
                                    zoomScale = 1.0
                                }
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                            .disabled(isCropping)
                        }
                        .padding(.horizontal, 2)
                    }
                    
                    // Right Column: Controls & Presets
                    VStack(alignment: .leading, spacing: 12) {
                        // Aspect Ratio Preset Selector
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aspect Ratio Preset")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Picker("Aspect Ratio", selection: $selectedPreset) {
                                ForEach(CropPreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .disabled(isCropping)
                        }
                        
                        Divider()
                        
                        // Zoom / Scale Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Zoom / Framing Scale")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.1fx", zoomScale))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $zoomScale, in: 1.0...2.5, step: 0.05)
                                .controlSize(.small)
                                .disabled(isCropping)
                        }
                        
                        // Horizontal Pan Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Horizontal Position (Pan X)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                HStack(spacing: 6) {
                                    Button("L") { panX = 0.0 }.controlSize(.mini).buttonStyle(.borderless)
                                    Button("C") { panX = 0.5 }.controlSize(.mini).buttonStyle(.borderless)
                                    Button("R") { panX = 1.0 }.controlSize(.mini).buttonStyle(.borderless)
                                }
                            }
                            Slider(value: $panX, in: 0.0...1.0)
                                .controlSize(.small)
                                .disabled(isCropping)
                        }
                        
                        // Vertical Pan Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Vertical Position (Pan Y)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                HStack(spacing: 6) {
                                    Button("Top") { panY = 0.0 }.controlSize(.mini).buttonStyle(.borderless)
                                    Button("Mid") { panY = 0.5 }.controlSize(.mini).buttonStyle(.borderless)
                                    Button("Btm") { panY = 1.0 }.controlSize(.mini).buttonStyle(.borderless)
                                }
                            }
                            Slider(value: $panY, in: 0.0...1.0)
                                .controlSize(.small)
                                .disabled(isCropping)
                        }
                    }
                    .frame(width: 230)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
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
            
            // Progress Bar when cropping
            if isCropping {
                VStack(spacing: 4) {
                    ProgressView(value: cropProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("Cropping with Apple Silicon hardware acceleration… \(Int(cropProgress * 100))%")
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
                    onDismiss()
                }
                .buttonStyle(.plain)
                .disabled(isCropping)
                
                Spacer()
                
                Button {
                    startCropping()
                } label: {
                    Label(
                        isCropping ? "Cropping…" : "Crop & Save to Gallery",
                        systemImage: "crop"
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isCropping)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 650, idealWidth: 680, maxWidth: 720)
        .frame(minHeight: 420, idealHeight: 460, maxHeight: 520)
        .background(.background)
        .task {
            thumbnailImage = await galleryManager.thumbnail(for: item)
        }
    }
    
    // MARK: - Crop Math
    
    private var computedCropRect: CGRect {
        let origW = item.resolutionWidth > 0 ? item.resolutionWidth : 1920
        let origH = item.resolutionHeight > 0 ? item.resolutionHeight : 1080
        let origRatio = origW / origH
        let targetRatio = selectedPreset.aspectRatio ?? origRatio
        
        var cropW: CGFloat
        var cropH: CGFloat
        
        if origRatio > targetRatio {
            cropH = origH / zoomScale
            cropW = cropH * targetRatio
        } else {
            cropW = origW / zoomScale
            cropH = cropW / targetRatio
        }
        
        if cropW > origW {
            cropW = origW
            cropH = cropW / targetRatio
        }
        if cropH > origH {
            cropH = origH
            cropW = cropH * targetRatio
        }
        
        let maxOffsetX = max(0, origW - cropW)
        let maxOffsetY = max(0, origH - cropH)
        
        let originX = maxOffsetX * panX
        let originY = maxOffsetY * panY
        
        return CGRect(x: originX, y: originY, width: cropW, height: cropH)
    }
    
    // MARK: - Visual Crop Canvas
    
    private var cropCanvasView: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let origW = item.resolutionWidth > 0 ? item.resolutionWidth : 1920
            let origH = item.resolutionHeight > 0 ? item.resolutionHeight : 1080
            
            // Calculate aspect-fit frame for the video within canvas
            let scale = min(canvasSize.width / origW, canvasSize.height / origH)
            let fittedW = origW * scale
            let fittedH = origH * scale
            let fittedOriginX = (canvasSize.width - fittedW) / 2
            let fittedOriginY = (canvasSize.height - fittedH) / 2
            
            // Normalized crop coordinates
            let crop = computedCropRect
            let cropScaleX = fittedW / origW
            let cropScaleY = fittedH / origH
            let cropViewRect = CGRect(
                x: fittedOriginX + (crop.origin.x * cropScaleX),
                y: fittedOriginY + (crop.origin.y * cropScaleY),
                width: crop.width * cropScaleX,
                height: crop.height * cropScaleY
            )
            
            ZStack(alignment: .topLeading) {
                // Video frame thumbnail
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                } else {
                    ProgressView()
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
                
                // Darkened Shroud outside the crop area (Masking)
                Canvas { context, size in
                    let fullPath = Path(CGRect(origin: .zero, size: size))
                    let cropPath = Path(cropViewRect)
                    
                    var maskPath = fullPath
                    maskPath.addPath(cropPath)
                    
                    // Fill darkened shroud with even-odd rule
                    context.fill(maskPath, with: .color(Color.black.opacity(0.65)), style: FillStyle(eoFill: true))
                }
                
                // Glowing Crop Frame Border
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.cyan, lineWidth: 2)
                    .frame(width: cropViewRect.width, height: cropViewRect.height)
                    .position(x: cropViewRect.midX, y: cropViewRect.midY)
                    .shadow(color: .cyan.opacity(0.6), radius: 4)
                
                // 3x3 Rule-of-Thirds Grid Lines
                ZStack {
                    // Vertical lines
                    Path { p in
                        let w1 = cropViewRect.minX + cropViewRect.width / 3.0
                        let w2 = cropViewRect.minX + (cropViewRect.width * 2.0) / 3.0
                        p.move(to: CGPoint(x: w1, y: cropViewRect.minY))
                        p.addLine(to: CGPoint(x: w1, y: cropViewRect.maxY))
                        p.move(to: CGPoint(x: w2, y: cropViewRect.minY))
                        p.addLine(to: CGPoint(x: w2, y: cropViewRect.maxY))
                    }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // Horizontal lines
                    Path { p in
                        let h1 = cropViewRect.minY + cropViewRect.height / 3.0
                        let h2 = cropViewRect.minY + (cropViewRect.height * 2.0) / 3.0
                        p.move(to: CGPoint(x: cropViewRect.minX, y: h1))
                        p.addLine(to: CGPoint(x: cropViewRect.maxX, y: h1))
                        p.move(to: CGPoint(x: cropViewRect.minX, y: h2))
                        p.addLine(to: CGPoint(x: cropViewRect.maxX, y: h2))
                    }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isCropping else { return }
                        let dx = value.translation.width / max(1, fittedW - cropViewRect.width)
                        let dy = value.translation.height / max(1, fittedH - cropViewRect.height)
                        panX = max(0.0, min(1.0, panX + Double(dx) * 0.05))
                        panY = max(0.0, min(1.0, panY + Double(dy) * 0.05))
                    }
            )
        }
    }
    
    // MARK: - Execution
    
    private func startCropping() {
        guard let sourceURL = SecurityScopedResourceManager.shared.startAccess(for: item) else {
            errorMessage = "Could not resolve file access for '\(item.fileName)'."
            return
        }
        
        isCropping = true
        errorMessage = nil
        cropProgress = 0.0
        
        let destinationURL = galleryManager.croppedWallpapersDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let cropRect = computedCropRect
        let originalFileName = item.fileName
        
        Task {
            defer {
                SecurityScopedResourceManager.shared.stopAccess(for: item)
            }
            
            do {
                try await VideoCropService.cropVideo(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    cropRect: cropRect
                ) { progress in
                    Task { @MainActor in
                        self.cropProgress = progress
                    }
                }
                
                // Import the cropped wallpaper into the local gallery
                if let newItem = await galleryManager.importCroppedWallpaper(
                    croppedFileURL: destinationURL,
                    originalFileName: originalFileName
                ) {
                    playbackManager.selectForPreview(item: newItem)
                }
                
                isCropping = false
                onDismiss()
            } catch {
                errorMessage = "Cropping failed: \(error.localizedDescription)"
                isCropping = false
            }
        }
    }
}
