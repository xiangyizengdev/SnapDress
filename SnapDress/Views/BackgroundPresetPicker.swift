import SwiftUI

struct BackgroundPresetPicker: View {
    @Binding var selected: BackgroundStyle
    @Binding var customColor1: Color
    @Binding var customColor2: Color
    @Binding var customImageURL: URL?

    @State private var category: Category = .style
    @State private var hoveredStyle: BackgroundStyle? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            categoryPicker

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(category.styles) { style in
                    presetThumbnail(style)
                        .onTapGesture {
                            if style == .customImage {
                                pickImage()
                            } else {
                                selected = style
                            }
                        }
                        .onHover { hovering in
                            hoveredStyle = hovering ? style : nil
                        }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: category)

            if selected == .customColor && category == .custom {
                customColorEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { category = inferredCategory }
        .onChange(of: selected) { _, _ in
            if !category.styles.contains(selected) {
                withAnimation(.easeOut(duration: 0.18)) {
                    category = inferredCategory
                }
            }
        }
    }

    // MARK: - Category Segmented Picker

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(Category.allCases) { cat in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { category = cat }
                } label: {
                    Text(cat.label)
                        .font(.system(size: 11, weight: category == cat ? .semibold : .regular))
                        .foregroundStyle(category == cat ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(category == cat ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var customColorEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ColorPicker("From", selection: $customColor1, supportsOpacity: false)
                    .labelsHidden()
                Text("From").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                ColorPicker("To", selection: $customColor2, supportsOpacity: false)
                    .labelsHidden()
                Text("To").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .padding(.top, 4)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func presetThumbnail(_ style: BackgroundStyle) -> some View {
        let isSelected = selected == style
        let isHovered = hoveredStyle == style

        VStack(spacing: 4) {
            ZStack {
                thumbnailBackground(style)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                thumbnailOverlay(style)

                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(3)
                }
            }
            .scaleEffect(isHovered && !isSelected ? 1.04 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.15 : 0), radius: 4, y: 2)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            Text(style.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        case .transparent:
            checkerboardThumbnail
        case .customColor:
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        case .customImage:
            Image(systemName: "photo.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
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

    // MARK: - Helpers

    private var inferredCategory: Category {
        Category.allCases.first { $0.styles.contains(selected) } ?? .style
    }

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

// MARK: - Category

private enum Category: String, CaseIterable, Identifiable {
    case style, solid, gradient, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .style: return "Style"
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .custom: return "Custom"
        }
    }

    var styles: [BackgroundStyle] {
        switch self {
        case .style: return [.frostedGlass, .transparent]
        case .solid: return [.white, .dark, .black]
        case .gradient:
            return [
                .cool, .nice, .morning, .bright, .love, .rain, .sky,
                .ocean, .forest, .sand, .midnight, .peach,
            ]
        case .custom: return [.customColor, .customImage]
        }
    }
}
