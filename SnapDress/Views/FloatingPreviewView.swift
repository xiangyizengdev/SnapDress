import SwiftUI

struct FloatingPreviewView: View {
    let image: NSImage
    var totalDuration: Double = 3.5
    var onTap: () -> Void
    var onDismiss: () -> Void

    @State private var remaining: Double = 3.5
    @State private var isHovering = false
    @State private var isClosing = false
    @State private var didStart = false

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            statusBar
            progressBar
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.32), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { handleTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
            // While hovering we treat the popup as "pinned": fully restore the timer
            // so when the user moves away they get a fresh window to act on it,
            // not just whatever scraps were left.
            if hovering {
                remaining = totalDuration
            }
        }
        .onAppear {
            remaining = totalDuration
            didStart = true
        }
        .onReceive(tick) { _ in
            guard didStart, !isHovering, !isClosing else { return }
            remaining = max(0, remaining - 0.05)
            if remaining <= 0 {
                isClosing = true
                onDismiss()
            }
        }
    }

    // MARK: - Preview area

    private var previewArea: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 130)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)

            if isHovering {
                Button {
                    isClosing = true
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white, Color.black.opacity(0.65))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .padding(.top, 6)
                .padding(.trailing, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11, weight: .semibold))

            Text("Copied")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 4) {
                Text("Click to edit")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                Rectangle()
                    .fill(progressTint)
                    .frame(width: geo.size.width * progressFraction)
            }
        }
        .frame(height: 2)
        .animation(.linear(duration: 0.06), value: progressFraction)
    }

    // MARK: - Helpers

    private var progressFraction: Double {
        max(0, min(1, remaining / totalDuration))
    }

    private var progressTint: Color {
        isHovering ? Color.accentColor : Color.accentColor.opacity(0.7)
    }

    private func handleTap() {
        guard !isClosing else { return }
        isClosing = true
        onTap()
    }
}
