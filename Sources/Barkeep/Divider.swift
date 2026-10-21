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

    private let log = Logger(subsystem: "local.elle.barkeep", category: "divider")
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

    init() {
        // Items created later sit further left, so the toggle goes first.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "barkeep.toggle"
        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem.autosaveName = "barkeep.divider"
        alwaysItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        alwaysItem.autosaveName = "barkeep.always"

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
        menu.addItem(withTitle: "Quit Barkeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

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
    private static func menuIsOpen() -> Bool {
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
