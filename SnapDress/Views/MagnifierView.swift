import SwiftUI

/// Floating pixel-level magnifier that follows the cursor during region
/// selection, so the user can snap selection boundaries to pixels even on
/// high-density designs (e.g. Figma artboards).
///
/// The magnifier crops a small patch of the already-captured full-screen
/// snapshot around the cursor and renders it with `.interpolation(.none)`
/// so each source pixel shows up as a crisp block instead of being blurred.
struct MagnifierView: View {
    /// Cursor position in overlay view coordinates.
    let cursorPoint: CGPoint
    /// Full-screen snapshot of this display (pixel space).
    let snapshot: CGImage
    /// Backing scale (points → pixels conversion factor).
    let backingScale: CGFloat
    /// Size of the overlay view (used to flip placement near edges).
    let overlaySize: CGSize
    /// Optional dimension text to show in the footer (e.g. "420 × 280"). When
    /// nil the footer falls back to the cursor's pixel coordinates.
    let dimensionText: String?

    private let viewerSize: CGFloat = 100
    private let footerHeight: CGFloat = 22
    private let zoom: CGFloat = 5
    private var regionPoints: CGFloat { viewerSize / zoom }

    var body: some View {
        VStack(spacing: 0) {
            viewer
            footer
        }
        .frame(width: viewerSize, height: viewerSize + footerHeight)
        .background(Color.black.opacity(0.75))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .position(placement)
        .allowsHitTesting(false)
    }

    // MARK: - Subviews

    private var viewer: some View {
        ZStack {
            if let cropped = crop() {
                Image(decorative: cropped, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: viewerSize, height: viewerSize)
            } else {
                Color.black.opacity(0.6)
                    .frame(width: viewerSize, height: viewerSize)
            }

            // Crosshair in the center — matches the actual cursor pixel.
            Rectangle()
                .fill(Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.9))
                .frame(width: 1, height: viewerSize)
            Rectangle()
                .fill(Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.9))
                .frame(width: viewerSize, height: 1)

            // A single highlighted "target pixel" box for extra precision.
            Rectangle()
                .stroke(Color.yellow.opacity(0.85), lineWidth: 1)
                .frame(width: zoom, height: zoom)
        }
    }

    private var footer: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Helpers

    private var label: String {
        if let dimensionText { return dimensionText }
        let x = Int((cursorPoint.x * backingScale).rounded())
        let y = Int((cursorPoint.y * backingScale).rounded())
        return "(\(x), \(y))"
    }

    private var placement: CGPoint {
        let margin: CGFloat = 24
        let half = viewerSize / 2
        let halfH = (viewerSize + footerHeight) / 2
        let totalH = viewerSize + footerHeight

        // Default: bottom-right quadrant relative to cursor.
        var x = cursorPoint.x + margin + half
        var y = cursorPoint.y + margin + halfH

        // Flip horizontally if it would clip the right edge.
        if x + half > overlaySize.width - 4 {
            x = cursorPoint.x - margin - half
        }
        // Flip vertically if it would clip the bottom edge.
        if y + halfH > overlaySize.height - 4 {
            y = cursorPoint.y - margin - halfH
        }
        // Last-resort clamp in case both flips still overflow (tiny displays).
        x = min(max(x, half + 4), overlaySize.width - half - 4)
        y = min(max(y, halfH + 4), overlaySize.height - totalH / 2 - 4)

        return CGPoint(x: x, y: y)
    }

    private func crop() -> CGImage? {
        let pixelCenterX = cursorPoint.x * backingScale
        let pixelCenterY = cursorPoint.y * backingScale
        let pixelSide = regionPoints * backingScale
        let rect = CGRect(
            x: pixelCenterX - pixelSide / 2,
            y: pixelCenterY - pixelSide / 2,
            width: pixelSide,
            height: pixelSide
        )
        let snapshotBounds = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let clamped = rect.intersection(snapshotBounds)
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return snapshot.cropping(to: clamped)
    }
}
