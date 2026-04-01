import Foundation

enum PreviewPosition: String, CaseIterable, Identifiable {
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
    case topRight = "topRight"
    case topLeft = "topLeft"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        }
    }
}
