import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
    @AppStorage("previewPosition") private var previewPosition: String = PreviewPosition.bottomRight.rawValue
    @AppStorage("freezeOnCapture") private var freezeOnCapture: Bool = true
    @AppStorage("retinaExport") private var retinaExport: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            heroSection

            VStack(spacing: 10) {
                shortcutCard
                freezeCard
                retinaCard
                previewPositionCard
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)

            Divider().opacity(0.5)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)

            Text("SnapDress")
                .font(.system(size: 22, weight: .semibold))

            Text("Polished screenshots, effortlessly.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 22)
    }

    // MARK: - Cards

    private var shortcutCard: some View {
        SettingsCard(
            icon: "command",
            iconColor: .blue,
            title: "Capture Shortcut",
            subtitle: "Global hotkey to start region capture."
        ) {
            KeyboardShortcuts.Recorder(for: .captureRegion)
        }
    }

    private var freezeCard: some View {
        SettingsCard(
            icon: "snowflake",
            iconColor: .cyan,
            title: "Freeze on Capture",
            subtitle: "Show a static snapshot while you select — so the picked region doesn't keep moving."
        ) {
            Toggle("", isOn: $freezeOnCapture)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var retinaCard: some View {
        SettingsCard(
            icon: "sparkles",
            iconColor: .pink,
            title: "Retina (HiDPI) Export",
            subtitle: "Tag exports as @2x so they stay crisp when pasted into Figma, Sketch or Keynote. Output file is the same pixel size."
        ) {
            Toggle("", isOn: $retinaExport)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var previewPositionCard: some View {
        SettingsCardContainer {
            HStack(alignment: .top, spacing: 12) {
                SettingsCardIcon(symbol: "rectangle.inset.filled", color: .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview Position")
                        .font(.system(size: 13, weight: .medium))
                    Text("Where the copied-to-clipboard toast appears after capture.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                PreviewPositionGrid(selection: $previewPosition)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("SnapDress \(Self.appVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            FooterLink(title: "Feedback", url: "https://github.com/xiangyizengdev/SnapDress/issues")
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            FooterLink(title: "Check for Updates", url: "https://github.com/xiangyizengdev/SnapDress/releases")
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(short)"
    }
}

// MARK: - Generic Card Container

private struct SettingsCardContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - Standard Card (icon + title + subtitle + control)

private struct SettingsCard<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        SettingsCardContainer {
            HStack(alignment: .center, spacing: 12) {
                SettingsCardIcon(symbol: icon, color: iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                control()
            }
        }
    }
}

// MARK: - Colored SF Symbol tile

private struct SettingsCardIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.gradient)
                .frame(width: 28, height: 28)
                .shadow(color: color.opacity(0.25), radius: 2, y: 1)

            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Preview Position Grid (2×2 visual picker)

private struct PreviewPositionGrid: View {
    @Binding var selection: String

    @State private var hovered: PreviewPosition?

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                cell(.topLeft)
                cell(.topRight)
            }
            HStack(spacing: 5) {
                cell(.bottomLeft)
                cell(.bottomRight)
            }
        }
    }

    private func cell(_ pos: PreviewPosition) -> some View {
        let isSelected = selection == pos.rawValue
        let isHovered = hovered == pos

        return Button {
            selection = pos.rawValue
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.05 : 0.03))

                // Toast indicator inside the "screen" box
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.35))
                    .frame(width: 14, height: 9)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: pos))
            }
            .frame(width: 44, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering ? pos : nil
        }
        .help(pos.label)
    }

    private func alignment(for pos: PreviewPosition) -> Alignment {
        switch pos {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

// MARK: - Footer link (NSWorkspace open, styled)

private struct FooterLink: View {
    let title: String
    let url: String

    @State private var hovered = false

    var body: some View {
        Button {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(hovered ? Color.accentColor : .secondary)
                .underline(hovered, color: .accentColor)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
