import AppKit

/// Loads bundled (and later user) themes and decides which one is in effect.
final class ThemeManager: NSObject {
    static let shared = ThemeManager()
    static let didChange = Notification.Name("LegibleThemeDidChange")

    private(set) var themes: [Theme] = []

    /// Explicitly chosen theme id; nil means follow the system appearance.
    var selectedID: String? {
        didSet { if selectedID != oldValue { notify() } }
    }
    var lightDefault = "oat-milk" { didSet { notify() } }
    var darkDefault = "burnt-toast" { didSet { notify() } }

    private var appearanceObservation: NSKeyValueObservation?

    func start() {
        reload()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.notify()
        }
    }

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var effective: Theme {
        if let selectedID, let theme = theme(selectedID) { return theme }
        return theme(isDarkAppearance ? darkDefault : lightDefault) ?? themes.first ?? .fallback
    }

    func theme(_ id: String) -> Theme? {
        themes.first { $0.id == id }
    }

    func reload() {
        themes = load(from: AppInfo.bundledThemesRoot, bundled: true)
            .sorted { ($0.appearance.rawValue, $0.name) < ($1.appearance.rawValue, $1.name) }
        notify()
    }

    private func load(from directory: URL, bundled: Bool) -> [Theme] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "css" && !$0.lastPathComponent.hasPrefix("_") }
            .compactMap { url in
                do { return try Theme.load(from: url, bundled: bundled) } catch {
                    NSLog("Legible: cannot load theme %@: %@", url.path, error.localizedDescription)
                    return nil
                }
            }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: Menu actions

    @objc func selectTheme(_ sender: NSMenuItem) {
        selectedID = sender.representedObject as? String
    }

    @objc func followSystem(_ sender: Any?) {
        selectedID = nil
    }

    @objc func cycleTheme(_ sender: Any?) {
        guard !themes.isEmpty else { return }
        let current = effective.id
        let index = themes.firstIndex { $0.id == current } ?? -1
        selectedID = themes[(index + 1) % themes.count].id
    }
}

extension ThemeManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let system = NSMenuItem(title: "Follow System", action: #selector(followSystem(_:)), keyEquivalent: "")
        system.target = self
        system.state = selectedID == nil ? .on : .off
        menu.addItem(system)

        for appearance in [Theme.Appearance.light, .dark] {
            let group = themes.filter { $0.appearance == appearance }
            guard !group.isEmpty else { continue }
            menu.addItem(.separator())
            for theme in group {
                let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = theme.id
                item.state = selectedID == theme.id ? .on : .off
                item.toolTip = theme.description
                menu.addItem(item)
            }
        }
    }
}
