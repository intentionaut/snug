import AppKit
import os

/// Three status items, left to right: an always-hidden divider (‖), the divider (│) and the
/// beard. Collapsing stretches a divider so everything left of it is pushed off screen.
/// Clicking the beard opens the dropdown; hidden icons are revealed only to use or move one.
final class Divider {
    static let rehideDelayKey = "rehideDelay"
    static let defaultRehideDelay: TimeInterval = 5
    /// Set in Settings; read each time so a change applies straight away.
    static var rehideDelay: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: rehideDelayKey)
        return saved > 0 ? saved : defaultRehideDelay
    }
    private static let collapsedLength: CGFloat = 10_000

    private let log = Logger(subsystem: "com.intentionaut.snug", category: "divider")
    private let toggleItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private let alwaysItem: NSStatusItem
    private var rehideTimer: Timer?
    private var clickMonitor: Any?
    private let menu = NSMenu()
    private(set) var isCollapsed = false
    private(set) var isArranging = false
    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    /// Opens the dropdown if it isn't already open: hovering on the mousehole, or scrolling in the menu bar.
    var onReveal: (() -> Void)?
    static let openOnHoverKey = "openOnHover"
    static let openOnScrollKey = "openOnScroll"
    private var hover: HoverTarget?
    private var scrollMonitors: [Any] = []

    init() {
        // Items created later sit further left, so the toggle goes first.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "snug.toggle"
        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem.autosaveName = "snug.divider"
        alwaysItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        alwaysItem.autosaveName = "snug.always"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
        }
        dividerItem.button?.title = "│"
        dividerItem.button?.appearsDisabled = true
        alwaysItem.button?.title = "‖"
        alwaysItem.button?.appearsDisabled = true

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        UserDefaults.standard.register(defaults: [Self.openOnHoverKey: true, Self.openOnScrollKey: true])
        if let button = toggleItem.button {
            let target = HoverTarget { [weak self] in
                guard UserDefaults.standard.bool(forKey: Self.openOnHoverKey) else { return }
                self?.onReveal?()
            }
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: target, userInfo: nil))
            hover = target
        }
        // Scrolling anywhere on the menu bar opens it. A global monitor sees other apps' bar;
        // a local one sees scrolls over Snug's own icons.
        let scrolled: (NSEvent) -> Void = { [weak self] event in
            guard UserDefaults.standard.bool(forKey: Self.openOnScrollKey), abs(event.scrollingDeltaY) > 1 else { return }
            let point = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }), point.y >= screen.visibleFrame.maxY else { return }
            self?.onReveal?()
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: scrolled) { scrollMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { scrolled($0); return $0 }) { scrollMonitors.append(local) }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clickedElsewhere()
        }

        // Start shown; the dropdown collapses once it has pictures of every icon (see Dropdown.init).
    }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    /// Screen frames of the two dividers, for sorting and moving other apps' icons.
    var dividerFrame: CGRect? { dividerItem.button?.window?.frame }
    var alwaysFrame: CGRect? { alwaysItem.button?.window?.frame }
    /// Window-server IDs of the two dividers, which ItemMover moves icons beside. On macOS 26
    /// a status item's real window lives in Control Centre, so our local window's number is not
    /// it; find the window server's window with the same position and width instead.
    var dividerWindow: CGWindowID? { Self.serverWindow(matching: dividerFrame) }
    var alwaysWindow: CGWindowID? { Self.serverWindow(matching: alwaysFrame) }

    private static func serverWindow(matching frame: CGRect?) -> CGWindowID? {
        guard let frame else { return nil }
        return ItemMover.windowFrames().first {
            abs($0.value.minX - frame.minX) < 1 && abs($0.value.width - frame.width) < 1
        }?.key
    }

    /// A new status item lands wherever macOS puts it, which can be right of the divider.
    var alwaysIsMisplaced: Bool {
        guard let a = alwaysFrame, let d = dividerFrame else { return false }
        return a.minX > d.minX
    }

    @objc private func toggleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleItem.menu = menu
            toggleItem.button?.performClick(nil)
            toggleItem.menu = nil
            return
        }
        onOpen?()
    }

    @objc private func settingsClicked() { onSettings?() }

    var toggleFrame: CGRect? { toggleItem.button?.window?.frame }

    func collapse() {
        rehideTimer?.invalidate()
        guard !isArranging else { return }
        // If a divider was dragged right of the toggle, stretching it would hide the toggle too.
        guard let dividerX = dividerFrame?.minX,
              let toggleX = toggleItem.button?.window?.frame.minX,
              dividerX < toggleX else {
            log.error("divider is not left of the toggle; refusing to collapse")
            return
        }
        dividerItem.length = Self.collapsedLength
        stretchAlways()
        isCollapsed = true
        updateIcon()
    }

    /// Shows hidden icons (and always-hidden ones if asked) so one can be clicked, then re-hides
    /// on the usual timer or click-away.
    func reveal(includeAlways: Bool, rehideAfter delay: TimeInterval = Divider.rehideDelay) {
        dividerItem.length = NSStatusItem.variableLength
        if includeAlways { alwaysItem.length = NSStatusItem.variableLength } else { stretchAlways() }
        isCollapsed = false
        updateIcon()
        scheduleRehide(after: delay)
    }

    /// Shows everything, both sections included, and holds it open until `endArranging`.
    func beginArranging() {
        isArranging = true
        rehideTimer?.invalidate()
        dividerItem.length = NSStatusItem.variableLength
        alwaysItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateIcon()
    }

    func endArranging() {
        isArranging = false
        collapse()
    }

    private func stretchAlways() {
        guard let alwaysX = alwaysFrame?.minX, let dividerX = dividerFrame?.minX, alwaysX < dividerX else {
            log.error("always-hidden divider (x \(self.alwaysFrame?.minX ?? -1, privacy: .public)) is not left of the divider (x \(self.dividerFrame?.minX ?? -1, privacy: .public)); leaving it narrow")
            alwaysItem.length = NSStatusItem.variableLength
            return
        }
        alwaysItem.length = Self.collapsedLength
    }

    private func scheduleRehide(after delay: TimeInterval = Divider.rehideDelay) {
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A ⌘-drag to rearrange icons is invisible to our click monitor, so check the live
            // modifier and button state. Both class properties need no permission.
            if NSEvent.modifierFlags.contains(.command) || NSEvent.pressedMouseButtons != 0 || Self.menuIsOpen() {
                // Check again soon, so the icon hides as soon as its menu closes.
                self.scheduleRehide(after: 0.5)
            } else {
                self.collapse()
            }
        }
    }

    /// True while any app has a menu open, so a revealed icon isn't pulled away from under its menu.
    /// Window layers and owners are readable without Screen Recording; only titles need it.
    static func menuIsOpen() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }

    /// Global monitors only see clicks in other apps. A click in the menu bar
    /// (opening a revealed item) restarts the timer; a click anywhere else re-hides.
    private func clickedElsewhere() {
        guard !isCollapsed, !isArranging else { return }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        let menuBarBottom = screen.map { $0.visibleFrame.maxY } ?? .greatestFiniteMagnitude
        if point.y >= menuBarBottom {
            scheduleRehide()
        } else {
            collapse()
        }
    }

    private func updateIcon() {
        toggleItem.button?.image = Glyph.image(collapsed: isCollapsed)
    }
}

/// Receives the mousehole's hover events; opens after a short rest so passing over doesn't trigger it.
private final class HoverTarget: NSResponder {
    private let action: () -> Void
    private var pending: DispatchWorkItem?

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) {
        let work = DispatchWorkItem { [action] in action() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        pending?.cancel()
    }
}
