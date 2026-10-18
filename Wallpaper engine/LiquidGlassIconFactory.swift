//
//  LiquidGlassIconFactory.swift
//  Wallpaper engine
//

import AppKit

/// Factory for generating modern, high-DPI vector "Liquid Glass" menu bar icons
/// with fluid meniscus waves and specular glass highlights.
enum LiquidGlassIconFactory {
    
    /// Creates a crisp, vector-rendered liquid glass droplet/orb icon tailored for macOS menu bar.
    static func createIcon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            ctx.saveGState()
            
            let w = rect.width
            let h = rect.height
            let scale = min(w, h) / 18.0
            
            ctx.scaleBy(x: scale, y: scale)
            
            // 1. Outer Glass Orb / Droplet Rim (Smooth glass contour)
            let orbBounds = NSRect(x: 1.5, y: 1.5, width: 15.0, height: 15.0)
            let glassOrb = NSBezierPath(ovalIn: orbBounds)
            ctx.setLineWidth(1.35)
            NSColor.black.withAlphaComponent(0.95).setStroke()
            glassOrb.stroke()
            
            // 2. Liquid Meniscus / Dynamic Fluid Wave inside the lower half
            let wavePath = NSBezierPath()
            wavePath.move(to: NSPoint(x: 2.1, y: 8.5))
            wavePath.curve(
                to: NSPoint(x: 9.0, y: 8.0),
                controlPoint1: NSPoint(x: 4.5, y: 10.5),
                controlPoint2: NSPoint(x: 6.8, y: 6.5)
            )
            wavePath.curve(
                to: NSPoint(x: 15.9, y: 8.5),
                controlPoint1: NSPoint(x: 11.2, y: 9.5),
                controlPoint2: NSPoint(x: 13.5, y: 6.5)
            )
            wavePath.appendArc(
                withCenter: NSPoint(x: 9.0, y: 9.0),
                radius: 6.9,
                startAngle: 0,
                endAngle: 180,
                clockwise: true
            )
            wavePath.close()
            
            NSColor.black.withAlphaComponent(0.85).setFill()
            wavePath.fill()
            
            // 3. Primary Specular Glass Reflection (Curved shine arc on top-left)
            let specularShine = NSBezierPath()
            specularShine.appendArc(
                withCenter: NSPoint(x: 9.0, y: 9.0),
                radius: 5.6,
                startAngle: 105,
                endAngle: 165,
                clockwise: false
            )
            ctx.setLineWidth(1.3)
            ctx.setLineCap(.round)
            NSColor.black.withAlphaComponent(1.0).setStroke()
            specularShine.stroke()
            
            // 4. Secondary Micro Specular Ping (Gleam reflection on bottom-right)
            let gleamDot = NSBezierPath(ovalIn: NSRect(x: 12.0, y: 4.5, width: 1.3, height: 1.3))
            NSColor.black.withAlphaComponent(0.9).setFill()
            gleamDot.fill()
            
            ctx.restoreGState()
            return true
        }
        
        // Setting isTemplate to true lets macOS adapt the icon dynamically
        // for light/dark menu bar modes, selection states, and accent colors.
        image.isTemplate = true
        return image
    }
}
