import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotkey = Hotkey()
    /// Made once permission is granted: reading windows before that makes macOS
    /// put up its own alert, on top of the welcome window.
    private var switcher: Switcher?
    private let welcome = Welcome()
    private var statusItem: NSStatusItem?
    private var permissionItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var trusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One copy at a time, or two keyboard hooks would fight over Option-Tab.
        let id = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }
        // Don't let one frozen app stall the switcher.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        setUpMenu()

        trusted = AXIsProcessTrusted()
        if trusted {
            start()
            finishSetup()
        } else {
            welcome.show()
        }
        // Permission can be granted or taken away at any time; follow it.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
        updateIcon()
    }

    /// Opening the app again (Finder, Spotlight, Raycast) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        welcome.show()
        return false
    }

    private func checkPermission() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        if now {
            start()
            finishSetup()
        } else {
            // Permission was taken away: the keyboard hook is dead, so drop any open switcher.
            switcher?.handle(.cancel)
            hotkey.reset()
        }
        welcome.refresh()
        updateIcon()
    }

    /// The first time it has permission, however that happened: open at login, and say it's ready.
    private func finishSetup() {
        guard !UserDefaults.standard.bool(forKey: "welcomed") else { return }
        UserDefaults.standard.set(true, forKey: "welcomed")
        setOpenAtLogin(true)
        welcome.show()
    }

    private func start() {
        if switcher == nil {
            let switcher = Switcher()
            hotkey.onAction = { [switcher] in switcher.handle($0) }
            switcher.onClose = { [hotkey] in hotkey.reset() }
            self.switcher = switcher
        }
        hotkey.install()
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        let permission = menu.addItem(withTitle: "Allow Accessibility…", action: #selector(showWelcome), keyEquivalent: "")
        permission.target = self
        permissionItem = permission
        menu.addItem(withTitle: "Option-Tab to switch windows", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        loginItem = login
        menu.addItem(withTitle: "About alt-tabber", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit alt-tabber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem?.isHidden = trusted
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func updateIcon() {
        let symbol = trusted ? "rectangle.stack" : "exclamationmark.triangle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "alt-tabber")
    }

    @objc private func showWelcome() { welcome.show() }

    @objc private func toggleLogin() {
        setOpenAtLogin(SMAppService.mainApp.status != .enabled)
    }

    @objc private func about() {
        NSApp.activate()
        let credits = NSAttributedString(string: "Free and open source.\ngithub.com/alcun/alt-tabber",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
