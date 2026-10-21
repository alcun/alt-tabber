import AppKit

/// The switcher list: a floating HUD of rows (app icon, window title, app name),
/// centred on the screen with the mouse.
final class Panel {
    private let window: NSPanel
    private let content = NSVisualEffectView()

    private let width: CGFloat = 560, rowHeight: CGFloat = 46, padding: CGFloat = 8, searchHeight: CGFloat = 34
    private let maxRows = 12

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
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
        let visible = min(items.count, maxRows)
        let showSearch = !query.isEmpty
        let height = padding * 2 + CGFloat(max(visible, 1)) * rowHeight + (showSearch ? searchHeight : 0)

        // Scroll so the selection stays in view.
        let start = max(0, min(selected - visible / 2, items.count - visible))
        var y = height - padding
        if showSearch {
            y -= searchHeight
            let search = label("Search: \(query)", size: 14, weight: .semibold, color: .secondaryLabelColor)
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
            content.addSubview(row(items[i], selected: i == selected, frame: NSRect(x: padding, y: y, width: width - padding * 2, height: rowHeight)))
        }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        window.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }

    private func row(_ item: WindowItem, selected: Bool, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        if selected { row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor }

        let icon = NSImageView(frame: NSRect(x: 8, y: 7, width: 32, height: 32))
        icon.image = item.icon
        row.addSubview(icon)

        let textColor: NSColor = selected ? .white : .labelColor
        let title = label(item.title, size: 13, weight: .medium, color: textColor)
        title.frame = NSRect(x: 50, y: 22, width: frame.width - 62, height: 18)
        row.addSubview(title)

        var detail = item.appName
        if item.minimized { detail += " · minimized" }
        let app = label(detail, size: 11, weight: .regular, color: selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor)
        app.frame = NSRect(x: 50, y: 6, width: frame.width - 62, height: 15)
        row.addSubview(app)
        return row
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
