import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

class ImageProcessor {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func process(image: CGImage, options: BeautifyOptions) -> NSImage {
        let imageWidth = CGFloat(image.width) - options.inset * 2
        let imageHeight = CGFloat(image.height) - options.inset * 2
        let canvasWidth = imageWidth + options.padding * 2
        let canvasHeight = imageHeight + options.padding * 2

        // Crop the source image by inset
        let croppedImage: CGImage
        if options.inset > 0 {
            let insetRect = CGRect(
                x: options.inset,
                y: options.inset,
                width: max(imageWidth, 1),
                height: max(imageHeight, 1)
            )
            croppedImage = image.cropping(to: insetRect) ?? image
        } else {
            croppedImage = image
        }

        let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)

        // Use NSBitmapImageRep with alpha channel for proper transparency support
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: canvasSize)
        }

        guard let nsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            return NSImage(size: canvasSize)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let ctx = nsContext.cgContext

        // Clear canvas to fully transparent
        ctx.clear(CGRect(origin: .zero, size: canvasSize))

        // 1. Draw background (skip for transparent mode — canvas is already transparent)
        if options.backgroundStyle != .transparent {
            drawBackground(ctx: ctx, canvasSize: canvasSize, sourceImage: croppedImage, options: options)
        }

        // 2. Draw rounded screenshot with shadow
        //    Use a transparency layer so the shadow is generated from the
        //    composited alpha mask — no separate black fill that could bleed
        //    through anti-aliased corners.
        let imageRect = CGRect(
            x: options.padding,
            y: options.padding,
            width: CGFloat(croppedImage.width),
            height: CGFloat(croppedImage.height)
        )

        ctx.saveGState()
        let shadowColor = CGColor(gray: 0, alpha: options.shadowOpacity)
        ctx.setShadow(
            offset: CGSize(width: 0, height: -options.shadowOffsetY),
            blur: options.shadowRadius,
            color: shadowColor
        )
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        let clipPath = CGPath(
            roundedRect: imageRect,
            cornerWidth: options.cornerRadius,
            cornerHeight: options.cornerRadius,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.clip()
        ctx.draw(croppedImage, in: imageRect)

        ctx.endTransparencyLayer()
        ctx.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        let resultImage = NSImage(size: canvasSize)
        resultImage.addRepresentation(bitmapRep)
        return resultImage
    }

    // MARK: - Background Drawing

    private func drawBackground(ctx: CGContext, canvasSize: NSSize, sourceImage: CGImage, options: BeautifyOptions) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        switch options.backgroundStyle {
        case .frostedGlass:
            drawFrostedGlassBackground(ctx: ctx, canvasRect: canvasRect, sourceImage: sourceImage)

        case .white, .dark, .black:
            if let color = options.backgroundStyle.solidCGColor {
                ctx.setFillColor(color)
                ctx.fill([canvasRect])
            }

        case .cool, .nice, .morning, .bright, .love, .rain, .sky,
             .ocean, .forest, .sand, .midnight, .peach:
            let colors = options.backgroundStyle.cgColors
            if colors.count >= 2 {
                drawGradient(ctx: ctx, rect: canvasRect, colors: colors)
            }

        case .customColor:
            let c1 = NSColor(options.customColor1).cgColor
            let c2 = NSColor(options.customColor2).cgColor
            drawGradient(ctx: ctx, rect: canvasRect, colors: [c1, c2])

        case .customImage:
            if let url = options.customImageURL {
                drawImageBackground(ctx: ctx, canvasRect: canvasRect, imageURL: url)
            }

        case .transparent:
            break // handled by caller
        }
    }

    private func drawFrostedGlassBackground(ctx: CGContext, canvasRect: CGRect, sourceImage: CGImage) {
        let ciImage = CIImage(cgImage: sourceImage)
        let clamped = ciImage.clampedToExtent()
        let blurred = clamped.applyingGaussianBlur(sigma: 30)
        // Boost brightness and saturation so the frosted effect is visible
        // even on uniform-color screenshots (e.g. white pages)
        let enhanced = blurred.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.06,
            kCIInputSaturationKey: 1.3
        ])
        let cropped = enhanced.cropped(to: ciImage.extent)

        if let blurredCG = ciContext.createCGImage(cropped, from: ciImage.extent) {
            ctx.saveGState()
            ctx.clip(to: [canvasRect])
            let aspectFill = aspectFillRect(imageSize: CGSize(width: blurredCG.width, height: blurredCG.height), targetRect: canvasRect)
            ctx.draw(blurredCG, in: aspectFill)
            ctx.restoreGState()
        }
    }

    private func drawGradient(ctx: CGContext, rect: CGRect, colors: [CGColor]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return }
        ctx.saveGState()
        ctx.clip(to: [rect])
        ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        ctx.restoreGState()
    }

    private func drawImageBackground(ctx: CGContext, canvasRect: CGRect, imageURL: URL) {
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        ctx.saveGState()
        ctx.clip(to: [canvasRect])
        let fillRect = aspectFillRect(
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            targetRect: canvasRect
        )
        ctx.draw(cgImage, in: fillRect)
        ctx.restoreGState()
    }

    private func aspectFillRect(imageSize: CGSize, targetRect: CGRect) -> CGRect {
        let widthRatio = targetRect.width / imageSize.width
        let heightRatio = targetRect.height / imageSize.height
        let scale = max(widthRatio, heightRatio)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: targetRect.midX - scaledSize.width / 2,
            y: targetRect.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}
