import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject var captureState: CaptureState

    var body: some View {
        Button("Capture Region") {
            captureState.startCapture()
        }
        .keyboardShortcut("7", modifiers: [.command, .shift])

        Divider()

        Button("Preferences...") {
            AppDelegate.shared?.showPreferences()
        }

        Divider()

        Button("Quit SnapDress") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
