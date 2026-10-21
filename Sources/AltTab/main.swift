import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkey = Hotkey()
    private let switcher = Switcher()
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenu()
        // Don't let one frozen app stall the switcher.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        hotkey.onAction = { [switcher] in switcher.handle($0) }
        switcher.onClose = { [hotkey] in hotkey.reset() }
        // Ask for Accessibility once, then wait for it to be granted.
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if !(trusted && hotkey.install()) {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [hotkey] timer in
                if AXIsProcessTrusted() && hotkey.install() { timer.invalidate() }
            }
        }
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "AltTab")
        let menu = NSMenu()
        menu.addItem(withTitle: "Option-Tab to switch windows", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem = login
        menu.addItem(withTitle: "Quit AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
        loginItem?.state = service.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
