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

    func captureRegion(rect: CGRect, screen: NSScreen) async throws -> CGImage {
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

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // Convert rect from AppKit screen coordinates (origin bottom-left)
        // to CGImage pixel coordinates (origin top-left)
        let screenFrame = screen.frame
        let localX = rect.origin.x - screenFrame.origin.x
        let localY = screenFrame.height - (rect.maxY - screenFrame.origin.y)
        let pixelRect = CGRect(
            x: localX * scale,
            y: localY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let cropped = fullImage.cropping(to: pixelRect) else {
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
