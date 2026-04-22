import SwiftUI

struct PreviewWindow: View {
    @EnvironmentObject var captureState: CaptureState
    @State private var showCopyFeedback = false
    @State private var showSavedFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            topToolbar

            Divider()

            HStack(spacing: 0) {
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                ScrollView {
                    BeautifyControlsView(options: $captureState.beautifyOptions)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                }
                .frame(width: 270)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 940, minHeight: 580)
        .onChange(of: captureState.beautifyOptions) {
            captureState.updateProcessedImage()
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 12) {
            imageInfoPanel

            Spacer()

            HStack(spacing: 8) {
                ToolbarActionButton(
                    systemImage: "doc.on.doc",
                    label: "Copy",
                    shortcut: "⌘C"
                ) {
                    copyToClipboard()
                }
                .keyboardShortcut("c", modifiers: .command)

                ToolbarActionButton(
                    systemImage: "square.and.arrow.down",
                    label: "Save",
                    shortcut: "⌘S",
                    isPrimary: true
                ) {
                    saveToFile()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var imageInfoPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            if let image = captureState.processedImage {
                let size = pixelSize(of: image)
                Text("\(Int(size.width)) × \(Int(size.height))")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(captureState.beautifyOptions.backgroundStyle.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Processing…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewPane: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            if let image = captureState.processedImage {
                GeometryReader { geo in
                    let imageSize = image.size
                    let fitted = fitSize(imageSize, into: geo.size, padding: 32)
                    ZStack {
                        if captureState.beautifyOptions.backgroundStyle == .transparent {
                            CheckerboardView()
                                .frame(width: fitted.width, height: fitted.height)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fitted.width, height: fitted.height)
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .clipped()
            } else {
                ProgressView("Processing…")
            }

            if showCopyFeedback {
                FeedbackBadge(icon: "checkmark.circle.fill", text: "Copied")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            if showSavedFeedback {
                FeedbackBadge(icon: "square.and.arrow.down.fill", text: "Saved")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("Double-click to copy & close")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                        .padding(12)
                }
            }
            .allowsHitTesting(false)
        }
        .onTapGesture(count: 2) {
            copyAndClose()
        }
    }

    // MARK: - Helpers

    private func fitSize(_ imageSize: NSSize, into containerSize: CGSize, padding: CGFloat) -> CGSize {
        let availableW = max(containerSize.width - padding * 2, 1)
        let availableH = max(containerSize.height - padding * 2, 1)
        let scale = min(availableW / imageSize.width, availableH / imageSize.height, 1.0)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    // MARK: - Actions

    private func copyToClipboard() {
        guard let image = captureState.processedImage else { return }
        ExportService.copyToClipboard(image: image)
        flashCopy()
    }

    private func copyAndClose() {
        guard let image = captureState.processedImage else { return }
        ExportService.copyToClipboard(image: image)
        captureState.closeEditor()
    }

    private func saveToFile() {
        guard let image = captureState.processedImage else { return }
        ExportService.saveToFile(image: image)
        flashSaved()
    }

    private func flashCopy() {
        withAnimation(.easeInOut(duration: 0.2)) { showCopyFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.3)) { showCopyFeedback = false }
        }
    }

    private func flashSaved() {
        withAnimation(.easeInOut(duration: 0.2)) { showSavedFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.3)) { showSavedFeedback = false }
        }
    }
}

// MARK: - Toolbar Action Button

private struct ToolbarActionButton: View {
    let systemImage: String
    let label: String
    let shortcut: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor)
            )
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("\(label)  \(shortcut)")
    }

    private var backgroundColor: Color {
        if isPrimary {
            return isHovering ? Color.accentColor.opacity(0.85) : Color.accentColor
        }
        return isHovering ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)
    }
}

// MARK: - Feedback Badge

private struct FeedbackBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.7))
        )
    }
}

// MARK: - Checkerboard (preview-only, NOT rendered into exported image)

struct CheckerboardView: View {
    let tileSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / tileSize))
            let rows = Int(ceil(size.height / tileSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    let color: Color = (row + col) % 2 == 0 ? .white : Color(white: 0.85)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
