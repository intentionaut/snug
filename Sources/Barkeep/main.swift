import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var divider: Divider!
    private var hotKey: HotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An accessory app with no windows is otherwise eligible to be quit by the system.
        ProcessInfo.processInfo.disableAutomaticTermination("Barkeep lives in the menu bar")
        divider = Divider()
        // ⌃⌥⌘B
        hotKey = HotKey(keyCode: 11, modifiers: [.control, .option, .command]) { [weak self] in
            self?.divider.toggle()
        }
    }
}
