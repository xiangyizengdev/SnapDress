import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var captureState: CaptureState
    @ObservedObject private var recents = RecentScreenshotsStore.shared

    @State private var currentShortcutText: String? = nil
    @State private var copyToastID: UUID? = nil

    private let shortcutChange = NotificationCenter.default
        .publisher(for: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            captureButton
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            if !recents.items.isEmpty {
                Divider()
                recentSection
            }

            Divider()
            footer
        }
        .frame(width: 296)
        .onAppear { refreshShortcut() }
        .onReceive(shortcutChange) { _ in refreshShortcut() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("SnapDress")
                    .font(.system(size: 13, weight: .semibold))
                Text("Beautify your screenshots")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Capture button

    private var captureButton: some View {
        Button {
            captureState.startCapture()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                Text("Capture Region")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let text = currentShortcutText {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                        )
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if !recents.items.isEmpty {
                    Button("Clear") {
                        recents.clearAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recents.items) { item in
                        RecentThumbnail(
                            item: item,
                            isToasting: copyToastID == item.id
                        ) { handleRecentClick(item) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 1) {
            MenuRow(icon: "gearshape", title: "Preferences…") {
                AppDelegate.shared?.showPreferences()
            }
            MenuRow(icon: "power", title: "Quit SnapDress", trailing: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Actions

    private func handleRecentClick(_ item: RecentScreenshotsStore.Item) {
        guard let image = recents.image(for: item) else { return }
        ExportService.copyToClipboard(image: image)

        let id = item.id
        copyToastID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if copyToastID == id { copyToastID = nil }
        }
    }

    private func refreshShortcut() {
        let name = KeyboardShortcuts.Name.captureRegion
        let shortcut = KeyboardShortcuts.getShortcut(for: name) ?? name.defaultShortcut
        currentShortcutText = shortcut?.description
    }
}

// MARK: - Recent Thumbnail

private struct RecentThumbnail: View {
    let item: RecentScreenshotsStore.Item
    let isToasting: Bool
    let action: () -> Void

    @ObservedObject private var recents = RecentScreenshotsStore.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if let img = recents.image(for: item) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        )
                }

                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    .frame(width: 56, height: 56)

                if isToasting {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.black.opacity(0.55))
                        .frame(width: 56, height: 56)
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Copied")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        )
                        .transition(.opacity)
                }
            }
            .scaleEffect(isHovering ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 4, y: 2)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.18), value: isToasting)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Click to copy · Right-click for more")
        .contextMenu {
            Button("Copy") { action() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Delete", role: .destructive) {
                recents.remove(item)
            }
        }
    }
}

// MARK: - Menu Row

private struct MenuRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
