import AppKit

/// Remembers which documents were open (and where they were scrolled to) at
/// quit, and reopens them at the next launch. AppKit's own window restoration
/// only runs when the system's "Close windows when quitting" setting is off,
/// so Legible keeps its own record.
enum Session {
    private static let key = "session"
    static var restoreEnabled: Bool { SettingsStore.shared.settings.restoreWindows }

    struct Entry: Codable {
        let path: String
        let line: Double
    }

    static func record() {
        let entries = NSDocumentController.shared.documents.compactMap { document -> Entry? in
            guard let doc = document as? MarkdownDocument, let url = doc.fileURL else { return nil }
            return Entry(path: url.path, line: doc.viewController?.lastTopLine ?? 0)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func stored() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    /// Reopens the recorded documents. Returns true if any existed to reopen.
    @discardableResult
    static func restore() -> Bool {
        guard restoreEnabled else { return false }
        let entries = stored().filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !entries.isEmpty else { return false }
        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                guard entry.line > 0, let controller = (document as? MarkdownDocument)?.viewController else { return }
                let scroll = { controller.preview.scroll(toLine: entry.line) }
                if controller.hasRendered { scroll() } else { controller.onRendered = { _ in scroll() } }
            }
        }
        return true
    }
}
