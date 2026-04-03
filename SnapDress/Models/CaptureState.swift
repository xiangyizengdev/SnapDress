import SwiftUI
import ScreenCaptureKit
import KeyboardShortcuts

enum AppMode: Equatable {
    case idle
    case selecting
    case annotating
    case editing(CGRect)

    static func == (lhs: AppMode, rhs: AppMode) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.selecting, .selecting): return true
        case (.annotating, .annotating): return true
        case (.editing, .editing): return true
        default: return false
        }
    }
}

@MainActor
class CaptureState: ObservableObject {
    @Published var mode: AppMode = .idle
    @Published var capturedImage: CGImage?
    @Published var beautifyOptions = BeautifyOptions()
    @Published var processedImage: NSImage?

    // Annotation state (shared with overlay)
    @Published var pendingSelectionRect: CGRect? = nil
    @Published var pendingScreen: NSScreen? = nil

    private let screenCaptureService = ScreenCaptureService()
    private let imageProcessor = ImageProcessor()
    private var overlayWindows: [NSWindow] = []
    private var editorWindow: EditorWindow?
    private var editorWindowDelegate: EditorWindowDelegateHelper?
    private var floatingPreviewWindow: NSWindow?
    private var floatingPreviewDismissTask: Task<Void, Never>?

    init() {
        let delegate = EditorWindowDelegateHelper()
        self.editorWindowDelegate = delegate
        delegate.onClose = { [weak self] in
            self?.closeEditor()
        }

        // Defer keyboard shortcut registration to avoid accessing
        // @StateObject before it's installed on a View.
        DispatchQueue.main.async { [weak self] in
            KeyboardShortcuts.onKeyUp(for: .captureRegion) { [weak self] in
                Task { @MainActor in
                    self?.startCapture()
                }
            }
        }
    }

    func startCapture() {
        if case .editing = mode {
            closeEditor()
        }
        guard mode == .idle else { return }
        mode = .selecting
        showOverlayWindows()
    }

    func completeSelection(rect: CGRect, screen: NSScreen) {
        pendingSelectionRect = rect
        pendingScreen = screen
        mode = .annotating
    }

    func confirmAnnotation(annotations: [Annotation]) {
        guard let rect = pendingSelectionRect, let screen = pendingScreen else {
            cancelCapture()
            return
        }

        dismissOverlayWindows()

        Task {
            try? await Task.sleep(for: .milliseconds(150))

            do {
                let image = try await screenCaptureService.captureRegion(rect: rect, screen: screen)

                let finalImage: CGImage
                if annotations.isEmpty {
                    finalImage = image
                } else {
                    finalImage = renderAnnotations(annotations, onto: image, selectionRect: rect, screen: screen)
                }

                self.capturedImage = finalImage
                self.mode = .editing(rect)

                let processed = imageProcessor.process(image: finalImage, options: beautifyOptions)
                self.processedImage = processed
                ExportService.copyToClipboard(image: processed)

                showFloatingPreview(image: processed)
            } catch {
                print("Capture failed: \(error)")
                self.mode = .idle
            }

            pendingSelectionRect = nil
            pendingScreen = nil
        }
    }

    func cancelCapture() {
        mode = .idle
        pendingSelectionRect = nil
        pendingScreen = nil
        dismissOverlayWindows()
    }

    func closeEditor() {
        editorWindow?.orderOut(nil)
        mode = .idle
        capturedImage = nil
        processedImage = nil

        // Switch back to accessory mode (hide dock icon)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Floating Preview

    private func showFloatingPreview(image: NSImage) {
        dismissFloatingPreview()

        let window = WindowManager.createFloatingPreviewWindow(image: image) { [weak self] in
            self?.openEditorFromPreview()
        }
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        floatingPreviewWindow = window

        // Auto dismiss after 3 seconds
        floatingPreviewDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            dismissFloatingPreview()
            // If user didn't open editor, go back to idle
            if case .editing = mode {
                mode = .idle
                capturedImage = nil
                processedImage = nil
            }
        }
    }

    private func dismissFloatingPreview() {
        floatingPreviewDismissTask?.cancel()
        floatingPreviewDismissTask = nil
        guard let window = floatingPreviewWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
        floatingPreviewWindow = nil
    }

    func openEditorFromPreview() {
        dismissFloatingPreview()
        showEditor()
    }

    private func showEditor() {
        if editorWindow == nil {
            let window = WindowManager.createEditorWindow(captureState: self)
            window.delegate = editorWindowDelegate
            window.onClose = { [weak self] in self?.closeEditor() }
            self.editorWindow = window
        }

        // Switch to regular app so keyboard shortcuts (Cmd+W etc.) work
        NSApp.setActivationPolicy(.regular)
        editorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateProcessedImage() {
        guard let capturedImage else { return }
        Task.detached { [options = beautifyOptions, processor = imageProcessor] in
            let result = processor.process(image: capturedImage, options: options)
            await MainActor.run {
                self.processedImage = result
            }
        }
    }

    // MARK: - Annotation Rendering

    /// Renders annotations onto the captured CGImage.
    /// Annotations use SwiftUI view coordinates (top-left origin, points),
    /// which must be converted to pixel coordinates relative to the image.
    private func renderAnnotations(_ annotations: [Annotation], onto image: CGImage, selectionRect: CGRect, screen: NSScreen) -> CGImage {
        let scale = screen.backingScaleFactor
        let w = image.width
        let h = image.height

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Flip to top-left origin for annotation drawing (matches SwiftUI coordinate system)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let selOriginX = selectionRect.origin.x - screen.frame.origin.x
        let selOriginY = screen.frame.height - selectionRect.maxY + screen.frame.origin.y

        for annotation in annotations {
            let startX = (annotation.startPoint.x - selOriginX) * scale
            let startY = (annotation.startPoint.y - selOriginY) * scale
            let endX = (annotation.endPoint.x - selOriginX) * scale
            let endY = (annotation.endPoint.y - selOriginY) * scale

            switch annotation.tool {
            case .mosaic:
                let mosaicRect = CGRect(
                    x: min(startX, endX),
                    y: min(startY, endY),
                    width: abs(endX - startX),
                    height: abs(endY - startY)
                )
                renderMosaic(ctx: ctx, image: image, rect: mosaicRect)

            default:
                ctx.setStrokeColor(annotation.color.cgColor)
                ctx.setLineWidth(annotation.lineWidth * scale)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)

                switch annotation.tool {
                case .ellipse:
                    let rect = CGRect(
                        x: min(startX, endX),
                        y: min(startY, endY),
                        width: abs(endX - startX),
                        height: abs(endY - startY)
                    )
                    ctx.strokeEllipse(in: rect)

                case .rectangle:
                    let rect = CGRect(
                        x: min(startX, endX),
                        y: min(startY, endY),
                        width: abs(endX - startX),
                        height: abs(endY - startY)
                    )
                    ctx.stroke(rect)

                case .arrow:
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: startX, y: startY))
                    ctx.addLine(to: CGPoint(x: endX, y: endY))
                    ctx.strokePath()

                    let angle = atan2(endY - startY, endX - startX)
                    let headLength: CGFloat = 12 * scale
                    let headAngle: CGFloat = .pi / 6

                    let left = CGPoint(
                        x: endX - headLength * cos(angle - headAngle),
                        y: endY - headLength * sin(angle - headAngle)
                    )
                    let right = CGPoint(
                        x: endX - headLength * cos(angle + headAngle),
                        y: endY - headLength * sin(angle + headAngle)
                    )

                    ctx.beginPath()
                    ctx.move(to: left)
                    ctx.addLine(to: CGPoint(x: endX, y: endY))
                    ctx.addLine(to: right)
                    ctx.strokePath()

                default:
                    break
                }
            }
        }

        return ctx.makeImage() ?? image
    }

    /// Pixelates a rectangular region of the image by sampling block averages.
    private func renderMosaic(ctx: CGContext, image: CGImage, rect: CGRect) {
        let blockSize = 10
        let imgW = image.width
        let imgH = image.height

        // Clamp rect to image bounds
        let x0 = max(0, Int(rect.minX))
        let y0 = max(0, Int(rect.minY))
        let x1 = min(imgW, Int(rect.maxX))
        let y1 = min(imgH, Int(rect.maxY))

        guard x1 > x0, y1 > y0 else { return }

        // Get pixel data from the original image
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return }

        let bpp = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        var blockY = y0
        while blockY < y1 {
            let bh = min(blockSize, y1 - blockY)
            var blockX = x0
            while blockX < x1 {
                let bw = min(blockSize, x1 - blockX)

                // Sample average color from original image data
                var rSum: UInt64 = 0, gSum: UInt64 = 0, bSum: UInt64 = 0
                var count: UInt64 = 0
                for py in blockY..<(blockY + bh) {
                    for px in blockX..<(blockX + bw) {
                        let offset = py * bytesPerRow + px * bpp
                        rSum += UInt64(ptr[offset])
                        gSum += UInt64(ptr[offset + 1])
                        bSum += UInt64(ptr[offset + 2])
                        count += 1
                    }
                }

                if count > 0 {
                    let r = CGFloat(rSum / count) / 255.0
                    let g = CGFloat(gSum / count) / 255.0
                    let b = CGFloat(bSum / count) / 255.0

                    let fillRect = CGRect(x: blockX, y: blockY, width: bw, height: bh)
                    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                    ctx.fill([fillRect])
                }

                blockX += blockSize
            }
            blockY += blockSize
        }
    }

    // MARK: - Overlay Window Management

    private func showOverlayWindows() {
        for screen in NSScreen.screens {
            let window = WindowManager.createOverlayWindow(for: screen)
            window.onEscape = { [weak self] in
                Task { @MainActor in self?.cancelCapture() }
            }
            let overlayView = RegionSelectionOverlay(screen: screen)
                .environmentObject(self)
            window.contentView = NSHostingView(rootView: overlayView)
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        // Make sure one window is key
        overlayWindows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlayWindows() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }
}

// MARK: - Editor Window Delegate

private class EditorWindowDelegateHelper: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            onClose?()
        }
    }
}
