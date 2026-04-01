import SwiftUI

struct BeautifyOptions: Equatable {
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 20
    var shadowOpacity: CGFloat = 0.4
    var shadowOffsetY: CGFloat = 10
    var padding: CGFloat = 60
    var inset: CGFloat = 0
    var backgroundStyle: BackgroundStyle = .frostedGlass

    // Custom color gradient (used when backgroundStyle == .customColor)
    var customColor1: Color = .blue
    var customColor2: Color = .purple

    // Custom image background (used when backgroundStyle == .customImage)
    var customImageURL: URL? = nil
}
