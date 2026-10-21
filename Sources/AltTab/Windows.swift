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
    let otherSpace: Bool
}

/// Knows every window across Spaces and the order you last used them in.
/// Lives on the main thread; only the brute-force search runs in the background.
final class Windows {
    /// Windows seen before, so ones on other Spaces can still be listed.
    private var known: [CGWindowID: (pid: pid_t, element: AXUIElement)] = [:]
    /// Windows the background search already looked for, so it doesn't repeat itself.
    private var searched: Set<CGWindowID> = []
    private var searching = false
    private var lastUsed: [CGWindowID: Int] = [:]
    private var clock = 0

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Give apps a moment to report the new Space's windows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { _ = self?.currentSpaceWindows() }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markFocusedWindowUsed()
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            self?.known = self?.known.filter { $0.value.pid != pid } ?? [:]
        }
        _ = currentSpaceWindows()
        searchOtherSpaces()
    }

    /// Every window, most recently used first.
    func list() -> [WindowItem] {
        markFocusedWindowUsed()
        // The WindowServer lists on-screen windows front to back, which breaks ties in recency.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var onScreen: [CGWindowID: Int] = [:]
        for (i, w) in info.enumerated() where (w[kCGWindowLayer as String] as? Int) == 0 {
            if let id = w[kCGWindowNumber as String] as? CGWindowID { onScreen[id] = i }
        }

        var items: [CGWindowID: WindowItem] = [:]
        for (id, pid, element) in currentSpaceWindows() {
            if let item = makeItem(id, pid, element, otherSpace: onScreen[id] == nil) { items[id] = item }
        }
        let allSpaces = windowIdsOnAllSpaces()
        for (id, entry) in known where items[id] == nil && allSpaces.contains(id) {
            if let item = makeItem(id, entry.pid, entry.element, otherSpace: true) { items[id] = item }
            else { known[id] = nil } // closed
        }
        searchOtherSpaces()

        return items.values.sorted { a, b in
            let (ua, ub) = (lastUsed[a.id] ?? 0, lastUsed[b.id] ?? 0)
            if ua != ub { return ua > ub }
            return (onScreen[a.id] ?? Int.max) < (onScreen[b.id] ?? Int.max)
        }
    }

    /// Focus steps from AltTab: front the process with this window, make it key, raise it.
    /// Fronting a window on another Space makes macOS switch to that Space.
    func focus(_ item: WindowItem) {
        markUsed(item.id)
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

    /// Windows the Accessibility API reports: the current Space, plus minimized and hidden ones.
    /// Each one is remembered for when you're on another Space.
    private func currentSpaceWindows() -> [(CGWindowID, pid_t, AXUIElement)] {
        var result: [(CGWindowID, pid_t, AXUIElement)] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for w in windows {
                var id: CGWindowID = 0
                guard _AXUIElementGetWindow(w, &id) == .success, id != 0,
                      attribute(w, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { continue }
                known[id] = (app.processIdentifier, w)
                result.append((id, app.processIdentifier, w))
            }
        }
        return result
    }

    /// Finds windows on Spaces you haven't visited since launch, in the background.
    private func searchOtherSpaces() {
        guard !searching, AXIsProcessTrusted() else { return }
        let regular = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var wanted: [pid_t: Set<CGWindowID>] = [:]
        let allSpaces = windowIdsOnAllSpaces()
        for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = w[kCGWindowNumber as String] as? CGWindowID, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  allSpaces.contains(id), regular.contains(pid), known[id] == nil, !searched.contains(id) else { continue }
            wanted[pid, default: []].insert(id)
        }
        guard !wanted.isEmpty else { return }
        searched.formUnion(wanted.values.joined())
        searching = true
        DispatchQueue.global(qos: .utility).async {
            var found: [(CGWindowID, pid_t, AXUIElement)] = []
            for (pid, ids) in wanted {
                for (id, element) in findWindowsByBruteForce(pid, ids, budget: 0.3) { found.append((id, pid, element)) }
            }
            DispatchQueue.main.async { [weak self] in
                for (id, pid, element) in found { self?.known[id] = (pid, element) }
                self?.searching = false
            }
        }
    }

    private func makeItem(_ id: CGWindowID, _ pid: pid_t, _ element: AXUIElement, otherSpace: Bool) -> WindowItem? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        let minimized = attribute(element, kAXMinimizedAttribute) as? Bool ?? false
        let appName = app.localizedName ?? ""
        return WindowItem(id: id, pid: pid, title: (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName,
                          appName: appName, icon: app.icon, element: element, minimized: minimized,
                          otherSpace: otherSpace && !minimized && !app.isHidden)
    }

    private func markFocusedWindowUsed() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return }
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(window as! AXUIElement, &id) == .success { markUsed(id) }
    }

    private func markUsed(_ id: CGWindowID) {
        clock += 1
        lastUsed[id] = clock
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
