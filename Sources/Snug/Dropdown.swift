import AppKit
import SwiftUI
import os

/// The dropdown under the beard: every menu bar icon in three rows (Showing, Hidden, Always hidden).
/// Click an icon to use it; drag it to another row to move it in the menu bar.
/// The menu bar itself stays collapsed; hidden icons are only shown for a moment when used or moved.
final class Dropdown: NSObject {
    private static let log = Logger(subsystem: "com.intentionaut.snug", category: "dropdown")
    private let model: DropdownModel
    private let divider: Divider
    private var panel: NSPanel?
    private var clickAway: Any?
    private var hosting: NSHostingController<DropdownView>?

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
        // Hidden icons can only be photographed while on screen, so read and capture everything at
        // launch, while nothing is hidden yet, then hide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [model, divider] in
            guard MenuBarItems.isTrusted else { return divider.collapse() }
            model.load { divider.collapse() }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            let counts = Section.allCases.map { "\($0.rawValue)=\(self.model.sections[$0]?.count ?? 0)" }.joined(separator: " ")
            Self.log.notice("panel frame=\(String(describing: panel.frame), privacy: .public) visible=\(panel.isVisible, privacy: .public) trusted=\(model.trusted, privacy: .public) \(counts, privacy: .public) screen=\(String(describing: NSScreen.screens.first?.frame), privacy: .public) toggle=\(String(describing: self.divider.toggleFrame), privacy: .public)")
        }
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
        let host = NSHostingController(rootView: DropdownView(model: model))
        hosting = host
        panel.contentViewController = host
        panel.onEscape = { [weak self] in self?.close() }
        return panel
    }

    /// Right edge under the beard, top edge just below the menu bar.
    private func position(_ panel: NSPanel) {
        // Ask SwiftUI directly: a hosting view's fittingSize comes back 0 × 0 for this content.
        guard let size = hosting?.sizeThatFits(in: NSSize(width: 440, height: 900)), size.width > 0, size.height > 0 else {
            Self.log.error("dropdown has no size yet")
            return
        }
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
    private static let log = Logger(subsystem: "com.intentionaut.snug", category: "dropdown")
    @Published var trusted = MenuBarItems.isTrusted
    @Published var sections: [Section: [MenuBarItem]] = [:]
    @Published var status: String?
    @Published var busy = false
    @Published var loading = false
    @Published var images: [String: NSImage] = [:]
    @Published var canCapture = IconCapture.isAllowed
    @Published var captureRequested = false
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

    /// Keeps showing the last list while a fresh one is read, so the panel is never empty on open.
    func load(then done: (() -> Void)? = nil) {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = MenuBarItems.read()
            DispatchQueue.main.async {
                self.loading = false
                self.sort(items, then: done)
            }
        }
    }

    private func sort(_ items: [MenuBarItem], then done: (() -> Void)? = nil) {
        guard let d = divider.dividerFrame, let a = divider.alwaysFrame else { return }
        sections = Dictionary(grouping: items) { MenuBarItems.section(of: $0, divider: d, always: a) }
        DispatchQueue.main.async { self.relayout?() }
        canCapture = IconCapture.isAllowed
        guard canCapture else { done?(); return }
        Task {
            let captured = await IconCapture.capture(items)
            await MainActor.run {
                // Keep earlier pictures of icons that are off screen now; replace the rest.
                self.images.merge(captured) { _, new in new }
                done?()
                self.relayout?()
            }
        }
    }

    func requestCapture() {
        IconCapture.request()
        captureRequested = true
    }

    private func section(of item: MenuBarItem) -> Section? {
        guard let d = divider.dividerFrame, let a = divider.alwaysFrame else { return nil }
        return MenuBarItems.section(of: item, divider: d, always: a)
    }

    /// Clicks the real icon. A hidden one is shown only until its menu closes; the click fires as
    /// soon as the icon is back on screen rather than after a fixed wait.
    func use(_ id: String) {
        guard !busy, let item = sections.values.joined().first(where: { $0.id == id }) else { return }
        let current = section(of: item)
        close?()
        let started = Date()
        if current != .showing { divider.reveal(includeAlways: current == .always, rehideAfter: 1) }
        let screen = NSScreen.screens.first?.frame ?? .zero
        DispatchQueue.global(qos: .userInitiated).async {
            var live: MenuBarItem?
            for _ in 0..<20 {
                live = MenuBarItems.read().first { $0.id == id }
                if let x = live?.frame.minX, x >= screen.minX, x < screen.maxX { break }
                Thread.sleep(forTimeInterval: 0.03)
            }
            guard let live else { return }
            MenuBarItems.click(live)
            // It's on screen now, so refresh its picture.
            DispatchQueue.main.async { self.load() }
            Self.log.notice("clicked \(item.name, privacy: .public) \(Date().timeIntervalSince(started), privacy: .public)s after the press")
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
                        Row(section: section, items: model.sections[section] ?? [], images: model.images,
                            busy: model.busy, onUse: model.use, onDrop: { model.move($0, to: section) })
                    }
                    if model.sections.isEmpty && model.loading {
                        Text("Reading your menu bar…").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.canCapture {
                        CaptureBanner(requested: model.captureRequested, onAllow: model.requestCapture,
                                      onReopen: IconCapture.relaunch)
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
        .glass()
    }
}

/// One section as a wrapping grid of icons. Click to use, drag to another row to move.
private struct Row: View {
    let section: Section
    let items: [MenuBarItem]
    let images: [String: NSImage]
    let busy: Bool
    let onUse: (String) -> Void
    let onDrop: (String) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Flow(spacing: 2) {
                ForEach(items) { item in
                    Button { onUse(item.id) } label: {
                        // The real icon at its menu bar size when captured; the app's Dock icon otherwise.
                        if let image = images[item.id] {
                            Image(nsImage: image).frame(width: image.size.width, height: image.size.height)
                        } else {
                            Image(nsImage: item.icon).resizable().frame(width: 20, height: 20).padding(6)
                        }
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
        .background(RoundedRectangle(cornerRadius: 10).fill(targeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
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
            Text("Snug needs Accessibility").font(.headline)
            Text("To list your menu bar icons here, Snug needs to see which app owns each one. To open or move an icon for you, it clicks or ⌘-drags it the way you would.")
            Text("Accessibility is the only macOS permission that allows both. Snug uses it for the menu bar and nothing else. It doesn't read your screen, your typing or other windows, and nothing leaves this Mac.")
            Text("Next, macOS will ask you to turn Snug on in System Settings › Privacy & Security › Accessibility. This carries on by itself once it's on.")
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

/// Lays icons out left to right, wrapping to a new line when the row is full. Icons vary in width
/// (a clock is wider than a battery), so a fixed grid would leave gaps.
private struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

private struct CaptureBanner: View {
    let requested: Bool
    let onAllow: () -> Void
    let onReopen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Show real icons").font(.callout.weight(.semibold))
                Text(requested
                     ? "Once Snug is on in Screen & System Audio Recording, reopen it to apply."
                     : "Needs Screen Recording. Snug captures only the menu bar icons' own small windows, keeps the pictures in memory, never saves them, and nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(requested ? "Reopen" : "Allow…", action: requested ? onReopen : onAllow)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

private extension View {
    /// Liquid Glass on macOS 26, the older frosted material before it.
    @ViewBuilder func glass() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
