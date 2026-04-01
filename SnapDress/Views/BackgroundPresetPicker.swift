import SwiftUI

struct BackgroundPresetPicker: View {
    @Binding var selected: BackgroundStyle
    @Binding var customColor1: Color
    @Binding var customColor2: Color
    @Binding var customImageURL: URL?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BackgroundStyle.allCases) { style in
                    presetThumbnail(style)
                        .onTapGesture {
                            if style == .customImage {
                                pickImage()
                            } else {
                                selected = style
                            }
                        }
                }
            }

            // Custom color pickers (shown when customColor is selected)
            if selected == .customColor {
                HStack(spacing: 12) {
                    ColorPicker("From:", selection: $customColor1, supportsOpacity: false)
                    ColorPicker("To:", selection: $customColor2, supportsOpacity: false)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func presetThumbnail(_ style: BackgroundStyle) -> some View {
        VStack(spacing: 3) {
            ZStack {
                thumbnailBackground(style)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                thumbnailOverlay(style)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected == style ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(style.displayName)
                .font(.system(size: 9))
                .foregroundColor(selected == style ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func thumbnailBackground(_ style: BackgroundStyle) -> some View {
        let colors = style.thumbnailColors
        if colors.count >= 2 {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if let first = colors.first {
            first
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func thumbnailOverlay(_ style: BackgroundStyle) -> some View {
        switch style {
        case .frostedGlass:
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        case .transparent:
            checkerboardThumbnail
        case .customColor:
            Image(systemName: "paintpalette")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        case .customImage:
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        default:
            EmptyView()
        }
    }

    private var checkerboardThumbnail: some View {
        Canvas { context, size in
            let tile: CGFloat = 5
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    let color: Color = (row + col) % 2 == 0 ? .white : Color(white: 0.85)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    // MARK: - Image Picker

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            customImageURL = url
            selected = .customImage
        }
    }
}
