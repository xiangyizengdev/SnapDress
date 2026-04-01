import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
    @AppStorage("previewPosition") private var previewPosition: String = PreviewPosition.bottomRight.rawValue

    var body: some View {
        Form {
            Section("Capture Shortcut") {
                KeyboardShortcuts.Recorder("Capture Region:", name: .captureRegion)
            }
            Section("Preview Position") {
                Picker("Floating preview:", selection: $previewPosition) {
                    ForEach(PreviewPosition.allCases) { pos in
                        Text(pos.label).tag(pos.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
