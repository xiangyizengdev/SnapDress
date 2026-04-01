import SwiftUI
import ScreenCaptureKit

@main
struct SnapDressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var captureState = CaptureState()

    var body: some Scene {
        MenuBarExtra("SnapDress", systemImage: "camera.viewfinder") {
            MenuBarView()
                .environmentObject(captureState)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var preferencesWindow: NSWindow?
    private var preferencesWindowDelegate: PreferencesWindowDelegateHelper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let bundleID = Bundle.main.bundleIdentifier ?? "com.snapdress.app"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            if let existing = running.first(where: { $0 != .current }) {
                existing.activate()
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }

        preAuthorizeScreenCapture()

        // Show preferences on first launch so the user sees something
        DispatchQueue.main.async { [weak self] in
            self?.showPreferences()
        }
    }

    /// Called when user clicks the app icon while it's already running (e.g. from Dock, Spotlight)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showPreferences()
        }
        return true
    }

    // MARK: - Pre-authorize ScreenCaptureKit (triggers permission dialog early)

    private func preAuthorizeScreenCapture() {
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    // MARK: - Preferences Window

    func showPreferences() {
        if preferencesWindow == nil {
            let hostingView = NSHostingView(rootView: PreferencesView())
            hostingView.setFrameSize(hostingView.fittingSize)

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "SnapDress Preferences"
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.center()

            let delegate = PreferencesWindowDelegateHelper()
            delegate.onClose = { [weak self] in
                self?.onPreferencesWindowClosed()
            }
            window.delegate = delegate
            self.preferencesWindowDelegate = delegate

            preferencesWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func onPreferencesWindowClosed() {
        // Only switch back to accessory if no editor window is visible
        let hasVisibleEditorWindow = NSApp.windows.contains { $0 is EditorWindow && $0.isVisible }
        if !hasVisibleEditorWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private class PreferencesWindowDelegateHelper: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
