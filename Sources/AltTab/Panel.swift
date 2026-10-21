import AppKit

/// The switcher list: a floating HUD of rows (app icon, window title, app name),
/// centred on the screen with the mouse.
final class Panel {
    var onHover: (Int) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }
    var onAction: (Int, WindowAction) -> Void = { _, _ in }

    private let window: NSPanel
    /// Where the mouse was when the panel opened, so a resting pointer doesn't pick a row.
    private var mouseAtOpen = NSPoint.zero
    /// The row under the mouse, which shows the window buttons.
    private var hovered: Int?
    private let content = NSVisualEffectView()

    private let width: CGFloat = 560, rowHeight: CGFloat = 46, padding: CGFloat = 8, searchHeight: CGFloat = 34
    private let arrowHeight: CGFloat = 12
    /// First visible row. Only moves when the selection would leave the view.
    private var scrollStart = 0

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.acceptsMouseMovedEvents = true
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        window.contentView = content
    }

    func show(_ items: [WindowItem], selected: Int, query: String) {
        content.subviews.forEach { $0.removeFromSuperview() }
        let opening = !window.isVisible
        if opening {
            mouseAtOpen = NSEvent.mouseLocation
            hovered = nil
            scrollStart = 0
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let showSearch = !query.isEmpty

        // As many rows as fit in most of the screen.
        let room = area.height * 0.85 - padding * 2 - searchHeight - arrowHeight * 2
        let visible = min(items.count, max(3, Int(room / rowHeight)))
        if selected < scrollStart { scrollStart = selected }
        if selected >= scrollStart + visible { scrollStart = selected - visible + 1 }
        scrollStart = max(0, min(scrollStart, items.count - visible))
        let start = scrollStart
        let moreAbove = start > 0, moreBelow = start + visible < items.count
        let height = padding * 2 + CGFloat(max(visible, 1)) * rowHeight + (showSearch ? searchHeight : 0)
            + (moreAbove ? arrowHeight : 0) + (moreBelow ? arrowHeight : 0)

        var y = height - padding
        if moreAbove {
            y -= arrowHeight
            content.addSubview(arrow("chevron.up", y: y + 1))
        }
        if showSearch {
            y -= searchHeight
            let search = label("Search: \(query)    ↩ to switch", size: 14, weight: .semibold, color: .secondaryLabelColor)
            search.frame = NSRect(x: padding + 12, y: y + 8, width: width - padding * 2 - 24, height: 20)
            content.addSubview(search)
        }
        if items.isEmpty {
            let none = label(showSearch ? "No matching windows" : "No windows", size: 14, weight: .regular, color: .secondaryLabelColor)
            none.alignment = .center
            none.frame = NSRect(x: padding, y: y - rowHeight + 13, width: width - padding * 2, height: 20)
            content.addSubview(none)
        }
        for i in start..<start + visible {
            y -= rowHeight
            let row = row(items[i], selected: i == selected, buttons: i == hovered,
                          frame: NSRect(x: padding, y: y, width: width - padding * 2, height: rowHeight))
            row.onHover = { [weak self] in
                guard let self, NSEvent.mouseLocation != self.mouseAtOpen, self.hovered != i else { return }
                self.hovered = i
                self.onHover(i)
            }
            row.onClick = { [weak self] in self?.onClick(i) }
            row.onAction = { [weak self] action in self?.onAction(i, action) }
            content.addSubview(row)
        }
        if moreBelow { content.addSubview(arrow("chevron.down", y: y - arrowHeight - 1)) }

        window.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }

    private func row(_ item: WindowItem, selected: Bool, buttons: Bool, frame: NSRect) -> RowView {
        let row = RowView(frame: frame)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        if selected { row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor }

        let icon = NSImageView(frame: NSRect(x: 8, y: 7, width: 32, height: 32))
        icon.image = item.icon
        row.addSubview(icon)

        let textColor: NSColor = selected ? .white : .labelColor
        // Leave room for the buttons when they show.
        let textWidth = frame.width - 62 - (buttons ? 4 * 24 : 0)
        let title = label(item.title, size: 13, weight: .medium, color: textColor)
        title.frame = NSRect(x: 50, y: 22, width: textWidth, height: 18)
        row.addSubview(title)

        var detail = item.appName
        if item.minimized { detail += " · minimized" }
        if item.otherSpace { detail += " · other Space" }
        let app = label(detail, size: 11, weight: .regular, color: selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor)
        app.frame = NSRect(x: 50, y: 6, width: textWidth, height: 15)
        row.addSubview(app)

        if buttons {
            let actions: [(WindowAction, String, String)] = [
                (.minimize, "minus", item.minimized ? "Restore" : "Minimize"),
                (.fullscreen, "arrow.up.left.and.arrow.down.right", "Full Screen"),
                (.close, "xmark", "Close Window"),
                (.quit, "power", "Quit \(item.appName)"),
            ]
            var x = frame.width - 8 - CGFloat(actions.count) * 24
            for (action, symbol, help) in actions {
                let button = ActionButton(frame: NSRect(x: x, y: 12, width: 22, height: 22))
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
                    .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
                button.toolTip = help
                button.contentTintColor = selected ? .white : .secondaryLabelColor
                button.onPress = { [weak row] in row?.onAction(action) }
                row.addSubview(button)
                x += 24
            }
        }
        return row
    }

    /// A small chevron showing there are more windows out of view.
    private func arrow(_ symbol: String, y: CGFloat) -> NSImageView {
        let view = NSImageView(frame: NSRect(x: width / 2 - 10, y: y, width: 20, height: 12))
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "More windows")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        view.contentTintColor = .secondaryLabelColor
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// A clickable row that reports hovering.
private final class RowView: NSView {
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    var onAction: (WindowAction) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    // Take clicks for the whole row, not the labels inside it, except the buttons.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return super.hitTest(point) as? ActionButton ?? self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) { onClick() }
}

/// A small round icon button that lights up under the mouse.
private final class ActionButton: NSButton {
    var onPress: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        target = self
        action = #selector(press)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
    @objc private func press() { onPress() }
}
