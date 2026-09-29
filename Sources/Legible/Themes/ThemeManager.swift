import AppKit

/// Loads bundled and user themes, watches the user theme folder, and decides
/// which theme is in effect (explicit choice › hover preview › system appearance).
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

    /// Theme shown while the pointer rests on a menu item; cleared when the menu closes.
    private var previewID: String? {
        didSet { if previewID != oldValue { notify() } }
    }

    private var appearanceObservation: NSKeyValueObservation?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadTimer: Timer?

    func start() {
        installUserTemplate()
        reload()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.notify()
        }
    }

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var effective: Theme {
        if let previewID, let theme = theme(previewID) { return theme }
        if let selectedID, let theme = theme(selectedID) { return theme }
        return theme(isDarkAppearance ? darkDefault : lightDefault) ?? themes.first ?? .fallback
    }

    func theme(_ id: String) -> Theme? {
        themes.first { $0.id == id }
    }

    // MARK: Loading

    func reload() {
        var byID: [String: Theme] = [:]
        for theme in load(from: AppInfo.bundledThemesRoot, bundled: true) { byID[theme.id] = theme }
        for theme in load(from: AppInfo.userThemesDirectory, bundled: false) { byID[theme.id] = theme }  // user files override
        themes = byID.values.sorted { ($0.appearance.rawValue, $0.name.lowercased()) < ($1.appearance.rawValue, $1.name.lowercased()) }
        watchUserThemes()
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

    /// Creates ~/Library/Application Support/Legible/Themes/_template.css on first launch.
    private func installUserTemplate() {
        let directory = AppInfo.userThemesDirectory
        let template = directory.appendingPathComponent("_template.css")
        guard !FileManager.default.fileExists(atPath: template.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bundled = AppInfo.bundledThemesRoot.appendingPathComponent("_template.css")
            try FileManager.default.copyItem(at: bundled, to: template)
        } catch {
            NSLog("Legible: cannot install theme template: %@", error.localizedDescription)
        }
    }

    // MARK: Watching

    private func watchUserThemes() {
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        let directory = AppInfo.userThemesDirectory
        var paths = [directory]
        paths += ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "css" }
        for path in paths {
            let fd = open(path.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        reloadTimer?.invalidate()
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.reload()
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

    @objc func revealUserThemes(_ sender: Any?) {
        installUserTemplate()
        NSWorkspace.shared.activateFileViewerSelecting([AppInfo.userThemesDirectory])
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
                item.toolTip = theme.isBundled ? theme.description : "\(theme.description) (user theme)".trimmingCharacters(in: .whitespaces)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Show User Themes Folder", action: #selector(revealUserThemes(_:)), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
    }

    /// Live preview: the document takes on whichever theme the pointer is over.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        previewID = item?.representedObject as? String
    }

    func menuDidClose(_ menu: NSMenu) {
        previewID = nil
    }
}
