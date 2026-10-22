import AppKit
import os

/// Moves menu bar icons by addressing events to the icon's own window.
///
/// Nothing is dragged across the screen and nothing is revealed first. Snug sends a mouse-down
/// and a mouse-up addressed to the icon's own window, delivered to the app that owns the icon,
/// both at the edge of the icon it should land beside. macOS treats that as a ⌘-drag. Because the
/// events name the window directly, this works for off-screen icons and next to the notch, where
/// a real drag can't start.
///
/// Positions come from the window server, never Accessibility, and moves are checked against it.
enum ItemMover {
    private static let log = Logger(subsystem: "com.intentionaut.snug", category: "mover")
    private static let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    /// The raw "window ID" event field; moves are more reliable with it set.
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    enum Destination {
        case leftOf(CGWindowID), rightOf(CGWindowID)
        var target: CGWindowID { switch self { case .leftOf(let w), .rightOf(let w): w } }
    }

    /// Every menu bar item window, by ID, in global top-left coordinates. Needs no permission.
    static func windowFrames() -> [CGWindowID: CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var frames: [CGWindowID: CGRect] = [:]
        for info in list where (info[kCGWindowLayer as String] as? Int) == statusLayer {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as CFTypeRef?,
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { continue }
            frames[id] = rect
        }
        return frames
    }

    /// The window that holds an icon: the narrow menu bar window containing its centre.
    static func window(for item: MenuBarItem, in frames: [CGWindowID: CGRect]) -> CGWindowID? {
        frames.first { $0.value.width < 400 && $0.value.minX <= item.frame.midX && $0.value.maxX >= item.frame.midX }?.key
    }

    /// Moves `item` to `destination`, retrying up to three times. Returns true once the window
    /// server shows it in place.
    static func move(_ item: MenuBarItem, window: CGWindowID, to destination: Destination) -> Bool {
        for attempt in 1...3 {
            post(item: item, window: window, to: destination)
            if isInPlace(window, destination) {
                log.notice("moved \(item.name, privacy: .public) on attempt \(attempt, privacy: .public)")
                return true
            }
        }
        log.error("couldn't move \(item.name, privacy: .public)")
        return false
    }

    private static func isInPlace(_ window: CGWindowID, _ destination: Destination) -> Bool {
        let frames = windowFrames()
        guard let me = frames[window], let target = frames[destination.target] else { return false }
        switch destination {
        case .leftOf: return abs(me.maxX - target.minX) <= 1
        case .rightOf: return abs(me.minX - target.maxX) <= 1
        }
    }

    private static func post(item: MenuBarItem, window: CGWindowID, to destination: Destination) {
        let frames = windowFrames()
        guard let targetFrame = frames[destination.target],
              let screen = NSScreen.screens.first,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        let display = screen.frame
        // A target parked off screen uses its vertical middle; an on-screen one, its top edge.
        let offScreen = targetFrame.maxX <= display.minX
        let y = offScreen ? targetFrame.midY : targetFrame.minY
        let point: CGPoint
        switch destination {
        case .leftOf: point = CGPoint(x: targetFrame.minX, y: y)
        case .rightOf: point = CGPoint(x: targetFrame.maxX, y: y)
        }
        // For an off-screen target the press goes over the notch, which no icon occupies.
        var downPoint = point
        if offScreen, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            downPoint = CGPoint(x: (left.maxX + right.minX) / 2, y: y)
        }

        permitLocalEvents()
        let cursor = CGEvent(source: nil)?.location
        let onScreen = display.contains(CGPoint(x: point.x, y: max(point.y, 1)))
        if onScreen { CGWarpMouseCursorPosition(point) }
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let cursor { CGWarpMouseCursorPosition(cursor) }
            CGDisplayShowCursor(CGMainDisplayID())
        }
        Thread.sleep(forTimeInterval: 0.02)

        let before = frames[window]
        guard let down = event(.leftMouseDown, at: downPoint, window: window, source: source),
              let up = event(.leftMouseUp, at: point, window: destination.target, source: source) else { return }
        deliver(down, to: item.pid)
        waitForChange(of: window, from: before)
        let mid = windowFrames()[window]
        // Two mouse-ups: a single one occasionally leaves the icon stuck mid-move.
        deliver(up, to: item.pid)
        deliver(up, to: item.pid)
        waitForChange(of: window, from: mid)
    }

    /// A ⌘-mouse event stamped with the window it is for.
    private static func event(_ type: CGEventType, at point: CGPoint, window: CGWindowID, source: CGEventSource) -> CGEvent? {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return nil }
        e.flags = .maskCommand
        e.setIntegerValueField(.eventSourceUserData, value: Int64(Int(bitPattern: ObjectIdentifier(e))))
        e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        e.setIntegerValueField(windowIDField, value: Int64(window))
        return e
    }

    /// Sends the event through the session, then straight to the owning app, as Ice's
    /// event relay does.
    private static func deliver(_ event: CGEvent, to pid: pid_t) {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.005)
        event.postToPid(pid)
    }

    private static func waitForChange(of window: CGWindowID, from initial: CGRect?, timeout: TimeInterval = 0.25) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if windowFrames()[window] != initial { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Stops macOS suppressing the user's own mouse for a moment after synthetic events.
    private static func permitLocalEvents() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let all: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateRemoteMouseDrag)
        source.setLocalEventsFilterDuringSuppressionState(all, state: .eventSuppressionStateSuppressionInterval)
        source.localEventsSuppressionInterval = 0
    }
}
