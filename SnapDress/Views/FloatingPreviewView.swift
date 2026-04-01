import SwiftUI

struct FloatingPreviewView: View {
    let image: NSImage
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 180, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Copied! Click to edit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .onTapGesture { onTap() }
    }
}
