import SwiftUI

struct RegionSelectionOverlay: View {
    @EnvironmentObject var captureState: CaptureState
    let screen: NSScreen

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var finalViewRect: CGRect? = nil

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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isAnnotating, let rect = finalViewRect {
                    // Annotation mode: show annotation overlay with toolbar
                    AnnotationOverlay(
                        selectionRect: rect,
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
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                let w = Int(rect.width * screen.backingScaleFactor)
                let h = Int(rect.height * screen.backingScaleFactor)
                Text("\(w) × \(h)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: rect.midX, y: rect.maxY + 20)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = value.startLocation
                    }
                    dragCurrent = value.location
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
        Task { @MainActor in
            captureState.confirmAnnotation(annotations: annotations)
        }
    }
}

