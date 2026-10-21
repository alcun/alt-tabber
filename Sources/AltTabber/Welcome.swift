import AppKit
import ServiceManagement

/// The app's one window. On first run it gets you to the Accessibility setting, then
/// says you're ready. Opening the app again brings it back, so it's always reachable
/// even when the menu bar icon is hidden.
final class Welcome: NSObject {
    private var window: NSWindow?
    private let title = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let allow = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "Turn on alt-tabber in the list, then come back here.")
    private let login = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
    private let done = NSButton(title: "Done", target: nil, action: nil)

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless() // macOS may refuse to activate us; show it anyway
    }

    /// Called when permission changes, so the window flips to "ready" while you watch.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        title.stringValue = trusted ? "alt-tabber is ready" : "Allow alt-tabber"
        body.stringValue = trusted
            ? "Hold Option and press Tab to switch windows. Keep tapping Tab to move, and let go to switch."
            : "alt-tabber needs Accessibility permission to see Option-Tab and bring windows forward. It doesn't record or send anything."
        allow.isHidden = trusted
        hint.isHidden = trusted
        login.isHidden = !trusted
        done.isHidden = !trusted
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func build() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.alignment = .center
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.preferredMaxLayoutWidth = 320
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        for button in [allow, done] {
            button.bezelStyle = .push
            button.controlSize = .large
            button.target = self
        }
        // Return presses whichever button is showing, and it draws as the blue default.
        allow.keyEquivalent = "\r"
        done.keyEquivalent = "\r"
        allow.action = #selector(openSettings)
        done.action = #selector(close)
        login.target = self
        login.action = #selector(toggleLogin)

        let stack = NSStackView(views: [icon, title, body, allow, hint, login, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(20, after: body)
        stack.setCustomSpacing(16, after: login)
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 40, bottom: 28, right: 40)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 10),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.center()
        self.window = window
    }

    @objc private func openSettings() {
        // System Settings doesn't refresh an open list, so restart it, or alt-tabber
        // won't be there to turn on.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        running.forEach { $0.terminate() }
        let delay: TimeInterval = running.isEmpty ? 0 : 1
        // The first time, macOS's own alert adds alt-tabber to the list and links to it.
        // It only shows once, so after that, open the list ourselves.
        if !UserDefaults.standard.bool(forKey: "asked") {
            UserDefaults.standard.set(true, forKey: "asked")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc private func toggleLogin() {
        setOpenAtLogin(login.state == .on)
        refresh()
    }

    @objc private func close() { window?.close() }
}

func setOpenAtLogin(_ on: Bool) {
    let service = SMAppService.mainApp
    try? on ? service.register() : service.unregister()
}
