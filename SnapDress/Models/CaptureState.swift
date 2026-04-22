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
    @Published var beautifyOptions = BeautifyOptions() {
        didSet {
            // Persist every change so padding / shadow / background /
            // custom color pickers survive restarts. didSet fires only for
            // post-init mutations, so the default assignment doesn't thrash
            // the disk.
            Self.saveBeautifyOptions(beautifyOptions)
        }
    }
    @Published var processedImage: NSImage?

    // Annotation state (shared with overlay)
    @Published var pendingSelectionRect: CGRect? = nil
    @Published var pendingScreen: NSScreen? = nil

    // Frozen per-screen snapshots used when "freeze on capture" is enabled.
    // Keyed by displayID so each overlay window can fetch its own screen's image.
    @Published var screenSnapshots: [CGDirectDisplayID: CGImage] = [:]

    /// Whether to freeze the screen contents while the user is selecting /
    /// annotating. Mirrors the `freezeOnCapture` user default (which is
    /// registered with a default of `true` in AppDelegate).
    private var freezeOnCapture: Bool {
        UserDefaults.standard.bool(forKey: "freezeOnCapture")
    }

    /// Whether the processed image should be tagged as a HiDPI/Retina asset
    /// (NSImage.size in points). When off, the image is exported at 1x like a
    /// regular bitmap. Defaults to off; toggleable from Preferences.
    private var retinaExport: Bool {
        UserDefaults.standard.bool(forKey: "retinaExport")
    }

    /// Backing scale of the screen the most recent capture came from, used by
    /// `updateProcessedImage()` since live edits don't carry a screen ref.
    private var lastBackingScale: CGFloat = 2.0

    private let screenCaptureService = ScreenCaptureService()
    private let imageProcessor = ImageProcessor()
    private var overlayWindows: [NSWindow] = []
    private var editorWindow: EditorWindow?
    private var editorWindowDelegate: EditorWindowDelegateHelper?
    private var floatingPreviewWindow: NSWindow?

    init() {
        let delegate = EditorWindowDelegateHelper()
        self.editorWindowDelegate = delegate
        delegate.onClose = { [weak self] in
            self?.closeEditor()
        }

        // Restore persisted beautify preferences. Assignments inside init
        // don't trigger didSet, so no accidental write-back.
        if let loaded = Self.loadBeautifyOptions() {
            self.beautifyOptions = loaded
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
        // Ensure any leftover floating preview from the previous capture
        // is torn down immediately — otherwise it can still hold focus
        // and contribute to the "first click is eaten" issue when the
        // user triggers a second capture right after the first one.
        dismissFloatingPreview()
        guard mode == .idle else { return }
        mode = .selecting

        if freezeOnCapture {
            // Frozen mode: grab each screen's snapshot first, then show the
            // overlay with that static image as background. The selection
            // area no longer updates while the user is dragging/annotating.
            Task { @MainActor in
                var snapshots: [CGDirectDisplayID: CGImage] = [:]
                for screen in NSScreen.screens {
                    if let snap = try? await screenCaptureService.captureFullScreen(screen: screen) {
                        snapshots[screen.displayID] = snap
                    }
                }
                // Bail out if user cancelled via ESC before snapshots finished.
                guard mode == .selecting else { return }
                if snapshots.isEmpty {
                    mode = .idle
                    return
                }
                screenSnapshots = snapshots
                showOverlayWindows()
            }
        } else {
            // Live mode: show overlay immediately; the actual capture happens
            // after the user confirms (legacy behavior).
            showOverlayWindows()
        }
    }

    func completeSelection(rect: CGRect, screen: NSScreen) {
        pendingSelectionRect = rect
        pendingScreen = screen
        mode = .annotating
    }

    func confirmAnnotation(annotations: [Annotation], updatedScreenRect: CGRect? = nil) {
        // If the overlay moved/nudged the rect during annotation, prefer the
        // updated one over the initial pendingSelectionRect.
        if let updatedScreenRect {
            pendingSelectionRect = updatedScreenRect
        }
        guard let rect = pendingSelectionRect, let screen = pendingScreen else {
            cancelCapture()
            return
        }

        if let snapshot = screenSnapshots[screen.displayID] {
            // Frozen mode: crop directly from the snapshot we took when
            // entering capture. No need to wait for the overlay to disappear
            // because it's not in the source image.
            dismissOverlayWindows()
            guard let cropped = screenCaptureService.cropSnapshot(snapshot, selection: rect, screen: screen) else {
                cancelCapture()
                return
            }
            finalizeCapture(image: cropped, annotations: annotations, rect: rect, screen: screen)
        } else {
            // Live mode: dismiss overlay first, wait a beat for it to clear
            // from the screen, then grab the live pixels.
            dismissOverlayWindows()
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                do {
                    let image = try await screenCaptureService.captureRegion(rect: rect, screen: screen)
                    finalizeCapture(image: image, annotations: annotations, rect: rect, screen: screen)
                } catch {
                    print("Capture failed: \(error)")
                    mode = .idle
                    pendingSelectionRect = nil
                    pendingScreen = nil
                }
            }
        }
    }

    private func finalizeCapture(image: CGImage, annotations: [Annotation], rect: CGRect, screen: NSScreen) {
        let finalImage: CGImage
        if annotations.isEmpty {
            finalImage = image
        } else {
            finalImage = renderAnnotations(annotations, onto: image, selectionRect: rect, screen: screen)
        }

        self.capturedImage = finalImage
        self.mode = .editing(rect)
        self.lastBackingScale = screen.backingScaleFactor

        let processed = imageProcessor.process(
            image: finalImage,
            options: beautifyOptions,
            backingScale: screen.backingScaleFactor,
            useRetinaSize: retinaExport
        )
        self.processedImage = processed
        ExportService.copyToClipboard(image: processed)
        RecentScreenshotsStore.shared.add(image: processed)

        showFloatingPreview(image: processed)

        pendingSelectionRect = nil
        pendingScreen = nil
        screenSnapshots.removeAll()
    }

    func cancelCapture() {
        mode = .idle
        pendingSelectionRect = nil
        pendingScreen = nil
        screenSnapshots.removeAll()
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

        let window = WindowManager.createFloatingPreviewWindow(
            image: image,
            onTap: { [weak self] in
                self?.openEditorFromPreview()
            },
            onDismiss: { [weak self] in
                self?.handleFloatingPreviewExpired()
            }
        )
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        floatingPreviewWindow = window
    }

    /// Called by FloatingPreviewView once its own countdown expires (or the user
    /// dismisses it explicitly). The countdown lives in the view so it can be
    /// paused on hover; here we only need to tear down state.
    private func handleFloatingPreviewExpired() {
        dismissFloatingPreview()
        if case .editing = mode {
            mode = .idle
            capturedImage = nil
            processedImage = nil
        }
    }

    private func dismissFloatingPreview() {
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
        let scale = lastBackingScale
        let retina = retinaExport
        Task.detached { [options = beautifyOptions, processor = imageProcessor] in
            let result = processor.process(
                image: capturedImage,
                options: options,
                backingScale: scale,
                useRetinaSize: retina
            )
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
        // Activate the app BEFORE showing the overlay. Because SnapDress is
        // an LSUIElement agent, it is often not the active app when the
        // global hotkey fires (e.g. user was working in Chrome). If we
        // show the overlay first and activate afterwards, macOS treats the
        // very first mouseDown on the overlay as an "activating click"
        // and swallows it — the user has to click twice to start dragging.
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = WindowManager.createOverlayWindow(for: screen)
            window.onEscape = { [weak self] in
                Task { @MainActor in self?.cancelCapture() }
            }
            let overlayView = RegionSelectionOverlay(screen: screen)
                .environmentObject(self)
            // OverlayHostingView overrides acceptsFirstMouse so the first
            // click is delivered to SwiftUI's DragGesture even if the app
            // hasn't finished activating yet.
            window.contentView = OverlayHostingView(rootView: overlayView)
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
        }

        // Make sure one window is key
        overlayWindows.first?.makeKey()
    }

    private func dismissOverlayWindows() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    // MARK: - Beautify Options Persistence

    private static let beautifyStorageKey = "beautifyOptions.v1"

    fileprivate static func loadBeautifyOptions() -> BeautifyOptions? {
        guard let data = UserDefaults.standard.data(forKey: beautifyStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(BeautifyOptions.self, from: data)
    }

    fileprivate static func saveBeautifyOptions(_ options: BeautifyOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: beautifyStorageKey)
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
