import SwiftUI

/// User-tunable beautify parameters persisted across launches.
///
/// `Color` and `URL` are hoisted into Codable-friendly storage so that the
/// whole struct can round-trip through UserDefaults/JSON. The SwiftUI-facing
/// API (`customColor1`, `customColor2`, `customImageURL`) is preserved via
/// computed properties so existing call sites (sliders, ColorPickers,
/// ImageProcessor) don't need to change.
struct BeautifyOptions: Codable, Equatable {
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 20
    var shadowOpacity: CGFloat = 0.4
    var shadowOffsetY: CGFloat = 10
    var padding: CGFloat = 60
    var inset: CGFloat = 0
    var backgroundStyle: BackgroundStyle = .frostedGlass

    // Encoded storage
    private var customColor1Storage: CodableColor = CodableColor(.blue)
    private var customColor2Storage: CodableColor = CodableColor(.purple)
    var customImageURL: URL? = nil

    // MARK: - SwiftUI-facing bridges

    var customColor1: Color {
        get { customColor1Storage.swiftUIColor }
        set { customColor1Storage = CodableColor(newValue) }
    }
    var customColor2: Color {
        get { customColor2Storage.swiftUIColor }
        set { customColor2Storage = CodableColor(newValue) }
    }
}

// MARK: - CodableColor

/// Minimal sRGB container so `SwiftUI.Color` can be persisted via Codable.
/// Uses device RGB components extracted through NSColor; opaque colors round
/// trip exactly, translucent colors within float precision.
struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        self.red = Double(ns.redComponent)
        self.green = Double(ns.greenComponent)
        self.blue = Double(ns.blueComponent)
        self.alpha = Double(ns.alphaComponent)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
