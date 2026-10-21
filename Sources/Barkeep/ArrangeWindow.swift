import AppKit
import SwiftUI

/// The Arrange Icons window: three columns, drag an icon between them and Barkeep moves it
/// in the menu bar. Opening it shows every section; closing it re-hides.
final class ArrangeWindow: NSObject, NSWindowDelegate {
    private let model: ArrangeModel
    private var window: NSWindow?

    init(divider: Divider) {
        model = ArrangeModel(divider: divider)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Arrange Icons"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ArrangeView(model: model))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.opened()
    }

    func windowWillClose(_ notification: Notification) {
        model.closed()
    }
}

final class ArrangeModel: ObservableObject {
    @Published var trusted = MenuBarItems.isTrusted
    @Published var sections: [Section: [MenuBarItem]] = [:]
    @Published var status: String?
    @Published var busy = false
    private let divider: Divider
    private var trustPoll: Timer?

    init(divider: Divider) { self.divider = divider }

    func opened() {
        trusted = MenuBarItems.isTrusted
        guard trusted else { return }
        divider.beginArranging()
        // Give the menu bar a moment to lay out the newly shown icons.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.placeAlwaysDivider()
            self.load()
        }
    }

    func closed() {
        trustPoll?.invalidate()
        divider.endArranging()
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

    /// Drags ‖ to just left of │ if macOS put it on the wrong side. Positions then persist.
    private func placeAlwaysDivider() {
        guard divider.alwaysIsMisplaced, let a = divider.alwaysFrame, let d = divider.dividerFrame,
              let screen = NSScreen.screens.first else { return }
        // Window frames are bottom-left origin; drags use top-left.
        let topLeft = CGRect(x: a.minX, y: screen.frame.maxY - a.maxY, width: a.width, height: a.height)
        let me = MenuBarItem(id: "barkeep.always", pid: ProcessInfo.processInfo.processIdentifier,
                             name: "the always-hidden divider", icon: NSImage(), frame: topLeft)
        // Drag off the main thread: AppKit handles our own item's drag here, and a sleeping main thread can't.
        DispatchQueue.global(qos: .userInitiated).async {
            MenuBarItems.drag(me, toX: d.minX + 2)
            DispatchQueue.main.async {
                if self.divider.alwaysIsMisplaced {
                    self.status = "Couldn't place the always-hidden divider ‖. ⌘-drag it to the left of │ once."
                }
                self.load()
            }
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
    }

    func move(_ id: String, to target: Section) {
        guard !busy, let d = divider.dividerFrame, let a = divider.alwaysFrame,
              let item = sections.values.joined().first(where: { $0.id == id }) else { return }
        let current = MenuBarItems.section(of: item, divider: d, always: a)
        guard current != target else { return }
        if let reason = offScreenReason(item) {
            status = "Couldn't move \(item.name): \(reason)."
            return
        }
        // Drop just past the middle of the divider the icon has to cross.
        let x: CGFloat
        switch target {
        case .showing: x = d.maxX - 2
        case .hidden: x = current == .showing ? d.minX + 2 : a.maxX - 2
        case .always: x = a.minX + 2
        }
        busy = true
        status = "Moving \(item.name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            MenuBarItems.drag(item, toX: x)
            let items = MenuBarItems.read()
            DispatchQueue.main.async {
                self.busy = false
                self.sort(items)
                let landed = items.first { $0.id == id }.flatMap { moved -> Section? in
                    guard let d = self.divider.dividerFrame, let a = self.divider.alwaysFrame else { return nil }
                    return MenuBarItems.section(of: moved, divider: d, always: a)
                }
                self.status = landed == target
                    ? "Moved \(item.name) to \(target.rawValue)."
                    : "Couldn't move \(item.name). Try again, or ⌘-drag it by hand."
            }
        }
    }

    /// A synthetic drag only works on what's visible: not past the screen edge, not behind the notch.
    private func offScreenReason(_ item: MenuBarItem) -> String? {
        guard let screen = NSScreen.screens.first else { return nil }
        if item.frame.minX < screen.frame.minX || item.frame.maxX > screen.frame.maxX {
            return "it's off the edge of the screen. Hide a few icons first"
        }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           item.frame.midX > left.maxX, item.frame.midX < right.minX {
            return "it's behind the notch. Hide a few icons first"
        }
        return nil
    }
}

struct ArrangeView: View {
    @ObservedObject var model: ArrangeModel

    var body: some View {
        if model.trusted {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Section.allCases) { section in
                        Column(section: section, items: model.sections[section] ?? []) { id in
                            model.move(id, to: section)
                        }
                    }
                }
                HStack {
                    Text(model.status ?? "Drag an icon to another column. Barkeep moves it in the menu bar.")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Refresh") { model.load() }.disabled(model.busy)
                }
            }
            .padding(16)
            .frame(minWidth: 640, minHeight: 360)
        } else {
            PermissionView { model.requestTrust() }
        }
    }
}

private struct Column: View {
    let section: Section
    let items: [MenuBarItem]
    let onDrop: (String) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.rawValue).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(nsImage: item.icon).resizable().frame(width: 18, height: 18)
                            Text(item.name).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .draggable(item.id)
                    }
                    if items.isEmpty {
                        Text("Empty").foregroundStyle(.tertiary).padding(6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Barkeep needs Accessibility").font(.title2.bold())
            Text("To arrange your icons, Barkeep needs to see which app owns each menu bar icon, and to drag icons for you the way you would with ⌘-drag.")
            Text("Accessibility is the only macOS permission that allows both. Barkeep uses it for the menu bar and nothing else. It doesn't read your screen, your typing or other windows, and nothing leaves this Mac.")
            Text("Next, macOS will ask you to turn Barkeep on in System Settings › Privacy & Security › Accessibility. This window carries on by itself once it's on.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Continue", action: onContinue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
