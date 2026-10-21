import AppKit
import ApplicationServices
import os

/// Other apps' menu bar icons, read and moved through Accessibility.
/// macOS 26 reports every menu bar window as Control Center's, so window lists can't say who owns
/// an icon; each app's AXExtrasMenuBar can.
enum Section: String, CaseIterable, Identifiable {
    case showing = "Showing", hidden = "Hidden", always = "Always hidden"
    var id: String { rawValue }
}

struct MenuBarItem: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let name: String
    let icon: NSImage
    let frame: CGRect   // global, top-left origin, as Accessibility and CGEvent use

    static func == (a: MenuBarItem, b: MenuBarItem) -> Bool { a.id == b.id && a.frame == b.frame }
}

enum MenuBarItems {
    private static let log = Logger(subsystem: "local.elle.barkeep", category: "items")

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Every app's menu bar icons, left to right. Slow apps are skipped after a short timeout.
    static func read() -> [MenuBarItem] {
        let me = ProcessInfo.processInfo.processIdentifier
        var items: [MenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != me {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            guard let bar: AXUIElement = attribute(appElement, "AXExtrasMenuBar"),
                  let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { continue }
            let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
            for (index, child) in children.enumerated() {
                guard let frame = frame(of: child) else { continue }
                let label: String? = attribute(child, kAXDescriptionAttribute) ?? attribute(child, kAXTitleAttribute)
                let name = children.count > 1 ? "\(appName): \(label?.isEmpty == false ? label! : "item \(index + 1)")" : appName
                items.append(MenuBarItem(id: "\(app.bundleIdentifier ?? appName)#\(index)",
                                         pid: app.processIdentifier, name: name,
                                         icon: app.icon ?? NSImage(), frame: frame))
            }
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Which section an icon is in, from where it sits relative to the two dividers.
    static func section(of item: MenuBarItem, divider: CGRect, always: CGRect) -> Section {
        if item.frame.midX > divider.midX { return .showing }
        if item.frame.midX > always.midX { return .hidden }
        return .always
    }

    /// Moves an icon with a synthetic ⌘-drag, the same gesture a person would make.
    /// Both the icon and the target divider must be on screen.
    static func drag(_ item: MenuBarItem, toX targetX: CGFloat) {
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let end = CGPoint(x: targetX, y: item.frame.midY)
        let restore = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, start)
        Thread.sleep(forTimeInterval: 0.05)
        post(.leftMouseDown, start)
        Thread.sleep(forTimeInterval: 0.08)
        let steps = 12
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y))
            Thread.sleep(forTimeInterval: 0.02)
        }
        post(.leftMouseUp, end)
        Thread.sleep(forTimeInterval: 0.25)
        if let restore { CGWarpMouseCursorPosition(restore) }
        log.notice("dragged \(item.name, privacy: .public) from \(start.x, privacy: .public) to \(end.x, privacy: .public)")
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}
