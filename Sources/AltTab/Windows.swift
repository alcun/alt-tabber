import AppKit
import ApplicationServices

struct WindowItem {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
    let element: AXUIElement
    let minimized: Bool
}

enum Windows {
    /// Windows on the current Space, most recently used first, then minimized and hidden ones.
    static func list() -> [WindowItem] {
        // The WindowServer lists on-screen windows front to back, which is recency order.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (i, w) in info.enumerated() where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let id = w[kCGWindowNumber as String] as? CGWindowID { order[id] = i }
        }

        var items: [(item: WindowItem, rank: Int)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25) // don't hang on a frozen app
            guard let windows = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for w in windows {
                var id: CGWindowID = 0
                guard _AXUIElementGetWindow(w, &id) == .success, id != 0 else { continue }
                guard attribute(w, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { continue }
                let minimized = attribute(w, kAXMinimizedAttribute) as? Bool ?? false
                let rank: Int
                if let onScreen = order[id] { rank = onScreen }
                else if minimized || app.isHidden { rank = Int.max / 2 }
                else { continue } // on another Space
                let appName = app.localizedName ?? ""
                let title = (attribute(w, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
                items.append((WindowItem(id: id, pid: app.processIdentifier, title: title, appName: appName,
                                         icon: app.icon, element: w, minimized: minimized), rank))
            }
        }
        return items.sorted { $0.rank < $1.rank }.map(\.item)
    }

    /// Focus steps from AltTab: front the process with this window, make it key, raise it.
    static func focus(_ item: WindowItem) {
        if item.minimized {
            AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if let app = NSRunningApplication(processIdentifier: item.pid), app.isHidden { app.unhide() }
        var psn = ProcessSerialNumber()
        GetProcessForPID(item.pid, &psn)
        _SLPSSetFrontProcessWithOptions(&psn, item.id, userGeneratedMode)
        makeKeyWindow(&psn, item.id)
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
