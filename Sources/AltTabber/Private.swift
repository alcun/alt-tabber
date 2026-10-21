import ApplicationServices

// Private WindowServer and Accessibility calls. Since macOS 14 the public activate() is
// only a request, so focusing another app's window needs these, and so does finding
// windows on other Spaces.
//
// The declarations, the make-key-window event layout and the brute-force window search
// are adapted from AltTab, Copyright (C) lwouis and contributors, licensed GPL-3.0:
// https://github.com/lwouis/alt-tab-macos. AltTab ported parts of them from yabai and
// Hammerspoon.

@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("GetProcessForPID") @discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

/// Marks the front-switch as user-initiated so macOS doesn't suppress it.
let userGeneratedMode: UInt32 = 0x200

/// Makes `wid` its app's key window with a synthetic mouse-down aimed far off the window,
/// so nothing inside it gets clicked. Byte layout from AltTab's makeKeyWindow.
func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
    var wid = wid
    var point = CGPoint(x: 300_000, y: 300_000)
    var bytes = [UInt8](repeating: 0, count: 0x100)
    bytes[0x04] = 0xf8 // record length
    bytes[0x08] = 0x01 // left mouse down
    bytes[0x3a] = 0x10
    memcpy(&bytes[0x3c], &wid, MemoryLayout<CGWindowID>.size)
    memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
    SLPSPostEventRecordTo(&psn, &bytes)
}

// MARK: - Windows on other Spaces

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int,
                                      _ setTags: UnsafeMutablePointer<Int>, _ clearTags: UnsafeMutablePointer<Int>) -> CFArray

@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Every window id on every Space, fullscreen Spaces included.
func windowIdsOnAllSpaces() -> Set<CGWindowID> {
    let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
    let spaces = displays.flatMap { ($0["Spaces"] as? [[String: Any]] ?? []).compactMap { $0["id64"] as? UInt64 } }
    var setTags = 0, clearTags = 0
    let ids = CGSCopyWindowsWithOptionsAndTags(CGSMainConnectionID(), 0, spaces as CFArray, 1 << 1, &setTags, &clearTags) as? [CGWindowID] ?? []
    return Set(ids)
}

/// The Accessibility API only lists an app's windows on the current Space. To reach the
/// others, build an element for each internal element id in turn and keep the ones that
/// are the windows we want. Slow (one call per id), so run it off the main thread.
func findWindowsByBruteForce(_ pid: pid_t, _ wanted: Set<CGWindowID>, budget: CFTimeInterval) -> [CGWindowID: AXUIElement] {
    // 20-byte token: pid (4) + 0 (4) + "coco" (4) + element id (8)
    guard let token = CFDataCreateMutable(nil, 20) else { return [:] }
    CFDataSetLength(token, 20)
    guard let bytes = CFDataGetMutableBytePtr(token) else { return [:] }
    memset(bytes, 0, 20)
    var pidField = pid
    memcpy(bytes, &pidField, 4)
    var magic = Int32(0x636f636f)
    memcpy(bytes + 8, &magic, 4)

    var found: [CGWindowID: AXUIElement] = [:]
    let deadline = CFAbsoluteTimeGetCurrent() + budget
    var elementId: UInt64 = 0
    while found.count < wanted.count && CFAbsoluteTimeGetCurrent() < deadline {
        memcpy(bytes + 12, &elementId, 8)
        elementId += 1
        guard let element = _AXUIElementCreateWithRemoteToken(token)?.takeRetainedValue() else { continue }
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &wid) == .success, wanted.contains(wid), found[wid] == nil else { continue }
        // Children of a window report its id too, so check this is the window itself.
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXStandardWindowSubrole { found[wid] = element }
    }
    return found
}
