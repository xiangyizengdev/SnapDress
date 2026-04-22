import SwiftUI

enum BackgroundStyle: String, CaseIterable, Identifiable, Codable {
    // Special
    case frostedGlass
    // Solid
    case white
    case dark
    case black
    // Gradients (original)
    case cool
    case nice
    case morning
    case bright
    case love
    case rain
    case sky
    // Gradients (new)
    case ocean
    case forest
    case sand
    case midnight
    case peach
    // Transparent
    case transparent
    // Custom
    case customColor
    case customImage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frostedGlass: return "Desktop"
        case .white: return "White"
        case .dark: return "Dark"
        case .black: return "Black"
        case .cool: return "Cool"
        case .nice: return "Nice"
        case .morning: return "Morning"
        case .bright: return "Bright"
        case .love: return "Love"
        case .rain: return "Rain"
        case .sky: return "Sky"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .sand: return "Sand"
        case .midnight: return "Midnight"
        case .peach: return "Peach"
        case .transparent: return "None"
        case .customColor: return "Custom"
        case .customImage: return "Image"
        }
    }

    /// Thumbnail colors for the preset picker.
    var thumbnailColors: [Color] {
        switch self {
        case .frostedGlass: return [.blue.opacity(0.4), .purple.opacity(0.4)]
        case .white: return [.white]
        case .dark: return [Color(white: 0.15)]
        case .black: return [.black]
        case .cool: return [Color(red: 0.3, green: 0.7, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.9)]
        case .nice: return [Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.95, green: 0.4, blue: 0.3)]
        case .morning: return [Color(red: 1.0, green: 0.55, blue: 0.25), Color(red: 0.95, green: 0.75, blue: 0.3)]
        case .bright: return [Color(red: 0.55, green: 0.3, blue: 0.95), Color(red: 0.3, green: 0.6, blue: 1.0)]
        case .love: return [Color(red: 0.85, green: 0.15, blue: 0.5), Color(red: 0.6, green: 0.1, blue: 0.7)]
        case .rain: return [Color(red: 0.3, green: 0.8, blue: 0.9), Color(red: 0.5, green: 0.6, blue: 1.0)]
        case .sky: return [Color(red: 0.6, green: 0.85, blue: 1.0), Color(red: 0.75, green: 0.6, blue: 0.95)]
        case .ocean: return [Color(red: 0.05, green: 0.2, blue: 0.5), Color(red: 0.1, green: 0.6, blue: 0.7)]
        case .forest: return [Color(red: 0.1, green: 0.5, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.2)]
        case .sand: return [Color(red: 0.85, green: 0.65, blue: 0.4), Color(red: 0.95, green: 0.85, blue: 0.7)]
        case .midnight: return [Color(red: 0.15, green: 0.05, blue: 0.3), Color(red: 0.05, green: 0.05, blue: 0.15)]
        case .peach: return [Color(red: 1.0, green: 0.7, blue: 0.65), Color(red: 1.0, green: 0.85, blue: 0.7)]
        case .transparent: return [Color(nsColor: .controlBackgroundColor)]
        case .customColor: return [.blue, .purple]
        case .customImage: return [.gray.opacity(0.3)]
        }
    }

    /// CG colors for the image processor gradient.
    var cgColors: [CGColor] {
        switch self {
        case .cool: return [CGColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1), CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)]
        case .nice: return [CGColor(red: 0.95, green: 0.25, blue: 0.5, alpha: 1), CGColor(red: 0.95, green: 0.4, blue: 0.3, alpha: 1)]
        case .morning: return [CGColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1), CGColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1)]
        case .bright: return [CGColor(red: 0.55, green: 0.3, blue: 0.95, alpha: 1), CGColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)]
        case .love: return [CGColor(red: 0.85, green: 0.15, blue: 0.5, alpha: 1), CGColor(red: 0.6, green: 0.1, blue: 0.7, alpha: 1)]
        case .rain: return [CGColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 1), CGColor(red: 0.5, green: 0.6, blue: 1.0, alpha: 1)]
        case .sky: return [CGColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1), CGColor(red: 0.75, green: 0.6, blue: 0.95, alpha: 1)]
        case .ocean: return [CGColor(red: 0.05, green: 0.2, blue: 0.5, alpha: 1), CGColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1)]
        case .forest: return [CGColor(red: 0.1, green: 0.5, blue: 0.3, alpha: 1), CGColor(red: 0.05, green: 0.3, blue: 0.2, alpha: 1)]
        case .sand: return [CGColor(red: 0.85, green: 0.65, blue: 0.4, alpha: 1), CGColor(red: 0.95, green: 0.85, blue: 0.7, alpha: 1)]
        case .midnight: return [CGColor(red: 0.15, green: 0.05, blue: 0.3, alpha: 1), CGColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1)]
        case .peach: return [CGColor(red: 1.0, green: 0.7, blue: 0.65, alpha: 1), CGColor(red: 1.0, green: 0.85, blue: 0.7, alpha: 1)]
        default: return []
        }
    }

    var isGradient: Bool {
        switch self {
        case .cool, .nice, .morning, .bright, .love, .rain, .sky,
             .ocean, .forest, .sand, .midnight, .peach:
            return true
        default:
            return false
        }
    }

    var isSolid: Bool {
        switch self {
        case .white, .dark, .black: return true
        default: return false
        }
    }

    var solidCGColor: CGColor? {
        switch self {
        case .white: return CGColor.white
        case .dark: return CGColor(gray: 0.15, alpha: 1)
        case .black: return CGColor.black
        default: return nil
        }
    }
}
