import AppKit
import SwiftUI

struct WindowManager {

    static func createEditorWindow(captureState: CaptureState) -> EditorWindow {
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapDress"
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 900, height: 550)

        let previewView = PreviewWindow()
            .environmentObject(captureState)
        window.contentView = NSHostingView(rootView: previewView)

        return window
    }

    static func createFloatingPreviewWindow(image: NSImage, onTap: @escaping () -> Void) -> NSWindow {
        let view = FloatingPreviewView(image: image, onTap: onTap)
        let hostingView = NSHostingView(rootView: view)
        hostingView.setFrameSize(hostingView.fittingSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position based on user preference
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let winSize = hostingView.fittingSize
            let margin: CGFloat = 16

            let posRaw = UserDefaults.standard.string(forKey: "previewPosition") ?? PreviewPosition.bottomRight.rawValue
            let position = PreviewPosition(rawValue: posRaw) ?? .bottomRight

            let x: CGFloat
            let y: CGFloat
            switch position {
            case .bottomRight:
                x = screenRect.maxX - winSize.width - margin
                y = screenRect.minY + margin
            case .bottomLeft:
                x = screenRect.minX + margin
                y = screenRect.minY + margin
            case .topRight:
                x = screenRect.maxX - winSize.width - margin
                y = screenRect.maxY - winSize.height - margin
            case .topLeft:
                x = screenRect.minX + margin
                y = screenRect.maxY - winSize.height - margin
            }
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        return window
    }

    static func createOverlayWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}

// Editor window: intercepts Cmd+W at the lowest level via performKeyEquivalent.
// This works reliably regardless of LSUIElement, app activation state, or SwiftUI event handling.
class EditorWindow: NSWindow {
    var onClose: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command && event.charactersIgnoringModifiers == "w" {
            onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// Borderless windows return NO from canBecomeKey by default.
// Subclass to allow the overlay to receive keyboard/mouse events.
class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
