import ApplicationServices

// Private WindowServer calls. Since macOS 14 the public activate() is only a request,
// so focusing another app's window needs these. Approach borrowed from AltTab
// (github.com/lwouis/alt-tab-macos, GPL-3.0), which ported it from yabai/Hammerspoon.

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
