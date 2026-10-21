import AppKit
import ScreenCaptureKit
import os

/// Pictures of the real menu bar icons, for the dropdown. Each icon is its own small window;
/// with Screen Recording, ScreenCaptureKit can capture just those windows, even off screen.
/// Images stay in memory and are never written anywhere.
enum IconCapture {
    private static let log = Logger(subsystem: "local.elle.barkeep", category: "capture")
    private static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    static let declinedKey = "screenRecordingDeclined"

    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's prompt. macOS only applies the grant after Barkeep is reopened.
    static func request() { _ = CGRequestScreenCaptureAccess() }

    /// Captures every item it can match to a menu bar window, keyed by item id.
    static func capture(_ items: [MenuBarItem]) async -> [String: NSImage] {
        guard isAllowed, !items.isEmpty else { return [:] }
        let started = Date()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.error("couldn't list windows: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        let windows = content.windows.filter { $0.windowLayer == statusLayer }
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        var images: [String: NSImage] = [:]
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for item in items {
                // Both use global coordinates with a top-left origin. The window carries a few points of
                // padding around the icon, so match the window that contains the icon's centre.
                // Skip the dividers' own 5,016-wide windows.
                guard let window = windows.first(where: { $0.frame.width < 400 && $0.frame.minX <= item.frame.midX && $0.frame.maxX >= item.frame.midX }) else { continue }
                group.addTask {
                    let config = SCStreamConfiguration()
                    config.width = Int(window.frame.width * scale)
                    config.height = Int(window.frame.height * scale)
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                        return (item.id, nil)
                    }
                    return (item.id, NSImage(cgImage: cg, size: window.frame.size))
                }
            }
            for await (id, image) in group {
                if let image { images[id] = image }
            }
        }
        let missed = items.filter { images[$0.id] == nil }.map(\.name).joined(separator: ", ")
        log.notice("missed: \(missed, privacy: .public)")
        log.notice("captured \(images.count, privacy: .public) of \(items.count, privacy: .public) icons in \(Date().timeIntervalSince(started), privacy: .public)s")
        return images
    }

    /// Reopens Barkeep so a new Screen Recording grant takes effect.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
