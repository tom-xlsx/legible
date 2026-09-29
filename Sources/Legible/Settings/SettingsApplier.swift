import AppKit

/// Pushes settings into the parts of the app that hold live state (theme
/// selection, zoom) and records changes made through menus and shortcuts back
/// into the settings file. Equal values are ignored, so nothing ping-pongs.
final class SettingsApplier {
    static let shared = SettingsApplier()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        })
        observers.append(center.addObserver(forName: ThemeManager.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.recordTheme()
        })
        observers.append(center.addObserver(forName: Zoom.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.recordZoom()
        })
        applySettings()
    }

    private func applySettings() {
        let s = SettingsStore.shared.settings
        let themes = ThemeManager.shared
        if themes.lightDefault != s.lightTheme { themes.lightDefault = s.lightTheme }
        if themes.darkDefault != s.darkTheme { themes.darkDefault = s.darkTheme }
        let selected: String? = s.theme == "system" ? nil : s.theme
        if themes.selectedID != selected { themes.selectedID = selected }
        Zoom.level = CGFloat(s.zoom)
    }

    private func recordTheme() {
        let themes = ThemeManager.shared
        var s = SettingsStore.shared.settings
        s.theme = themes.selectedID ?? "system"
        s.lightTheme = themes.lightDefault
        s.darkTheme = themes.darkDefault
        if s != SettingsStore.shared.settings { SettingsStore.shared.settings = s }
    }

    private func recordZoom() {
        var s = SettingsStore.shared.settings
        s.zoom = (Double(Zoom.level) * 100).rounded() / 100
        if s != SettingsStore.shared.settings { SettingsStore.shared.settings = s }
    }
}
