import SwiftUI

/// Stylised selection frame shared by both the live-drag selection phase and
/// the annotation phase. Gives SnapDress the "real screenshot tool" feel:
///
/// - layered border (outer dark shadow stroke + bright white stroke + inner
///   translucent line) so it reads as sharp pixels against any background
/// - eight corner/edge handles like macOS Screenshot / Snipaste / WeChat
/// - pixel-dimension capsule that smartly flips above/below the rect depending
///   on available space
///
/// The frame is purely visual — it does not receive hit tests. Move/resize
/// interactions are wired up in `AnnotationOverlay` / `RegionSelectionOverlay`.
struct SelectionFrame: View {
    let rect: CGRect
    let backingScale: CGFloat
    let overlaySize: CGSize
    var showHandles: Bool = true
    var showDimensions: Bool = true

    /// Accent color for the border & handles. Defaults to a WeChat-style
    /// vivid green which stays readable against almost any wallpaper / UI.
    var accentColor: Color = Color(red: 0.055, green: 0.757, blue: 0.376)

    private let borderWidth: CGFloat = 2.5
    private let handleSize: CGFloat = 9
    private let capsuleHeight: CGFloat = 22

    var body: some View {
        ZStack {
            // Thick accent border — the headline visual.
            Rectangle()
                .strokeBorder(accentColor, lineWidth: borderWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            if showHandles {
                ForEach(HandlePosition.all, id: \.self) { pos in
                    handle
                        .position(pos.point(in: rect))
                }
            }

            if showDimensions {
                dimensionsCapsule
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Handle

    private var handle: some View {
        Rectangle()
            .fill(accentColor)
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
    }

    // MARK: - Dimensions

    private var dimensionsCapsule: some View {
        let w = Int((rect.width * backingScale).rounded())
        let h = Int((rect.height * backingScale).rounded())

        return HStack(spacing: 5) {
            Image(systemName: "viewfinder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentColor)
            Text("\(w) × \(h)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.72))
                .overlay(
                    Capsule()
                        .strokeBorder(accentColor.opacity(0.55), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        .fixedSize()
        .position(dimensionsAnchor)
    }

    /// Prefer placing the capsule **above** the selection, flush-left with the
    /// rect. If there's no room above (selection hugs the top), slip it
    /// inside the selection at the top.
    private var dimensionsAnchor: CGPoint {
        let margin: CGFloat = 8
        let estimatedWidth: CGFloat = 78  // "XXXX × XXXX" worst case
        let halfH = capsuleHeight / 2
        let halfW = estimatedWidth / 2

        // X: flush-left with the rect (i.e. the capsule's left edge sits on
        // rect.minX). Positioning is by center so add halfW. Clamp to screen.
        var x = rect.minX + halfW
        x = min(max(x, halfW + 4), overlaySize.width - halfW - 4)

        // Y: above by default, inside-top if clipped.
        var y = rect.minY - margin - halfH
        if y - halfH < 4 {
            y = rect.minY + margin + halfH
        }
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Handle Positions

private enum HandlePosition: Hashable, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    static let all: [HandlePosition] = [
        .topLeft, .top, .topRight,
        .left, .right,
        .bottomLeft, .bottom, .bottomRight,
    ]

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
