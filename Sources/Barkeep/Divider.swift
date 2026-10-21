import AppKit
import os

/// Two status items: a beard-and-bowtie toggle (rightmost) and a thin divider to its left.
/// Collapsing stretches the divider so everything left of it is pushed off screen.
/// ⌘-drag the divider to choose where hiding starts.
final class Divider {
    static let rehideDelay: TimeInterval = 5
    private static let collapsedLength: CGFloat = 10_000

    private let log = Logger(subsystem: "local.elle.barkeep", category: "divider")
    private let toggleItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private var rehideTimer: Timer?
    private var clickMonitor: Any?
    private let quitMenu = NSMenu()
    private(set) var isCollapsed = false

    init() {
        // Items created later sit further left, so the toggle goes first.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "barkeep.toggle"
        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        dividerItem.autosaveName = "barkeep.divider"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
        }
        dividerItem.button?.title = "│"
        dividerItem.button?.appearsDisabled = true

        quitMenu.addItem(withTitle: "Quit Barkeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func toggleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleItem.menu = quitMenu
            toggleItem.button?.performClick(nil)
            toggleItem.menu = nil
            return
        }
        toggle()
    }

    func toggle() {
        isCollapsed ? expand() : collapse()
    }

    func collapse() {
        rehideTimer?.invalidate()
        // If the divider was dragged right of the toggle, stretching it would hide the toggle too.
        guard let dividerX = dividerItem.button?.window?.frame.minX,
              let toggleX = toggleItem.button?.window?.frame.minX,
              dividerX < toggleX else {
            let d = dividerItem.button?.window?.frame.minX ?? -1, t = toggleItem.button?.window?.frame.minX ?? -1
            log.error("divider (x \(d, privacy: .public)) is not left of the toggle (x \(t, privacy: .public)); refusing to collapse")
            return
        }
        dividerItem.length = Self.collapsedLength
        isCollapsed = true
        updateIcon()

        // The macOS 26 check: did the system grant the full length?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let width = self.dividerItem.button?.window?.frame.width else { return }
            self.log.notice("collapsed divider width: \(width, privacy: .public) (asked \(Self.collapsedLength, privacy: .public))")
        }
    }

    func expand() {
        dividerItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateIcon()
        scheduleRehide()
    }

    private func scheduleRehide() {
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: Self.rehideDelay, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    /// Global monitors only see clicks in other apps. A click in the menu bar
    /// (opening a revealed item) restarts the timer; a click anywhere else re-hides.
    private func clickedElsewhere() {
        guard !isCollapsed else { return }
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
