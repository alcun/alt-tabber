import AppKit

/// Ties the hotkey to the window list and the panel.
final class Switcher {
    /// Called when the switcher closes by itself (a mouse click), so the hotkey stops routing keys.
    var onClose: () -> Void = {}

    private let panel = Panel()
    private let windows = Windows()
    private var all: [WindowItem] = []
    private var shown: [WindowItem] = []
    private var selected = 0
    private var query = ""
    private var pendingShow: DispatchWorkItem?

    init() {
        panel.onHover = { [weak self] i in
            guard let self, i != self.selected else { return }
            self.selected = i
            self.render()
        }
        panel.onClick = { [weak self] i in
            self?.selected = i
            self?.handle(.commit)
            self?.onClose()
        }
    }

    func handle(_ action: Hotkey.Action) {
        switch action {
        case .start(let backwards):
            all = windows.list()
            query = ""
            shown = all
            // The first window is the one you're in, so start on the one before it.
            selected = shown.count > 1 ? (backwards ? shown.count - 1 : 1) : 0
            // A quick Option-Tab tap switches without flashing the panel.
            let show = DispatchWorkItem { [weak self] in self?.render() }
            pendingShow = show
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: show)
        case .move(let step):
            guard !shown.isEmpty else { return }
            selected = (selected + step + shown.count) % shown.count
            render()
        case .type(let text):
            query += text
            filter()
        case .backspace:
            guard !query.isEmpty else { return }
            query.removeLast()
            filter()
        case .commit:
            let target = shown.indices.contains(selected) ? shown[selected] : nil
            close()
            if let target { windows.focus(target) }
        case .cancel:
            close()
        }
    }

    /// Search by typing: every word must appear in the window title or app name.
    private func filter() {
        let words = query.split(separator: " ").map(String.init)
        shown = words.isEmpty ? all : all.filter { item in
            let haystack = "\(item.title) \(item.appName)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        selected = 0
        render()
    }

    private func render() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.show(shown, selected: selected, query: query)
    }

    private func close() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.hide()
        all = []
        shown = []
    }
}
