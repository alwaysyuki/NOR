//
//  VideoPreviewView.swift
//  Wallpaper engine
//

import SwiftUI
import AppKit
import AVFoundation

/// Embedded video player view leveraging WallpaperPlayerView's direct AVPlayerLayer backing
/// for hardware-accelerated preview rendering in the SwiftUI interface.
struct VideoPreviewView: NSViewRepresentable {
    let player: AVPlayer?
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    
    func makeNSView(context: Context) -> WallpaperPlayerView {
        let view = WallpaperPlayerView(frame: .zero)
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player
        return view
    }
    
    func updateNSView(_ nsView: WallpaperPlayerView, context: Context) {
        if nsView.playerLayer.videoGravity != videoGravity {
            nsView.playerLayer.videoGravity = videoGravity
        }
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}
