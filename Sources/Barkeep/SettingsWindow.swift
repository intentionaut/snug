import AppKit
import ServiceManagement
import SwiftUI

/// The small settings window: launch at login, re-hide delay, and where each permission stands.
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 10),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Barkeep Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @AppStorage(Divider.rehideDelayKey) private var rehideDelay = Divider.defaultRehideDelay
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Open Barkeep at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Stepper(value: $rehideDelay, in: 2...30, step: 1) {
                Text("Re-hide after \(Int(rehideDelay)) seconds")
            }
            LabeledContent("Shortcut", value: "⌃⌥⌘B")
            SwiftUI.Section("Permissions") {
                LabeledContent("Accessibility", value: MenuBarItems.isTrusted ? "On" : "Off")
                LabeledContent("Screen Recording", value: IconCapture.isAllowed ? "On" : "Off: showing app icons")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        // Show what macOS actually did, not what was asked for.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
