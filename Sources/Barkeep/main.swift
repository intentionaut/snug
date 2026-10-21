import AppKit
import os

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `open build/Barkeep.app --args --dump` logs every icon Barkeep can see and where it sorts it.
    private func dump() {
        let log = Logger(subsystem: "local.elle.barkeep", category: "dump")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            log.notice("trusted=\(MenuBarItems.isTrusted, privacy: .public) divider=\(String(describing: self.divider.dividerFrame), privacy: .public) always=\(String(describing: self.divider.alwaysFrame), privacy: .public)")
            let items = MenuBarItems.read()
            log.notice("read \(items.count, privacy: .public) items")
            for item in items {
                let section = self.divider.dividerFrame.flatMap { d in self.divider.alwaysFrame.map { MenuBarItems.section(of: item, divider: d, always: $0).rawValue } } ?? "?"
                log.notice("\(section, privacy: .public)  x=\(item.frame.minX, privacy: .public) w=\(item.frame.width, privacy: .public)  \(item.name, privacy: .public)")
            }
        }
    }

    private var divider: Divider!
    private var hotKey: HotKey!
    private var dropdown: Dropdown!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An accessory app with no windows is otherwise eligible to be quit by the system.
        ProcessInfo.processInfo.disableAutomaticTermination("Barkeep lives in the menu bar")
        divider = Divider()
        dropdown = Dropdown(divider: divider)
        divider.onOpen = { [weak self] in self?.dropdown.toggle() }
        // `open build/Barkeep.app --args --request-capture` shows the Screen Recording prompt.
        if CommandLine.arguments.contains("--request-capture") { IconCapture.request() }
        if CommandLine.arguments.contains("--dump") {
            dump()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.dropdown.open() }
        }
        // ⌃⌥⌘B
        hotKey = HotKey(keyCode: 11, modifiers: [.control, .option, .command]) { [weak self] in
            self?.dropdown.toggle()
        }
    }
}
