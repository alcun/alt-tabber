import AppKit

/// Watches the keyboard with an event tap: Option-Tab opens the switcher, and while it is
/// open every key is swallowed and routed here. Releasing Option commits, unless you've
/// started typing a search: then Enter commits, so you can let go of Option to type.
final class Hotkey {
    enum Action { case start(backwards: Bool), move(Int), type(String), backspace, commit, cancel }

    var onAction: (Action) -> Void = { _ in }
    private var tap: CFMachPort?
    private var active = false
    private var searching = false

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
            if active && !searching && !event.flags.contains(.maskAlternate) { finish(.commit) }
            return pass
        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let shift = event.flags.contains(.maskShift)
            if !active {
                guard key == Self.tab, event.flags.contains(.maskAlternate),
                      !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl) else { return pass }
                active = true
                send(.start(backwards: shift))
                return nil
            }
            switch key {
            case Self.tab: send(.move(shift ? -1 : 1))
            case Self.down, Self.right: send(.move(1))
            case Self.up, Self.left: send(.move(-1))
            case Self.escape: finish(.cancel)
            case Self.enter: finish(.commit)
            case Self.delete: send(.backspace)
            default:
                // Option changes letters (a becomes å), so read the key without modifiers.
                if let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !chars.isEmpty,
                   chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.whitespaces).contains($0) }) {
                    searching = true
                    send(.type(chars.lowercased()))
                }
            }
            return nil
        case .keyUp:
            return active ? nil : pass
        default:
            return pass
        }
    }

    /// Stops routing keys, for when the switcher closed some other way.
    func reset() {
        active = false
        searching = false
    }

    private func finish(_ action: Action) {
        reset()
        send(action)
    }

    /// Every keypress on the Mac waits for this tap, so do the work after it returns.
    private func send(_ action: Action) {
        DispatchQueue.main.async { [weak self] in self?.onAction(action) }
    }
}
