import SwiftUI
import ScreenCaptureKit
import KeyboardShortcuts
import CoreImage
import CoreImage.CIFilterBuiltins

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
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
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
    ///
    /// Render order:
    /// 1. Original screenshot (in CG y-up coords).
    /// 2. Mosaic / blur effects (Core Image filters), drawn while the
    ///    context is still y-up so we can composite cropped CGImages.
    /// 3. Vector strokes (rect / ellipse / arrow), after flipping the
    ///    context to a y-down (top-left origin) coordinate system that
    ///    matches the SwiftUI annotation points.
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

        // 1. Base screenshot
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let selOriginX = selectionRect.origin.x - screen.frame.origin.x
        let selOriginY = screen.frame.height - selectionRect.maxY + screen.frame.origin.y

        // Convert one annotation's view-points endpoints into the image's
        // top-left-origin pixel rect. Used for both effect cropping and
        // vector path geometry.
        func imagePixelRect(for ann: Annotation) -> CGRect {
            let sx = (ann.startPoint.x - selOriginX) * scale
            let sy = (ann.startPoint.y - selOriginY) * scale
            let ex = (ann.endPoint.x - selOriginX) * scale
            let ey = (ann.endPoint.y - selOriginY) * scale
            return CGRect(
                x: min(sx, ex),
                y: min(sy, ey),
                width: abs(ex - sx),
                height: abs(ey - sy)
            )
        }

        // 2. Effect tools (mosaic / blur) — y-up coordinate composite.
        for ann in annotations where ann.tool == .mosaic || ann.tool == .blur {
            let rect = imagePixelRect(for: ann).integral
            let clamped = rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard !clamped.isEmpty,
                  let cropped = image.cropping(to: clamped) else { continue }

            let effected: CGImage?
            switch ann.tool {
            case .mosaic:
                effected = pixellate(cropped, blockSize: max(2, ann.blockSize * scale))
            case .blur:
                effected = gaussianBlur(cropped, sigma: max(2, ann.blurRadius * scale))
            default:
                effected = nil
            }

            guard let effected else { continue }
            let yUpRect = CGRect(
                x: clamped.minX,
                y: CGFloat(h) - clamped.maxY,
                width: clamped.width,
                height: clamped.height
            )
            ctx.draw(effected, in: yUpRect)
        }

        // 3. Vector strokes — flip to y-down (matches SwiftUI coords).
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        for ann in annotations where ann.tool.isVector {
            let sx = (ann.startPoint.x - selOriginX) * scale
            let sy = (ann.startPoint.y - selOriginY) * scale
            let ex = (ann.endPoint.x - selOriginX) * scale
            let ey = (ann.endPoint.y - selOriginY) * scale
            let lineWidth = ann.lineWidth * scale

            ctx.setStrokeColor(ann.color.cgColor)
            ctx.setFillColor(ann.color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            switch ann.tool {
            case .ellipse:
                let rect = CGRect(
                    x: min(sx, ex), y: min(sy, ey),
                    width: abs(ex - sx), height: abs(ey - sy)
                )
                ctx.strokeEllipse(in: rect)

            case .rectangle:
                let rect = CGRect(
                    x: min(sx, ex), y: min(sy, ey),
                    width: abs(ex - sx), height: abs(ey - sy)
                )
                ctx.stroke(rect)

            case .arrow:
                drawSolidArrow(
                    ctx: ctx,
                    from: CGPoint(x: sx, y: sy),
                    to: CGPoint(x: ex, y: ey),
                    bodyWidth: lineWidth,
                    scale: scale
                )

            default:
                break
            }
        }

        return ctx.makeImage() ?? image
    }

    // MARK: - Effect Filters

    /// Mosaic effect using CIPixellate (GPU-accelerated). `blockSize` is in
    /// source pixels.
    private func pixellate(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = ci
        filter.scale = Float(blockSize)
        filter.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return ciContext.createCGImage(out, from: ci.extent)
    }

    /// Gaussian blur via Core Image. `sigma` is in source pixels.
    /// `clampedToExtent()` keeps edges from going transparent.
    private func gaussianBlur(_ image: CGImage, sigma: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ci.clampedToExtent()
        filter.radius = Float(sigma)
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return ciContext.createCGImage(out, from: ci.extent)
    }

    /// Draw a closed-polygon arrow (body + filled triangle head) into the
    /// current ctx (assumed to be in y-down / top-left coordinates). Geometry
    /// matches `SolidArrowShape` so what the user sees in the overlay is
    /// what gets baked into the screenshot.
    private func drawSolidArrow(
        ctx: CGContext,
        from: CGPoint,
        to: CGPoint,
        bodyWidth: CGFloat,
        scale: CGFloat
    ) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 0.5 else { return }

        let angle = atan2(dy, dx)
        let perp = angle + .pi / 2
        let cosP = cos(perp), sinP = sin(perp)

        let headLen = min(len * 0.65, bodyWidth * 4.5)
        let headHalfWidth = max(bodyWidth * 1.7, bodyWidth + 3 * scale)
        let bodyHalf = bodyWidth / 2
        let bodyEndRatio = max(0, 1 - headLen / len)
        let bodyEnd = CGPoint(
            x: from.x + dx * bodyEndRatio,
            y: from.y + dy * bodyEndRatio
        )

        let p1 = CGPoint(x: from.x + bodyHalf * cosP, y: from.y + bodyHalf * sinP)
        let p2 = CGPoint(x: from.x - bodyHalf * cosP, y: from.y - bodyHalf * sinP)
        let p3 = CGPoint(x: bodyEnd.x - bodyHalf * cosP, y: bodyEnd.y - bodyHalf * sinP)
        let p4 = CGPoint(x: bodyEnd.x - headHalfWidth * cosP, y: bodyEnd.y - headHalfWidth * sinP)
        let p5 = to
        let p6 = CGPoint(x: bodyEnd.x + headHalfWidth * cosP, y: bodyEnd.y + headHalfWidth * sinP)
        let p7 = CGPoint(x: bodyEnd.x + bodyHalf * cosP, y: bodyEnd.y + bodyHalf * sinP)

        ctx.beginPath()
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.addLine(to: p3)
        ctx.addLine(to: p4)
        ctx.addLine(to: p5)
        ctx.addLine(to: p6)
        ctx.addLine(to: p7)
        ctx.closePath()
        ctx.fillPath()
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
