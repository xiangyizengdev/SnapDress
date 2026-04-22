import SwiftUI

struct BeautifyControlsView: View {
    @Binding var options: BeautifyOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            // MARK: Layout

            section(icon: "rectangle.expand.vertical", title: "Layout", tint: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    ParamRow(title: "Padding", valueText: integerValue(options.padding)) {
                        CompactSlider(value: $options.padding, range: 0...120, step: 5)
                    }
                    ParamRow(title: "Inset", valueText: integerValue(options.inset)) {
                        CompactSlider(value: $options.inset, range: 0...60, step: 2)
                    }
                    ParamRow(title: "Corner Radius", valueText: integerValue(options.cornerRadius)) {
                        CompactSlider(value: $options.cornerRadius, range: 0...30, step: 1)
                    }
                }
            }

            // MARK: Shadow

            section(icon: "shadow", title: "Shadow", tint: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    ParamRow(title: "Radius", valueText: integerValue(options.shadowRadius)) {
                        CompactSlider(value: $options.shadowRadius, range: 0...80, step: 1)
                    }
                    ParamRow(title: "Opacity", valueText: percentValue(options.shadowOpacity)) {
                        CompactSlider(value: $options.shadowOpacity, range: 0...1, step: 0.05)
                    }
                    ParamRow(title: "Offset Y", valueText: integerValue(options.shadowOffsetY)) {
                        CompactSlider(value: $options.shadowOffsetY, range: 0...40, step: 1)
                    }
                }
            }

            // MARK: Background

            section(icon: "paintbrush.fill", title: "Background", tint: .pink) {
                BackgroundPresetPicker(
                    selected: $options.backgroundStyle,
                    customColor1: $options.customColor1,
                    customColor2: $options.customColor2,
                    customImageURL: $options.customImageURL
                )
            }

            Divider().padding(.vertical, 4)

            resetButton
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    let preserved = (
                        options.customColor1,
                        options.customColor2,
                        options.customImageURL
                    )
                    options = BeautifyOptions()
                    options.customColor1 = preserved.0
                    options.customColor2 = preserved.1
                    options.customImageURL = preserved.2
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text("Reset to defaults")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .help("Reset all beautify options to default values")
            Spacer()
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section<Content: View>(
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tint.opacity(0.15))
                    )
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content()
        }
    }

    // MARK: - Formatters

    private func integerValue(_ v: CGFloat) -> String {
        "\(Int(v.rounded()))"
    }

    private func percentValue(_ v: CGFloat) -> String {
        "\(Int((v * 100).rounded()))%"
    }
}

// MARK: - Param Row

private struct ParamRow<Slider: View>: View {
    let title: String
    let valueText: String
    @ViewBuilder var slider: () -> Slider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            slider()
        }
    }
}

// MARK: - Compact Slider (Xnapper-style: thin colored track)

struct CompactSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbX = fraction * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(thumbX, 0), height: 6)

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: max(thumbX - 8, -4))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = max(0, min(1, drag.location.x / trackWidth))
                        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                        value = (raw / step).rounded() * step
                    }
            )
        }
        .frame(height: 16)
    }
}
