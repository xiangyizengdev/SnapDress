import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case arrow
    case mosaic
    case blur

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .mosaic: return "square.grid.3x3.fill"
        case .blur: return "drop.fill"
        }
    }

    var label: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Circle"
        case .arrow: return "Arrow"
        case .mosaic: return "Mosaic"
        case .blur: return "Blur"
        }
    }

    /// Vector tools honour color + lineWidth. Area-effect tools (mosaic /
    /// blur) ignore them and use blockSize / blurRadius instead.
    var isVector: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow: return true
        case .mosaic, .blur: return false
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    /// Stroke color for vector tools.
    var color: NSColor = .systemRed
    /// Stroke width (in view points) for vector tools. Arrow head dimensions
    /// scale off this — bigger lineWidth ⇒ bigger triangle.
    var lineWidth: CGFloat = 4
    /// Pixel block size for the mosaic tool, in source-image pixels.
    /// Bigger value = chunkier blocks. Used by both preview and final render.
    var blockSize: CGFloat = 12
    /// Gaussian blur sigma for the blur tool, in source-image pixels.
    var blurRadius: CGFloat = 18

    /// Min-corner bounding rect in view coordinates. Useful for area-effect
    /// tools and hit-testing.
    var rect: CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }
}

// MARK: - Annotation Style (UI-side, sticky across tool switches)

/// User's currently selected color + thickness preferences. Persisted
/// across annotation sessions only via SwiftUI @State; resets on app
/// relaunch (intentional — most screenshots want defaults).
struct AnnotationStyle: Equatable {
    var color: NSColor = AnnotationStyle.palette[0]
    var lineWidth: CGFloat = AnnotationStyle.widths[1]
    var blockSize: CGFloat = AnnotationStyle.blockSizes[1]
    var blurRadius: CGFloat = AnnotationStyle.blurRadii[1]

    /// 6-color swatch — covers the standard "annotation red", warm yellow,
    /// success green, info blue, plus pure black/white for high contrast on
    /// any background.
    static let palette: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1.0), // red
        NSColor(srgbRed: 1.00, green: 0.78, blue: 0.0,  alpha: 1.0), // amber
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), // green
        NSColor(srgbRed: 0.0,  green: 0.48, blue: 1.0,  alpha: 1.0), // blue
        .black,
        .white,
    ]

    /// thin / medium / thick stroke widths in view points.
    static let widths: [CGFloat] = [2.5, 4, 6]

    /// small / medium / large block size for mosaic, in source pixels.
    static let blockSizes: [CGFloat] = [8, 14, 22]

    /// soft / medium / strong blur radius for blur tool, in source pixels.
    static let blurRadii: [CGFloat] = [10, 18, 30]
}
