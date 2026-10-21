import AppKit

/// Watches the keyboard with an event tap: Option-Tab opens the switcher, and while it is
/// open every key is swallowed and routed here. Releasing Option commits.
final class Hotkey {
    enum Action { case start(backwards: Bool), move(Int), type(String), backspace, commit, cancel }

    var onAction: (Action) -> Void = { _ in }
    private var tap: CFMachPort?
    private var active = false

    private static let tab: Int64 = 48, escape: Int64 = 53, enter: Int64 = 36, delete: Int64 = 51
    private static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126

    /// Fails until the app has Accessibility permission.
    func install() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
            let me = Unmanaged<Hotkey>.fromOpaque(info!).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .flagsChanged:
            if active && !event.flags.contains(.maskAlternate) { finish(.commit) }
            return pass
        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let shift = event.flags.contains(.maskShift)
            if !active {
                guard key == Self.tab, event.flags.contains(.maskAlternate),
                      !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl) else { return pass }
                active = true
                onAction(.start(backwards: shift))
                return nil
            }
            switch key {
            case Self.tab: onAction(.move(shift ? -1 : 1))
            case Self.down, Self.right: onAction(.move(1))
            case Self.up, Self.left: onAction(.move(-1))
            case Self.escape: finish(.cancel)
            case Self.enter: finish(.commit)
            case Self.delete: onAction(.backspace)
            default:
                // Option changes letters (a becomes å), so read the key without modifiers.
                if let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !chars.isEmpty,
                   chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.whitespaces).contains($0) }) {
                    onAction(.type(chars.lowercased()))
                }
            }
            return nil
        case .keyUp:
            return active ? nil : pass
        default:
            return pass
        }
    }

    private func finish(_ action: Action) {
        active = false
        onAction(action)
    }
}
