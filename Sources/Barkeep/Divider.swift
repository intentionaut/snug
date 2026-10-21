import AppKit
import os

/// Three status items, left to right: an always-hidden divider (‖), the divider (│) and the
/// beard toggle. Collapsing stretches a divider so everything left of it is pushed off screen.
/// The always-hidden divider stays stretched except while icons are being arranged.
final class Divider {
    static let rehideDelay: TimeInterval = 5
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
    var onArrange: (() -> Void)?

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

        let arrange = menu.addItem(withTitle: "Arrange Icons…", action: #selector(arrangeClicked), keyEquivalent: "")
        arrange.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Barkeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        toggleItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clickedElsewhere()
        }

        // Start collapsed once the items have been placed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.collapse() }
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
        toggle()
    }

    @objc private func arrangeClicked() {
        onArrange?()
    }

    func toggle() {
        isCollapsed ? expand() : collapse()
    }

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

    func expand() {
        dividerItem.length = NSStatusItem.variableLength
        stretchAlways()
        isCollapsed = false
        updateIcon()
        scheduleRehide()
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

    private func scheduleRehide() {
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: Self.rehideDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A ⌘-drag to rearrange icons is invisible to our click monitor, so check the live
            // modifier and button state. Both class properties need no permission.
            if NSEvent.modifierFlags.contains(.command) || NSEvent.pressedMouseButtons != 0 {
                self.scheduleRehide()
            } else {
                self.collapse()
            }
        }
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
