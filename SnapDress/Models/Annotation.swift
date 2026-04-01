import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case arrow
    case mosaic

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .mosaic: return "squareshape.split.3x3"
        }
    }

    var label: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Circle"
        case .arrow: return "Arrow"
        case .mosaic: return "Mosaic"
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    let color: NSColor = .systemRed
    let lineWidth: CGFloat = 2.5
}
