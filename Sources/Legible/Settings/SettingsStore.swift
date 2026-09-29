import AppKit
import Observation

/// The single source of truth for settings. The window and the file both go
/// through here: UI changes are patched into settings.toml line by line, and
/// edits to the file are picked up and applied immediately. A file that does
/// not parse keeps the last good settings and reports which line is wrong.
@Observable
final class SettingsStore {
    static let shared = SettingsStore(fileURL: AppInfo.supportDirectory.appendingPathComponent("settings.toml"))
    static let didChange = Notification.Name("LegibleSettingsDidChange")

    let fileURL: URL
    var settings = Settings() {
        didSet {
            guard !isLoading, settings != oldValue else { return }
            persist()
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    /// Human-readable problem with the file, e.g. "settings.toml line 12: arrays are not supported".
    private(set) var fileError: String?
    private(set) var warnings: [String] = []

    @ObservationIgnored private var document: TOMLDocument?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var isLoading = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start() {
        ensureFileExists()
        loadFromDisk()
        watcher = FileWatcher(url: fileURL) { [weak self] in self?.loadFromDisk() }
    }

    // MARK: Disk

    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Settings.defaultFileText().write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Legible: cannot create settings file: %@", error.localizedDescription)
        }
    }

    func loadFromDisk() {
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // No file: defaults apply, nothing to report.
            document = nil
            setLoaded(Settings(), error: nil, warnings: [])
            return
        }
        do {
            var parsed = try TOMLDocument(text: text)
            if SettingsMigration.migrate(&parsed) {
                write(parsed)
            }
            document = parsed
            let loaded = Settings.load(from: parsed)
            setLoaded(loaded.settings, error: nil, warnings: loaded.warnings)
        } catch let error as TOMLDocument.ParseError {
            setLoaded(settings, error: "\(fileURL.lastPathComponent) line \(error.line): \(error.message). Using the last good settings.", warnings: [])
        } catch {
            setLoaded(settings, error: "\(fileURL.lastPathComponent): \(error.localizedDescription)", warnings: [])
        }
    }

    private func setLoaded(_ new: Settings, error: String?, warnings: [String]) {
        isLoading = true
        let changed = new != settings || error != fileError
        settings = new
        fileError = error
        self.warnings = warnings
        isLoading = false
        if changed { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    /// Patches the changed keys into the file. While the file is broken, changes
    /// stay in memory rather than overwriting what the person is fixing.
    private func persist() {
        guard fileError == nil else { return }
        var doc: TOMLDocument
        if let document {
            doc = document
        } else {
            doc = (try? TOMLDocument(text: Settings.defaultFileText())) ?? (try! TOMLDocument(text: ""))
        }
        settings.apply(to: &doc)
        if doc != document {
            document = doc
            write(doc)
        }
    }

    private func write(_ doc: TOMLDocument) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try doc.text.write(to: fileURL, atomically: true, encoding: .utf8)
            watcher?.acknowledgeOwnWrite()
        } catch {
            NSLog("Legible: cannot write settings: %@", error.localizedDescription)
        }
    }

    // MARK: Actions

    func resetToDefaults() {
        do {
            try Settings.defaultFileText().write(to: fileURL, atomically: true, encoding: .utf8)
            watcher?.acknowledgeOwnWrite()
        } catch {
            NSLog("Legible: cannot reset settings: %@", error.localizedDescription)
        }
        loadFromDisk()
    }

    func revealFile() {
        ensureFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
