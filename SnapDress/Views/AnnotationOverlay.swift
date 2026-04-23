import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shared GPU-backed Core Image context. CIContext is thread-safe and
/// expensive to construct, so we keep one process-wide instance and let
/// detached tasks reach it directly without crossing actor boundaries.
private let annotationCIContext = CIContext(options: [.useSoftwareRenderer: false])

struct AnnotationOverlay: View {
    @Binding var selectionRect: CGRect
    let overlayBounds: CGRect
    let screen: NSScreen
    /// Frozen full-screen snapshot. Required for WYSIWYG mosaic / blur
    /// previews; if `nil` (live mode) those tools render a flat placeholder.
    let snapshot: CGImage?
    let onConfirm: ([Annotation]) -> Void
    let onCancel: () -> Void

    @State private var selectedTool: AnnotationTool? = nil
    @State private var style = AnnotationStyle()
    @State private var annotations: [Annotation] = []
    @State private var redoStack: [Annotation] = []
    @State private var currentAnnotation: Annotation? = nil
    @State private var moveStartRect: CGRect? = nil
    @State private var moveStartAnnotations: [Annotation]? = nil
    @State private var isHoveringSelection: Bool = false
    @State private var pixellatedImage: NSImage? = nil
    @State private var blurredImage: NSImage? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed background with cut-out
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.3))
                )
                context.blendMode = .destinationOut
                context.fill(
                    Path(selectionRect),
                    with: .color(.white)
                )
            }
            .compositingGroup()
            .allowsHitTesting(false)

            // Mosaic / blur effect layers — show the actual pixellated /
            // blurred screen content through a mask of mosaic/blur rects so
            // the user sees exactly what the export will look like.
            mosaicLayer
            blurLayer

            // Selection frame with handles + dimension capsule.
            SelectionFrame(
                rect: selectionRect,
                backingScale: screen.backingScaleFactor,
                overlaySize: overlayBounds.size,
                showHandles: true,
                showDimensions: true
            )

            // Move handle: drag the whole selection when no tool is selected.
            moveHandle

            // Vector annotations canvas (rect / circle / arrow).
            annotationCanvas

            // Floating toolbar — toolbar row position is stable regardless of
            // whether the style row is showing, so picking a tool never causes
            // the toolbar to jump. The style row is positioned independently
            // below it.
            toolbar
                .position(x: selectionRect.midX, y: toolbarRowY)

            if let tool = selectedTool {
                styleRow(for: tool)
                    // .id forces SwiftUI to fully tear down the old style row
                    // and rebuild a fresh one on every tool change. Without
                    // this, the conditional-content diff sometimes left stale
                    // swatches visible after switching tools.
                    .id(tool.rawValue)
                    .position(x: selectionRect.midX, y: styleRowY)
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .task(id: snapshotIdentity) { await regenerateEffectImages() }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
            let delta: CGSize
            switch press.key {
            case .upArrow: delta = CGSize(width: 0, height: -step)
            case .downArrow: delta = CGSize(width: 0, height: step)
            case .leftArrow: delta = CGSize(width: -step, height: 0)
            case .rightArrow: delta = CGSize(width: step, height: 0)
            default: return .ignored
            }
            nudge(by: delta)
            return .handled
        }
        .onKeyPress(keys: ["z"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) {
                redoLast()
            } else {
                undoLast()
            }
            return .handled
        }
    }

    // MARK: - Effect Image Generation (mosaic / blur previews)

    /// Lightweight identity used to drive `.task(id:)`. Triggers a regenerate
    /// only when the snapshot itself changes (between captures).
    private var snapshotIdentity: Int {
        guard let s = snapshot else { return 0 }
        return s.width &* 31 &+ s.height
    }

    private func regenerateEffectImages() async {
        guard let snap = snapshot else {
            pixellatedImage = nil
            blurredImage = nil
            return
        }
        async let pix = Self.pixellate(snap, blockSize: style.blockSize)
        async let blur = Self.gaussianBlur(snap, sigma: style.blurRadius)
        let (p, b) = await (pix, blur)
        await MainActor.run {
            pixellatedImage = p
            blurredImage = b
        }
    }

    private static func pixellate(_ image: CGImage, blockSize: CGFloat) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            let ci = CIImage(cgImage: image)
            let filter = CIFilter.pixellate()
            filter.inputImage = ci
            filter.scale = Float(max(2, blockSize))
            filter.center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
            guard let out = filter.outputImage?.cropped(to: ci.extent),
                  let cg = annotationCIContext.createCGImage(out, from: ci.extent) else {
                return nil
            }
            return NSImage(cgImage: cg, size: .zero)
        }.value
    }

    private static func gaussianBlur(_ image: CGImage, sigma: CGFloat) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            let ci = CIImage(cgImage: image)
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ci.clampedToExtent()
            filter.radius = Float(max(2, sigma))
            guard let out = filter.outputImage?.cropped(to: ci.extent),
                  let cg = annotationCIContext.createCGImage(out, from: ci.extent) else {
                return nil
            }
            return NSImage(cgImage: cg, size: .zero)
        }.value
    }

    @ViewBuilder
    private var mosaicLayer: some View {
        if let img = pixellatedImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: overlayBounds.width, height: overlayBounds.height)
                .mask(mask(for: .mosaic))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var blurLayer: some View {
        if let img = blurredImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: overlayBounds.width, height: overlayBounds.height)
                .mask(mask(for: .blur))
                .allowsHitTesting(false)
        }
    }

    private func mask(for tool: AnnotationTool) -> some View {
        Canvas { ctx, _ in
            for ann in annotations where ann.tool == tool {
                ctx.fill(Path(ann.rect), with: .color(.white))
            }
            if let cur = currentAnnotation, cur.tool == tool {
                ctx.fill(Path(cur.rect), with: .color(.white))
            }
        }
        .frame(width: overlayBounds.width, height: overlayBounds.height)
    }

    // MARK: - Move Handle

    @ViewBuilder
    private var moveHandle: some View {
        if selectedTool == nil {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)
                .onHover { hovering in
                    isHoveringSelection = hovering
                    if hovering, moveStartRect == nil {
                        NSCursor.openHand.set()
                    } else if !hovering, moveStartRect == nil {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(moveGesture)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if moveStartRect == nil {
                    moveStartRect = selectionRect
                    moveStartAnnotations = annotations
                    NSCursor.closedHand.set()
                }
                guard let startRect = moveStartRect,
                      let startAnn = moveStartAnnotations else { return }

                var target = startRect.offsetBy(
                    dx: value.translation.width,
                    dy: value.translation.height
                )
                let minX = overlayBounds.minX
                let maxX = overlayBounds.maxX - target.width
                let minY = overlayBounds.minY
                let maxY = overlayBounds.maxY - target.height
                target.origin.x = min(max(target.origin.x, minX), maxX)
                target.origin.y = min(max(target.origin.y, minY), maxY)
                selectionRect = target

                let dx = target.minX - startRect.minX
                let dy = target.minY - startRect.minY
                annotations = startAnn.map { shift($0, dx: dx, dy: dy) }
            }
            .onEnded { _ in
                moveStartRect = nil
                moveStartAnnotations = nil
                NSCursor.openHand.set()
            }
    }

    private func nudge(by delta: CGSize) {
        var target = selectionRect.offsetBy(dx: delta.width, dy: delta.height)
        let maxX = overlayBounds.maxX - target.width
        let maxY = overlayBounds.maxY - target.height
        target.origin.x = min(max(target.origin.x, overlayBounds.minX), maxX)
        target.origin.y = min(max(target.origin.y, overlayBounds.minY), maxY)
        let dx = target.minX - selectionRect.minX
        let dy = target.minY - selectionRect.minY
        selectionRect = target
        annotations = annotations.map { shift($0, dx: dx, dy: dy) }
    }

    private func shift(_ a: Annotation, dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = a
        copy.startPoint.x += dx
        copy.startPoint.y += dy
        copy.endPoint.x += dx
        copy.endPoint.y += dy
        return copy
    }

    // MARK: - Toolbar Position

    private static let toolbarHeight: CGFloat = 44
    private static let styleRowHeight: CGFloat = 40
    private static let toolbarRowSpacing: CGFloat = 6
    private static let toolbarMargin: CGFloat = 10
    private static let buttonSize: CGFloat = 36

    /// Y of the toolbar row's centre. Always reserves space below for the
    /// style row even when no tool is selected, so the toolbar position is
    /// stable across tool switches (no jumping).
    private var toolbarRowY: CGFloat {
        let stackHeight = Self.toolbarHeight + Self.toolbarRowSpacing + Self.styleRowHeight
        let screenHeight = screen.frame.height
        if selectionRect.maxY + Self.toolbarMargin + stackHeight < screenHeight {
            return selectionRect.maxY + Self.toolbarMargin + Self.toolbarHeight / 2
        } else {
            return selectionRect.minY - Self.toolbarMargin - stackHeight + Self.toolbarHeight / 2
        }
    }

    private var styleRowY: CGFloat {
        toolbarRowY + Self.toolbarHeight / 2 + Self.toolbarRowSpacing + Self.styleRowHeight / 2
    }

    // MARK: - Annotation Canvas (vector layer)

    private var annotationCanvas: some View {
        ZStack {
            // Finished vector annotations — drawingGroup rasters them
            // offscreen so subsequent drags don't trigger a re-render of
            // every shape every frame.
            ZStack {
                ForEach(annotations.filter { $0.tool.isVector }) { annotation in
                    AnnotationShape(annotation: annotation)
                }
            }
            .drawingGroup()

            // The annotation currently being drawn — rendered live.
            if let current = currentAnnotation, current.tool.isVector {
                AnnotationShape(annotation: current)
            }

            // Drawing surface (transparent hit area).
            Color.clear
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .allowsHitTesting(selectedTool != nil)
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let tool = selectedTool else { return }
                let start = clampToSelection(value.startLocation)
                let current = clampToSelection(value.location)
                currentAnnotation = makeAnnotation(tool: tool, from: start, to: current)
            }
            .onEnded { value in
                guard let tool = selectedTool else { return }
                let start = clampToSelection(value.startLocation)
                let end = clampToSelection(value.location)
                if hypot(end.x - start.x, end.y - start.y) > 5 {
                    annotations.append(makeAnnotation(tool: tool, from: start, to: end))
                    redoStack.removeAll()
                }
                currentAnnotation = nil
            }
    }

    private func makeAnnotation(tool: AnnotationTool, from: CGPoint, to: CGPoint) -> Annotation {
        Annotation(
            tool: tool,
            startPoint: from,
            endPoint: to,
            color: style.color,
            lineWidth: style.lineWidth,
            blockSize: style.blockSize,
            blurRadius: style.blurRadius
        )
    }

    private func clampToSelection(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(selectionRect.minX, min(selectionRect.maxX, point.x)),
            y: max(selectionRect.minY, min(selectionRect.maxY, point.y))
        )
    }

    // MARK: - Toolbar Row

    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool)
            }

            divider

            Button(action: undoLast) {
                toolbarIcon("arrow.uturn.backward",
                            enabled: !annotations.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(annotations.isEmpty)
            .help("Undo (⌘Z)")

            Button(action: redoLast) {
                toolbarIcon("arrow.uturn.forward",
                            enabled: !redoStack.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(redoStack.isEmpty)
            .help("Redo (⌘⇧Z)")

            divider

            cancelButton
            confirmButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(toolbarBackground)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .foregroundColor(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("Cancel (Esc)")
    }

    private var confirmButton: some View {
        Button(action: { onConfirm(annotations) }) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.62, blue: 1.0),
                            Color(red: 0.0,  green: 0.42, blue: 0.95),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.05),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.7
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.0, green: 0.42, blue: 0.95).opacity(0.45),
                        radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .help("Confirm (Return)")
    }

    private func toolbarIcon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .foregroundColor(enabled ? .white.opacity(0.78) : .white.opacity(0.22))
    }

    /// Dark Glass v2: deeper base + subtle gradient hairline that fades
    /// top-to-bottom, giving a soft "lit from above" sheen without GPU
    /// backdrop blur.
    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Color(white: 0.11, opacity: 0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.04),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            )
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = selectedTool == tool
        // Vector tools tint the selected background with the current ink
        // colour — gives the user an instant visual readout of what they're
        // about to draw without needing to scan the style row.
        let selectedFill: Color = (isSelected && tool.isVector)
            ? Color(nsColor: style.color).opacity(0.28)
            : (isSelected ? Color.white.opacity(0.16) : .clear)
        let borderOpacity: Double = isSelected ? 0.22 : 0
        let iconColor: Color = isSelected ? .white : .white.opacity(0.65)
        return Button(action: {
            selectedTool = isSelected ? nil : tool
        }) {
            Group {
                if tool == .mosaic {
                    // SF Symbols don't have a true "mosaic" icon — every grid
                    // glyph reads as "app drawer". This hand-painted 4x4 pixel
                    // tile communicates pixelation directly.
                    MosaicIcon(color: iconColor)
                } else {
                    Image(systemName: tool.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(iconColor)
                }
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(borderOpacity),
                                          lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(tool.label)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 6)
    }

    // MARK: - Style Row (color / width / size, context-aware)

    @ViewBuilder
    private func styleRow(for tool: AnnotationTool) -> some View {
        HStack(spacing: 10) {
            if tool.isVector {
                colorSwatches
                divider
                widthSwatches
            } else if tool == .mosaic {
                granularitySwatches(values: AnnotationStyle.blockSizes,
                                    selected: style.blockSize) { value in
                    style.blockSize = value
                    Task { await regenerateEffectImages() }
                }
            } else if tool == .blur {
                granularitySwatches(values: AnnotationStyle.blurRadii,
                                    selected: style.blurRadius) { value in
                    style.blurRadius = value
                    Task { await regenerateEffectImages() }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(toolbarBackground)
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }

    private var colorSwatches: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationStyle.palette.indices, id: \.self) { i in
                let color = AnnotationStyle.palette[i]
                let isSelected = style.color == color
                Button(action: { style.color = color }) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: color))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                            )
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 1.6)
                                .frame(width: 26, height: 26)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var widthSwatches: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationStyle.widths.indices, id: \.self) { i in
                let width = AnnotationStyle.widths[i]
                let isSelected = style.lineWidth == width
                Button(action: { style.lineWidth = width }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? Color.white.opacity(0.18) : .clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.22 : 0),
                                                  lineWidth: 0.5)
                            )
                            .frame(width: 32, height: 30)
                        // Horizontal line sample — communicates "stroke
                        // width" more directly than a varying circle.
                        Capsule()
                            .fill(isSelected
                                  ? Color(nsColor: style.color)
                                  : Color.white.opacity(0.6))
                            .frame(width: 18, height: width)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func granularitySwatches(values: [CGFloat], selected: CGFloat, onSelect: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                let value = values[i]
                let label = ["S", "M", "L"][i]
                let isSelected = selected == value
                Button(action: { onSelect(value) }) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(width: 36, height: 30)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Color.white.opacity(0.18) : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Color.white.opacity(isSelected ? 0.22 : 0),
                                                      lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Undo / Redo

    private func undoLast() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        redoStack.append(removed)
    }

    private func redoLast() {
        guard !redoStack.isEmpty else { return }
        let restored = redoStack.removeLast()
        annotations.append(restored)
    }
}

// MARK: - Mosaic Icon

/// Hand-painted 4x4 pixel tile for the mosaic toolbar button. SF Symbols'
/// grid glyphs all read as "app drawer"; this one actually communicates
/// pixelation by varying per-cell opacity.
private struct MosaicIcon: View {
    let color: Color
    var size: CGFloat = 16

    /// Opacities tuned by hand: dispersed enough to look noisy, no two
    /// neighbours equal, biased slightly toward the brighter end so the
    /// icon doesn't feel "muddy" on a dark toolbar.
    private static let pattern: [Double] = [
        0.95, 0.35, 0.70, 0.50,
        0.45, 0.85, 0.25, 0.65,
        0.75, 0.30, 0.95, 0.55,
        0.30, 0.75, 0.45, 0.90
    ]

    var body: some View {
        Canvas { context, geo in
            let cell = geo.width / 4
            for i in 0..<16 {
                let row = CGFloat(i / 4)
                let col = CGFloat(i % 4)
                let rect = CGRect(x: col * cell, y: row * cell,
                                  width: cell, height: cell)
                context.fill(Path(rect),
                             with: .color(color.opacity(Self.pattern[i])))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Annotation Shape Rendering

struct AnnotationShape: View {
    let annotation: Annotation

    var body: some View {
        switch annotation.tool {
        case .ellipse:
            ellipseShape
        case .rectangle:
            rectangleShape
        case .arrow:
            arrowShape
        case .mosaic, .blur:
            // Area-effect tools render via the mask layer in
            // AnnotationOverlay; nothing to draw on the vector canvas.
            EmptyView()
        }
    }

    private var rect: CGRect { annotation.rect }
    private var strokeColor: Color { Color(nsColor: annotation.color) }

    private var ellipseShape: some View {
        Ellipse()
            .stroke(strokeColor, lineWidth: annotation.lineWidth)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var rectangleShape: some View {
        Rectangle()
            .stroke(strokeColor, lineWidth: annotation.lineWidth)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var arrowShape: some View {
        SolidArrowShape(
            from: annotation.startPoint,
            to: annotation.endPoint,
            bodyWidth: annotation.lineWidth
        )
        .fill(strokeColor)
    }
}

// MARK: - Solid Arrow (closed polygon — body + filled triangle head)

struct SolidArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let bodyWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 0.5 else { return path }

        let angle = atan2(dy, dx)
        let perp = angle + .pi / 2

        // Head dimensions scale with the chosen line width — keeps the
        // proportions readable across thin / medium / thick strokes.
        let headLen = min(len * 0.65, bodyWidth * 4.5)
        let headHalfWidth = max(bodyWidth * 1.7, bodyWidth + 3)
        let bodyHalf = bodyWidth / 2

        // Where the body stops and the triangle head begins.
        let bodyEndRatio = max(0, 1 - headLen / len)
        let bodyEnd = CGPoint(
            x: from.x + dx * bodyEndRatio,
            y: from.y + dy * bodyEndRatio
        )

        // 7-vertex closed polygon: rounded-tail rectangle + arrowhead.
        let cosP = cos(perp), sinP = sin(perp)

        let p1 = CGPoint(x: from.x + bodyHalf * cosP, y: from.y + bodyHalf * sinP)
        let p2 = CGPoint(x: from.x - bodyHalf * cosP, y: from.y - bodyHalf * sinP)
        let p3 = CGPoint(x: bodyEnd.x - bodyHalf * cosP, y: bodyEnd.y - bodyHalf * sinP)
        let p4 = CGPoint(x: bodyEnd.x - headHalfWidth * cosP, y: bodyEnd.y - headHalfWidth * sinP)
        let p5 = to
        let p6 = CGPoint(x: bodyEnd.x + headHalfWidth * cosP, y: bodyEnd.y + headHalfWidth * sinP)
        let p7 = CGPoint(x: bodyEnd.x + bodyHalf * cosP, y: bodyEnd.y + bodyHalf * sinP)

        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.addLine(to: p5)
        path.addLine(to: p6)
        path.addLine(to: p7)
        path.closeSubpath()
        return path
    }
}
