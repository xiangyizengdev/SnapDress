import ScreenCaptureKit
import AppKit

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case captureFailed
    case cropFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found for the selected screen."
        case .captureFailed: return "Failed to capture the screen."
        case .cropFailed: return "Failed to crop the captured image."
        case .permissionDenied: return "Screen recording permission is required. Please enable it in System Settings > Privacy & Security > Screen Recording."
        }
    }
}

class ScreenCaptureService {

    /// Captures the full contents of the given screen as a CGImage.
    /// Used to grab a frozen snapshot the user can select/annotate on,
    /// so the picked region doesn't change while the screen keeps updating.
    func captureFullScreen(screen: NSScreen) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }

        let displayID = screen.displayID
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(scDisplay.width) * scale)
        config.height = Int(CGFloat(scDisplay.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Crops a pre-captured full-screen snapshot using a selection rect in
    /// AppKit screen coordinates (origin bottom-left, measured in points).
    func cropSnapshot(_ snapshot: CGImage, selection: CGRect, screen: NSScreen) -> CGImage? {
        let scale = screen.backingScaleFactor
        let screenFrame = screen.frame
        let localX = selection.origin.x - screenFrame.origin.x
        let localY = screenFrame.height - (selection.maxY - screenFrame.origin.y)
        let pixelRect = CGRect(
            x: localX * scale,
            y: localY * scale,
            width: selection.width * scale,
            height: selection.height * scale
        )
        return snapshot.cropping(to: pixelRect)
    }

    /// Live-capture path: grabs the current screen and crops to the selection.
    /// Used when "freeze on capture" is disabled — the caller should make sure
    /// the overlay window is already hidden so it's not baked into the image.
    func captureRegion(rect: CGRect, screen: NSScreen) async throws -> CGImage {
        let snapshot = try await captureFullScreen(screen: screen)
        guard let cropped = cropSnapshot(snapshot, selection: rect, screen: screen) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
