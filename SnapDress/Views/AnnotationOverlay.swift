import SwiftUI

struct AnnotationOverlay: View {
    @Binding var selectionRect: CGRect
    let overlayBounds: CGRect
    let screen: NSScreen
    let onConfirm: ([Annotation]) -> Void
    let onCancel: () -> Void

    @State private var selectedTool: AnnotationTool? = nil
    @State private var annotations: [Annotation] = []
    @State private var currentAnnotation: Annotation? = nil
    @State private var moveStartRect: CGRect? = nil
    @State private var moveStartAnnotations: [Annotation]? = nil
    @State private var isHoveringSelection: Bool = false
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

            // Selection frame with handles + dimension capsule (shared with
            // the live-drag phase). Gives the selection a proper "screenshot
            // tool" feel instead of a plain stroke.
            SelectionFrame(
                rect: selectionRect,
                backingScale: screen.backingScaleFactor,
                overlaySize: overlayBounds.size,
                showHandles: true,
                showDimensions: true
            )

            // Move handle: covers the selection rect and lets the user drag
            // the whole frame to fine-tune its position. Only active when no
            // annotation tool is selected, so drawing still takes priority.
            moveHandle

            // Annotation canvas
            annotationCanvas

            // Floating toolbar
            toolbar
                .position(toolbarPosition)
        }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
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
                // Clamp inside overlay bounds.
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

    private var toolbarPosition: CGPoint {
        let toolbarHeight: CGFloat = 36
        let margin: CGFloat = 10
        let screenHeight = screen.frame.height

        let y: CGFloat
        // If enough space below selection, place below; otherwise above
        if selectionRect.maxY + margin + toolbarHeight < screenHeight {
            y = selectionRect.maxY + margin + toolbarHeight / 2
        } else {
            y = selectionRect.minY - margin - toolbarHeight / 2
        }

        return CGPoint(x: selectionRect.midX, y: y)
    }

    // MARK: - Annotation Canvas

    private var annotationCanvas: some View {
        ZStack {
            ForEach(annotations) { annotation in
                AnnotationShape(annotation: annotation)
            }
            if let current = currentAnnotation {
                AnnotationShape(annotation: current)
            }

            // Drawing surface
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
                currentAnnotation = Annotation(tool: tool, startPoint: start, endPoint: current)
            }
            .onEnded { value in
                guard let tool = selectedTool else { return }
                let start = clampToSelection(value.startLocation)
                let end = clampToSelection(value.location)
                if hypot(end.x - start.x, end.y - start.y) > 5 {
                    annotations.append(Annotation(tool: tool, startPoint: start, endPoint: end))
                }
                currentAnnotation = nil
            }
    }

    private func clampToSelection(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(selectionRect.minX, min(selectionRect.maxX, point.x)),
            y: max(selectionRect.minY, min(selectionRect.maxY, point.y))
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // Tool buttons
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }
            }

            pill

            // Undo
            Button(action: undoLast) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 30)
                    .foregroundColor(annotations.isEmpty ? .white.opacity(0.3) : .white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(annotations.isEmpty)

            pill

            // Cancel
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            // Confirm
            Button(action: { onConfirm(annotations) }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color(nsColor: .systemBlue))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.65))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTool = (selectedTool == tool) ? nil : tool
            }
        }) {
            Image(systemName: tool.icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedTool == tool ? Color.white.opacity(0.2) : Color.clear)
                )
                .foregroundColor(selectedTool == tool ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var pill: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 5)
    }

    private func undoLast() {
        guard !annotations.isEmpty else { return }
        _ = annotations.removeLast()
    }
}

// MARK: - Annotation Shape Rendering (SwiftUI preview layer)

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
        case .mosaic:
            mosaicShape
        }
    }

    private var rect: CGRect {
        CGRect(
            x: min(annotation.startPoint.x, annotation.endPoint.x),
            y: min(annotation.startPoint.y, annotation.endPoint.y),
            width: abs(annotation.endPoint.x - annotation.startPoint.x),
            height: abs(annotation.endPoint.y - annotation.startPoint.y)
        )
    }

    private var strokeColor: Color {
        Color(nsColor: annotation.color)
    }

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
        ArrowLine(from: annotation.startPoint, to: annotation.endPoint)
            .stroke(strokeColor, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// Mosaic preview: a grid of semi-transparent blocks to indicate the mosaic area
    private var mosaicShape: some View {
        MosaicPreview()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Mosaic Preview (visual hint during drawing, not the actual pixelation)

struct MosaicPreview: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            let cols = max(Int(ceil(size.width / tile)), 1)
            let rows = max(Int(ceil(size.height / tile)), 1)
            for row in 0..<rows {
                for col in 0..<cols {
                    let r = CGRect(
                        x: CGFloat(col) * tile,
                        y: CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    )
                    let opacity = (row + col) % 2 == 0 ? 0.35 : 0.55
                    context.fill(Path(r), with: .color(.gray.opacity(opacity)))
                }
            }
        }
    }
}

// MARK: - Arrow Shape

struct ArrowLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 12
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: to.x - headLength * cos(angle - headAngle),
            y: to.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: to.x - headLength * cos(angle + headAngle),
            y: to.y - headLength * sin(angle + headAngle)
        )

        path.move(to: left)
        path.addLine(to: to)
        path.addLine(to: right)

        return path
    }
}
