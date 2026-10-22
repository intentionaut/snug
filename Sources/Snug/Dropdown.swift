import AppKit
import SwiftUI
import os

/// The dropdown under the mousehole: every menu bar icon in three rows (Showing, Hidden, Always hidden).
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
        // Content arrives after opening; keep the panel pinned under the mousehole as it grows.
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

    func testMove(named name: String, to target: Section) { model.testMove(named: name, to: target) }

    /// Diagnostic: clicks the first icon whose name contains `name`, as the panel would.
    func testUse(named name: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [model] in
            guard let item = model.sections.values.joined().first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else { return }
            model.use(item.id)
        }
    }

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

    /// Right edge under the mousehole, top edge just below the menu bar.
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
    /// Each icon's section as the person last left it, so a relaunched app's icon can be put back.
    private var saved: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "savedSections") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "savedSections") }
    }
    /// Apps that launched recently: their icons may be in macOS's default spot, not where they were left.
    private var restoring = Set<pid_t>()
    var close: (() -> Void)?
    var relayout: (() -> Void)?
    private let divider: Divider
    private var trustPoll: Timer?

    init(divider: Divider) {
        self.divider = divider
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.restoreIcons(of: app.processIdentifier)
        }
    }

    /// When an app launches, macOS may put its icon back in its default spot. Wait for the icon
    /// to appear, then move it to the section it was in. Only relaunched apps are touched, so a
    /// person's own ⌘-drags are never undone.
    private func restoreIcons(of pid: pid_t) {
        restoring.insert(pid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let dWin = self.divider.dividerWindow, let aWin = self.divider.alwaysWindow else {
                self.restoring.remove(pid); return
            }
            let saved = self.saved
            DispatchQueue.global(qos: .utility).async {
                let frames = ItemMover.windowFrames()
                let mine = MenuBarItems.read().filter { $0.pid == pid }
                for item in mine {
                    guard let want = saved[item.id].flatMap(Section.init(rawValue:)),
                          let window = ItemMover.window(for: item, in: frames),
                          let d = frames[dWin], let a = frames[aWin] else { continue }
                    let now = MenuBarItems.section(of: item, divider: d, always: a)
                    guard now != want else { continue }
                    let ok = ItemMover.move(item, window: window, to: Self.destination(from: now, to: want, divider: dWin, always: aWin))
                    Self.log.notice("restored \(item.name, privacy: .public) to \(want.rawValue, privacy: .public): \(ok, privacy: .public)")
                }
                DispatchQueue.main.async {
                    self.restoring.remove(pid)
                    self.load()
                }
            }
        }
    }

    static func destination(from current: Section, to target: Section, divider dWin: CGWindowID, always aWin: CGWindowID) -> ItemMover.Destination {
        switch target {
        case .showing: return .rightOf(dWin)
        case .hidden: return current == .showing ? .leftOf(dWin) : .rightOf(aWin)
        case .always: return .leftOf(aWin)
        }
    }

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
        // Take the dividers' positions from the same moment as the icons'; comparing an old read
        // with dividers that have since collapsed sorted Tailscale into the wrong section.
        let frames = (divider.dividerFrame, divider.alwaysFrame)
        let shown = (frames.0?.width ?? .infinity) < 200 && (frames.1?.width ?? .infinity) < 200
        DispatchQueue.global(qos: .userInitiated).async {
            // A fully shown bar may still be settling (at launch); wait for it, since this read decides sections.
            let items = shown ? MenuBarItems.readSettled() : MenuBarItems.read()
            DispatchQueue.main.async {
                self.loading = false
                // If a divider changed width during the read, the icons and dividers are from
                // different moments: sort from what's remembered, record nothing.
                let unchanged = self.divider.dividerFrame == frames.0 && self.divider.alwaysFrame == frames.1
                self.sort(items, divider: frames.0, always: frames.1, recording: unchanged, then: done)
            }
        }
    }

    private func sort(_ items: [MenuBarItem], divider d: CGRect?, always a: CGRect?, recording: Bool, then done: (() -> Void)? = nil) {
        guard let d, let a else { return }
        // Window-server positions: off-screen icons keep their real order.
        _ = recording
        sections = Dictionary(grouping: items) { MenuBarItems.section(of: $0, divider: d, always: a) }
        if restoring.isEmpty, !busy, recording {
            var next = saved
            for (section, list) in sections { for item in list { next[item.id] = section.rawValue } }
            saved = next
        }
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

    /// Clicks the real icon. A hidden one is moved, on its own, just right of │ so it is on screen,
    /// clicked, then put back beside its old neighbour once its menu closes. Nothing else moves.
    func use(_ id: String) {
        guard !busy, let item = sections.values.joined().first(where: { $0.id == id }) else { return }
        let current = section(of: item)
        close?()
        let started = Date()
        guard current != .showing else {
            return DispatchQueue.global(qos: .userInitiated).async {
                guard let live = MenuBarItems.readKnown().first(where: { $0.id == id }) else { return }
                MenuBarItems.click(live)
                Self.log.notice("clicked \(item.name, privacy: .public) in \(Date().timeIntervalSince(started), privacy: .public)s")
            }
        }
        guard let dWin = divider.dividerWindow else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let frames = ItemMover.windowFrames()
            guard let live = MenuBarItems.readKnown().first(where: { $0.id == id }),
                  let window = ItemMover.window(for: live, in: frames),
                  let own = frames[window] else {
                return DispatchQueue.main.async { self.busy = false }
            }
            // Its neighbour on the right is where it goes back to.
            let neighbour = frames.filter { $0.key != window && $0.value.minX >= own.maxX - 1 }
                .min { $0.value.minX < $1.value.minX }?.key
            guard ItemMover.move(live, window: window, to: .rightOf(dWin)),
                  let shown = MenuBarItems.readKnown().first(where: { $0.id == id }) else {
                return DispatchQueue.main.async { self.busy = false; self.status = "Couldn't open \(item.name)." }
            }
            MenuBarItems.click(shown)
            Self.log.notice("clicked \(item.name, privacy: .public) in \(Date().timeIntervalSince(started), privacy: .public)s")
            DispatchQueue.main.async {
                self.busy = false
                // Refresh its picture while it's on screen.
                self.load()
                if let neighbour { self.putBack(id, window: window, leftOf: neighbour) }
            }
        }
    }

    /// Waits for the icon's menu to close (two quiet checks, at least a second), then moves it back.
    private func putBack(_ id: String, window: CGWindowID, leftOf neighbour: CGWindowID) {
        var quiet = 0
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            quiet = Divider.menuIsOpen() || NSEvent.pressedMouseButtons != 0 ? 0 : quiet + 1
            guard quiet >= 2, Date().timeIntervalSince(started) > 1, !self.busy else { return }
            timer.invalidate()
            DispatchQueue.global(qos: .userInitiated).async {
                guard let live = MenuBarItems.readKnown().first(where: { $0.id == id }) else { return }
                let back = ItemMover.move(live, window: window, to: .leftOf(neighbour))
                Self.log.notice("put back \(live.name, privacy: .public): \(back ? "done" : "failed", privacy: .public)")
                DispatchQueue.main.async { self.load() }
            }
        }
    }

    /// Diagnostic: moves the first icon whose name contains `name` to `target`, logging the result.
    func testMove(named name: String, to target: Section) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let item = self.sections.values.joined().first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
                return Self.log.error("test-move: no icon named \(name, privacy: .public)")
            }
            Self.log.notice("test-move: \(item.name, privacy: .public) to \(target.rawValue, privacy: .public)")
            self.move(item.id, to: target)
            // Report once the move has finished.
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                guard !self.busy else { return }
                timer.invalidate()
                Self.log.notice("test-move: done, status: \(self.status ?? "ok", privacy: .public)")
            }
        }
    }

    /// Moves an icon between rows with ItemMover: events addressed to the icon's window, nothing
    /// revealed, positions from the window server. Works off screen and beside the notch.
    func move(_ id: String, to target: Section) {
        let item = sections.values.joined().first { $0.id == id }
        Self.log.notice("drop \(id, privacy: .public) on \(target.rawValue, privacy: .public): found=\(item != nil, privacy: .public) busy=\(self.busy, privacy: .public)")
        guard !busy, let item, let dWin = divider.dividerWindow, let aWin = divider.alwaysWindow else { return }
        busy = true
        status = "Moving \(item.name)…"
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let frames = ItemMover.windowFrames()
            guard let live = MenuBarItems.readKnown().first(where: { $0.id == id }),
                  let window = ItemMover.window(for: live, in: frames),
                  let d = frames[dWin], let a = frames[aWin] else {
                return DispatchQueue.main.async { self.finish("Couldn't find \(item.name) in the menu bar.") }
            }
            let current = MenuBarItems.section(of: live, divider: d, always: a)
            Self.log.notice("move \(item.name, privacy: .public): \(current.rawValue, privacy: .public) → \(target.rawValue, privacy: .public)")
            guard current != target else { return DispatchQueue.main.async { self.finish(nil) } }
            let destination = Self.destination(from: current, to: target, divider: dWin, always: aWin)
            let moved = ItemMover.move(live, window: window, to: destination)
            Self.log.notice("move \(item.name, privacy: .public): \(moved ? "done" : "failed", privacy: .public) in \(Date().timeIntervalSince(started), privacy: .public)s")
            DispatchQueue.main.async {
                self.finish(moved ? nil : "Couldn't move \(item.name). Try again, or ⌘-drag it by hand.")
            }
        }
    }


    private func finish(_ problem: String?) {
        if divider.isArranging { divider.endArranging() }
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
            let me = MenuBarItem(id: "snug.always", pid: ProcessInfo.processInfo.processIdentifier,
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

}

struct DropdownView: View {
    @ObservedObject var model: DropdownModel
    /// The icon being dragged and where the pointer is, in the panel's coordinates.
    @State private var drag: (id: String, at: CGPoint)?
    @State private var rowFrames: [Section: CGRect] = [:]

    private var targetRow: Section? {
        guard let drag else { return nil }
        return rowFrames.first { $0.value.contains(drag.at) }?.key
    }

    var body: some View {
        Group {
            if model.trusted {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Section.allCases) { section in
                        Row(section: section, items: model.sections[section] ?? [], images: model.images,
                            busy: model.busy, dragging: drag?.id, highlighted: targetRow == section,
                            onUse: model.use,
                            onDragChanged: { id, at in drag = (id, at) },
                            onDragEnded: { id, at in
                                let target = rowFrames.first { $0.value.contains(at) }?.key
                                drag = nil
                                if let target { model.move(id, to: target) }
                            })
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
                .coordinateSpace(name: "panel")
                .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
            } else {
                PermissionView { model.requestTrust() }
            }
        }
        .glass()
    }
}

/// Each row's frame in the panel, so a drag can tell which row it ended over.
private struct RowFrames: PreferenceKey {
    static let defaultValue: [Section: CGRect] = [:]
    static func reduce(value: inout [Section: CGRect], nextValue: () -> [Section: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One section as a wrapping grid of icons. Click to use; drag to another row to move.
/// Dragging is a plain gesture tracked by Snug, not system drag and drop, which handed the icon
/// over through the pasteboard and dropped out intermittently in this non-activating panel.
private struct Row: View {
    let section: Section
    let items: [MenuBarItem]
    let images: [String: NSImage]
    let busy: Bool
    let dragging: String?
    let highlighted: Bool
    let onUse: (String) -> Void
    let onDragChanged: (String, CGPoint) -> Void
    let onDragEnded: (String, CGPoint) -> Void
    @State private var offset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Flow(spacing: 2) {
                ForEach(items) { item in
                    icon(item)
                        .contentShape(Rectangle())
                        .offset(dragging == item.id ? offset : .zero)
                        .zIndex(dragging == item.id ? 1 : 0)
                        .help(item.name)
                        .opacity(busy ? 0.5 : 1)
                        .onTapGesture { if !busy { onUse(item.id) } }
                        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("panel"))
                            .onChanged { value in
                                guard !busy else { return }
                                offset = value.translation
                                onDragChanged(item.id, value.location)
                            }
                            .onEnded { value in
                                offset = .zero
                                guard !busy else { return }
                                onDragEnded(item.id, value.location)
                            })
                }
            }
            .frame(minHeight: 30, alignment: .topLeading)
            .overlay(alignment: .leading) {
                if items.isEmpty { Text("Drag icons here").font(.caption).foregroundStyle(.tertiary) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
        .background(GeometryReader { geo in
            Color.clear.preference(key: RowFrames.self, value: [section: geo.frame(in: .named("panel"))])
        })
        .zIndex(dragging.map { id in items.contains { $0.id == id } } == true ? 1 : 0)
    }

    /// The real icon at its menu bar size when captured; the app's Dock icon otherwise.
    @ViewBuilder private func icon(_ item: MenuBarItem) -> some View {
        if let image = images[item.id] {
            Image(nsImage: image).frame(width: image.size.width, height: image.size.height)
        } else {
            Image(nsImage: item.icon).resizable().frame(width: 20, height: 20).padding(6)
        }
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
