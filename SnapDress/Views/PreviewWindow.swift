import SwiftUI

struct PreviewWindow: View {
    @EnvironmentObject var captureState: CaptureState
    @State private var showCopyFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            // Main content: preview + sidebar
            HStack(spacing: 0) {
                // Left: Preview area (image scales to fit, no scrolling)
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Right: Control sidebar
                ScrollView {
                    BeautifyControlsView(options: $captureState.beautifyOptions)
                        .padding(16)
                }
                .frame(width: 240)
            }

            Divider()

            // Bottom toolbar
            bottomToolbar
        }
        .frame(minWidth: 900, minHeight: 550)
        .onChange(of: captureState.beautifyOptions) {
            captureState.updateProcessedImage()
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
                        // Show checkerboard behind image when transparent background is selected
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
                ProgressView("Processing...")
            }

            // Copy feedback overlay
            if showCopyFeedback {
                Text("Copied!")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.7))
                    .cornerRadius(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onTapGesture(count: 2) {
            copyAndClose()
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Text("Copy")
                    Text("⌘C")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button(action: saveToFile) {
                HStack(spacing: 4) {
                    Text("Save")
                    Text("⌘S")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Save As...") {
                saveAsFile()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Spacer()

            Text("Double-click background = Copy and Close")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    /// Compute the largest size that fits `imageSize` inside `containerSize` with padding.
    private func fitSize(_ imageSize: NSSize, into containerSize: CGSize, padding: CGFloat) -> CGSize {
        let availableW = max(containerSize.width - padding * 2, 1)
        let availableH = max(containerSize.height - padding * 2, 1)
        let scale = min(availableW / imageSize.width, availableH / imageSize.height, 1.0)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    // MARK: - Actions

    private func copyToClipboard() {
        guard let image = captureState.processedImage else { return }
        ExportService.copyToClipboard(image: image)
        withAnimation(.easeInOut(duration: 0.2)) { showCopyFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.3)) { showCopyFeedback = false }
        }
    }

    private func copyAndClose() {
        guard let image = captureState.processedImage else { return }
        ExportService.copyToClipboard(image: image)
        captureState.closeEditor()
    }

    private func saveToFile() {
        guard let image = captureState.processedImage else { return }
        ExportService.saveToFile(image: image)
    }

    private func saveAsFile() {
        guard let image = captureState.processedImage else { return }
        ExportService.saveToFile(image: image)
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
