import SwiftUI

struct BeautifyControlsView: View {
    @Binding var options: BeautifyOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Padding
            controlSection("Padding") {
                CompactSlider(value: $options.padding, range: 0...120, step: 5)
            }

            // Inset
            controlSection("Inset") {
                CompactSlider(value: $options.inset, range: 0...60, step: 2)
            }

            // Border Radius & Shadow (side by side)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Border Radius")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CompactSlider(value: $options.cornerRadius, range: 0...30, step: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Shadow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CompactSlider(value: $options.shadowRadius, range: 0...50, step: 1)
                }
            }

            Divider()

            // Background presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Background")
                    .font(.caption)
                    .foregroundColor(.secondary)
                BackgroundPresetPicker(
                    selected: $options.backgroundStyle,
                    customColor1: $options.customColor1,
                    customColor2: $options.customColor2,
                    customImageURL: $options.customImageURL
                )
            }
        }
    }

    @ViewBuilder
    private func controlSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
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
                // Track background
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)

                // Filled track
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(thumbX, 0), height: 6)

                // Thumb
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
