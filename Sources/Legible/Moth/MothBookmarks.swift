import Foundation

/// Where the moth was (and so where the reading left off) per document, kept
/// for the 500 most recently opened files in Application Support.
final class MothBookmarks {
    static let shared = MothBookmarks(fileURL: AppInfo.supportDirectory.appendingPathComponent("moth-bookmarks.json"))
    static let capacity = 500

    struct Entry: Codable, Equatable {
        var path: String
        var line: Double
        var seen: Date
    }

    private struct File: Codable {
        var version: Int
        var entries: [Entry]
    }

    let fileURL: URL
    private(set) var entries: [Entry] = []   // oldest first
    private var saveTimer: Timer?

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func line(for path: String) -> Double? {
        entries.last { $0.path == path }?.line
    }

    func set(line: Double, for path: String) {
        entries.removeAll { $0.path == path }
        entries.append(Entry(path: path, line: line, seen: Date()))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        scheduleSave()
    }

    func remove(path: String) {
        entries.removeAll { $0.path == path }
        scheduleSave()
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(File.self, from: data) {
            entries = file.entries.sorted { $0.seen < $1.seen }
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in self?.save() }
    }

    func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(File(version: 1, entries: entries)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Legible: cannot save moth bookmarks: %@", error.localizedDescription)
        }
    }
}
