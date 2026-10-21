import AppKit
import SwiftUI

/// The dropdown under the beard: every menu bar icon in three rows (Showing, Hidden, Always hidden).
/// Click an icon to use it; drag it to another row to move it in the menu bar.
/// The menu bar itself stays collapsed; hidden icons are only shown for a moment when used or moved.
final class Dropdown: NSObject {
    private let model: DropdownModel
    private let divider: Divider
    private var panel: NSPanel?
    private var clickAway: Any?

    init(divider: Divider) {
        self.divider = divider
        model = DropdownModel(divider: divider)
        super.init()
        model.close = { [weak self] in self?.close() }
        // Content arrives after opening; keep the panel pinned under the beard as it grows.
        model.relayout = { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            self.position(panel)
        }
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.opened()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        clickAway = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let clickAway { NSEvent.removeMonitor(clickAway) }
        clickAway = nil
        model.closed()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                             styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                             backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: DropdownView(model: model))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }
        return panel
    }

    /// Right edge under the beard, top edge just below the menu bar.
    private func position(_ panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        guard let anchor = divider.toggleFrame, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        let x = min(anchor.maxX, screen.visibleFrame.maxX - 8) - size.width
        let y = screen.visibleFrame.maxY - 6 - size.height
        panel.setFrame(NSRect(x: max(x, screen.visibleFrame.minX + 8), y: y, width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel that can take key focus (for drags and Esc) without activating like a window.
private final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class DropdownModel: ObservableObject {
    @Published var trusted = MenuBarItems.isTrusted
    @Published var sections: [Section: [MenuBarItem]] = [:]
    @Published var status: String?
    @Published var busy = false
    var close: (() -> Void)?
    var relayout: (() -> Void)?
    private let divider: Divider
    private var trustPoll: Timer?

    init(divider: Divider) { self.divider = divider }

    func opened() {
        status = nil
        trusted = MenuBarItems.isTrusted
        guard trusted else { return }
        if divider.alwaysIsMisplaced { placeAlwaysDivider() } else { load() }
    }

    func closed() {
        trustPoll?.invalidate()
    }

    /// Shows macOS's own prompt, then waits for the switch to be turned on.
    func requestTrust() {
        MenuBarItems.requestTrust()
        trustPoll?.invalidate()
        trustPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, MenuBarItems.isTrusted else { return }
            timer.invalidate()
            self.trusted = true
            self.opened()
        }
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let items = MenuBarItems.read()
            DispatchQueue.main.async { self.sort(items) }
        }
    }

    private func sort(_ items: [MenuBarItem]) {
        guard let d = divider.dividerFrame, let a = divider.alwaysFrame else { return }
        sections = Dictionary(grouping: items) { MenuBarItems.section(of: $0, divider: d, always: a) }
        DispatchQueue.main.async { self.relayout?() }
    }

    private func section(of item: MenuBarItem) -> Section? {
        guard let d = divider.dividerFrame, let a = divider.alwaysFrame else { return nil }
        return MenuBarItems.section(of: item, divider: d, always: a)
    }

    /// Clicks the real icon: shows it for a moment if it's hidden, then re-hides on the usual timer.
    func use(_ id: String) {
        guard !busy, let item = sections.values.joined().first(where: { $0.id == id }) else { return }
        let current = section(of: item)
        close?()
        if current != .showing { divider.reveal(includeAlways: current == .always) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (current == .showing ? 0 : 0.35)) {
            // Re-read: revealing moved it.
            guard let live = MenuBarItems.read().first(where: { $0.id == id }) else { return }
            MenuBarItems.click(live)
        }
    }

    /// Moves an icon between rows: shows everything, does the ⌘-drag, checks it landed, re-hides.
    func move(_ id: String, to target: Section) {
        guard !busy, let item = sections.values.joined().first(where: { $0.id == id }),
              let current = section(of: item), current != target else { return }
        busy = true
        status = "Moving \(item.name)…"
        divider.beginArranging()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.4) {
            let fresh = MenuBarItems.read()
            DispatchQueue.main.async {
                guard let live = fresh.first(where: { $0.id == id }),
                      let d = self.divider.dividerFrame, let a = self.divider.alwaysFrame else {
                    return self.finish("Couldn't find \(item.name) in the menu bar.")
                }
                if let reason = Self.offScreenReason(live) {
                    return self.finish("Couldn't move \(item.name): \(reason).")
                }
                // Drop just past the middle of the divider the icon has to cross.
                let x: CGFloat
                switch target {
                case .showing: x = d.maxX - 2
                case .hidden: x = current == .showing ? d.minX + 2 : a.maxX - 2
                case .always: x = a.minX + 2
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    MenuBarItems.drag(live, toX: x)
                    let after = MenuBarItems.read()
                    DispatchQueue.main.async {
                        let landed = after.first { $0.id == id }.flatMap(self.section(of:))
                        self.finish(landed == target ? nil : "Couldn't move \(item.name). Try again, or ⌘-drag it by hand.")
                    }
                }
            }
        }
    }

    private func finish(_ problem: String?) {
        divider.endArranging()
        busy = false
        status = problem
        load()
    }

    /// Drags ‖ to just left of │ if macOS put it on the wrong side. Positions then persist.
    private func placeAlwaysDivider() {
        divider.beginArranging()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let a = self.divider.alwaysFrame, let d = self.divider.dividerFrame,
                  let screen = NSScreen.screens.first else { return self.finish(nil) }
            // Window frames are bottom-left origin; drags use top-left.
            let topLeft = CGRect(x: a.minX, y: screen.frame.maxY - a.maxY, width: a.width, height: a.height)
            let me = MenuBarItem(id: "barkeep.always", pid: ProcessInfo.processInfo.processIdentifier,
                                 name: "the always-hidden divider", icon: NSImage(), frame: topLeft)
            // Off the main thread: AppKit handles our own item's drag here, and a sleeping main thread can't.
            DispatchQueue.global(qos: .userInitiated).async {
                MenuBarItems.drag(me, toX: d.minX + 2)
                DispatchQueue.main.async {
                    self.finish(self.divider.alwaysIsMisplaced
                        ? "Couldn't place the always-hidden divider ‖. ⌘-drag it to the left of │ once." : nil)
                }
            }
        }
    }

    /// A synthetic drag only works on what's visible: not past the screen edge, not behind the notch.
    private static func offScreenReason(_ item: MenuBarItem) -> String? {
        guard let screen = NSScreen.screens.first else { return nil }
        if item.frame.minX < screen.frame.minX || item.frame.maxX > screen.frame.maxX {
            return "it's off the edge of the screen. Move a few icons to Always hidden first"
        }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           item.frame.midX > left.maxX, item.frame.midX < right.minX {
            return "it's behind the notch. Move a few icons to Always hidden first"
        }
        return nil
    }
}

struct DropdownView: View {
    @ObservedObject var model: DropdownModel

    var body: some View {
        Group {
            if model.trusted {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Section.allCases) { section in
                        Row(section: section, items: model.sections[section] ?? [], busy: model.busy,
                            onUse: model.use, onDrop: { model.move($0, to: section) })
                    }
                    if let status = model.status {
                        Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(width: 420)
            } else {
                PermissionView { model.requestTrust() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One section as a wrapping grid of icons. Click to use, drag to another row to move.
private struct Row: View {
    let section: Section
    let items: [MenuBarItem]
    let busy: Bool
    let onUse: (String) -> Void
    let onDrop: (String) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    Button { onUse(item.id) } label: {
                        Image(nsImage: item.icon).resizable().frame(width: 20, height: 20).padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                    .disabled(busy)
                    .draggable(item.id)
                }
            }
            .frame(minHeight: 30, alignment: .topLeading)
            .overlay(alignment: .leading) {
                if items.isEmpty { Text("Drag icons here").font(.caption).foregroundStyle(.tertiary) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct PermissionView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barkeep needs Accessibility").font(.headline)
            Text("To list your menu bar icons here, Barkeep needs to see which app owns each one. To open or move an icon for you, it clicks or ⌘-drags it the way you would.")
            Text("Accessibility is the only macOS permission that allows both. Barkeep uses it for the menu bar and nothing else. It doesn't read your screen, your typing or other windows, and nothing leaves this Mac.")
            Text("Next, macOS will ask you to turn Barkeep on in System Settings › Privacy & Security › Accessibility. This carries on by itself once it's on.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Continue", action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
