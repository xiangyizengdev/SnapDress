import SwiftUI

struct RegionSelectionOverlay: View {
    @EnvironmentObject var captureState: CaptureState
    let screen: NSScreen

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var finalViewRect: CGRect? = nil
    @State private var hoverPoint: CGPoint? = nil

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private var isAnnotating: Bool {
        captureState.mode == .annotating
    }

    private var snapshot: CGImage? {
        captureState.screenSnapshots[screen.displayID]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Frozen screen snapshot as background. In frozen mode this
                // makes the selection area show a static image instead of
                // live pixels; in live mode it's absent and the overlay stays
                // transparent as before.
                if let snap = snapshot {
                    Image(decorative: snap, scale: screen.backingScaleFactor)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }

                if isAnnotating, finalViewRect != nil {
                    // Annotation mode: show annotation overlay with toolbar.
                    // Binding lets the overlay fine-tune the rect (drag to move,
                    // arrow keys to nudge) and propagate it back here.
                    AnnotationOverlay(
                        selectionRect: Binding(
                            get: { finalViewRect ?? .zero },
                            set: { finalViewRect = $0 }
                        ),
                        overlayBounds: CGRect(origin: .zero, size: geometry.size),
                        screen: screen,
                        onConfirm: { annotations in
                            confirmWithAnnotations(annotations, viewSize: geometry.size)
                        },
                        onCancel: {
                            Task { @MainActor in captureState.cancelCapture() }
                        }
                    )
                } else {
                    // Selection mode: drag to select region
                    selectionView(geometry: geometry)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Selection Phase

    @ViewBuilder
    private func selectionView(geometry: GeometryProxy) -> some View {
        ZStack {
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.3))
                )
                if let rect = selectionRect {
                    context.blendMode = .destinationOut
                    context.fill(Path(rect), with: .color(.white))
                }
            }
            .compositingGroup()

            if let rect = selectionRect {
                // During the active drag we skip handles (the rect is
                // still changing shape). They show up once the user lets
                // go and we transition into annotation mode.
                SelectionFrame(
                    rect: rect,
                    backingScale: screen.backingScaleFactor,
                    overlaySize: geometry.size,
                    showHandles: false,
                    showDimensions: true
                )
            }

            // Pixel magnifier (frozen mode only — we need a static snapshot
            // to crop from). Follows the cursor, flips to the opposite corner
            // when it would clip a screen edge.
            if let snap = snapshot, let pt = hoverPoint {
                MagnifierView(
                    cursorPoint: pt,
                    snapshot: snap,
                    backingScale: screen.backingScaleFactor,
                    overlaySize: geometry.size,
                    dimensionText: selectionRect.map { r in
                        let scale = screen.backingScaleFactor
                        return "\(Int(r.width * scale)) × \(Int(r.height * scale))"
                    }
                )
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
            case .ended:
                hoverPoint = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = value.startLocation
                    }
                    dragCurrent = value.location
                    hoverPoint = value.location
                }
                .onEnded { value in
                    dragCurrent = value.location
                    finishSelection(in: geometry.size)
                }
        )
        .onAppear {
            NSCursor.crosshair.push()
        }
        .onDisappear {
            NSCursor.pop()
        }
    }

    // MARK: - Selection → Annotation

    private func finishSelection(in viewSize: CGSize) {
        guard let rect = selectionRect, rect.width > 10, rect.height > 10 else {
            Task { @MainActor in captureState.cancelCapture() }
            return
        }

        finalViewRect = rect

        let screenFrame = screen.frame
        let screenRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.origin.y + (viewSize.height - rect.maxY),
            width: rect.width,
            height: rect.height
        )

        Task { @MainActor in
            captureState.completeSelection(rect: screenRect, screen: screen)
        }
    }

    // MARK: - Annotation → Capture

    private func confirmWithAnnotations(_ annotations: [Annotation], viewSize: CGSize) {
        // The user may have dragged / nudged the rect while in annotation mode,
        // so recompute the screen-space rect from the current view rect before
        // committing to the capture pipeline.
        let rect = finalViewRect ?? .zero
        let screenFrame = screen.frame
        let updatedScreenRect = CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.origin.y + (viewSize.height - rect.maxY),
            width: rect.width,
            height: rect.height
        )

        Task { @MainActor in
            captureState.confirmAnnotation(
                annotations: annotations,
                updatedScreenRect: updatedScreenRect
            )
        }
    }
}

