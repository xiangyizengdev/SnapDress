#!/usr/bin/env swift

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

// Create bitmap context
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("ERROR: Failed to create CGContext")
    exit(1)
}

// --- macOS squircle background ---
let iconRect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = size * 0.22 // macOS icon corner radius

// Draw rounded rect with gradient
let path = CGPath(roundedRect: iconRect.insetBy(dx: size * 0.02, dy: size * 0.02),
                  cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()

// Blue-purple gradient (#4F46E5 → #7C3AED)
let gradientColors = [
    CGColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0),  // #4F46E5
    CGColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1.0),  // #7C3AED
]
let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])
ctx.restoreGState()

// --- Viewfinder corners (white, representing screenshot capture) ---
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
ctx.setStrokeColor(white)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let vfInset: CGFloat = size * 0.22
let vfRect = iconRect.insetBy(dx: vfInset, dy: vfInset)
let cornerLen: CGFloat = size * 0.12
let lineWidth: CGFloat = size * 0.035
ctx.setLineWidth(lineWidth)

// Top-left corner
ctx.move(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - cornerLen))
ctx.addLine(to: CGPoint(x: vfRect.minX, y: vfRect.maxY))
ctx.addLine(to: CGPoint(x: vfRect.minX + cornerLen, y: vfRect.maxY))
ctx.strokePath()

// Top-right corner
ctx.move(to: CGPoint(x: vfRect.maxX - cornerLen, y: vfRect.maxY))
ctx.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY))
ctx.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.maxY - cornerLen))
ctx.strokePath()

// Bottom-left corner
ctx.move(to: CGPoint(x: vfRect.minX, y: vfRect.minY + cornerLen))
ctx.addLine(to: CGPoint(x: vfRect.minX, y: vfRect.minY))
ctx.addLine(to: CGPoint(x: vfRect.minX + cornerLen, y: vfRect.minY))
ctx.strokePath()

// Bottom-right corner
ctx.move(to: CGPoint(x: vfRect.maxX - cornerLen, y: vfRect.minY))
ctx.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY))
ctx.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + cornerLen))
ctx.strokePath()

// --- Inner rounded rectangle (the "screenshot" being dressed up) ---
let innerInset: CGFloat = size * 0.28
let innerRect = iconRect.insetBy(dx: innerInset, dy: innerInset)
let innerCorner: CGFloat = size * 0.06
let innerPath = CGPath(roundedRect: innerRect,
                       cornerWidth: innerCorner, cornerHeight: innerCorner, transform: nil)

// Semi-transparent white fill
ctx.saveGState()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
ctx.addPath(innerPath)
ctx.fillPath()
ctx.restoreGState()

// White border
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.4))
ctx.setLineWidth(size * 0.012)
ctx.addPath(innerPath)
ctx.strokePath()

// --- Sparkle/diamond decorations (representing "dress up" / beautification) ---

func drawDiamond(ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setFillColor(color)
    ctx.move(to: CGPoint(x: center.x, y: center.y + radius))
    ctx.addLine(to: CGPoint(x: center.x + radius * 0.4, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - radius))
    ctx.addLine(to: CGPoint(x: center.x - radius * 0.4, y: center.y))
    ctx.closePath()
    ctx.fillPath()

    ctx.move(to: CGPoint(x: center.x + radius, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.4))
    ctx.addLine(to: CGPoint(x: center.x - radius, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - radius * 0.4))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

// Large sparkle (top-right area)
drawDiamond(ctx: ctx,
            center: CGPoint(x: size * 0.72, y: size * 0.73),
            radius: size * 0.055,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))

// Medium sparkle
drawDiamond(ctx: ctx,
            center: CGPoint(x: size * 0.62, y: size * 0.82),
            radius: size * 0.032,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))

// Small sparkle
drawDiamond(ctx: ctx,
            center: CGPoint(x: size * 0.80, y: size * 0.62),
            radius: size * 0.022,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))

// --- Save as PNG ---
guard let image = ctx.makeImage() else {
    print("ERROR: Failed to create image")
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    print("ERROR: Failed to create image destination")
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    print("ERROR: Failed to write PNG")
    exit(1)
}

print("Icon saved to \(outputPath)")
