import AppKit

/// The Swift half of the moth: loads the art pack, hands the page everything
/// it needs, forwards app events, and keeps the per-document bookmark.
/// Nothing here has any effect while the garnish is held.
final class MothController {
    /// Documents that already showed a nibble this session (at most once per document per session).
    private static var nibbledPaths: Set<String> = []
    private static var cachedPack: (pack: MothPack, problem: String?)?

    /// Test hooks: force the moth on regardless of settings, fix the seed, speed up time.
    static var forceEnabled = false
    static var seedOverride: UInt32?
    static var timeScale: Double = 1

    weak var document: MarkdownDocument?
    private(set) var perchedLine: Double?
    private let seed: UInt32

    init(document: MarkdownDocument) {
        self.document = document
        seed = MothController.seedOverride ?? UInt32.random(in: 1...UInt32.max)
    }

    var path: String? { document?.fileURL?.path }

    var isEnabled: Bool { Garnish.mascot || MothController.forceEnabled }

    /// The pack in use, loaded once and refreshed when a window reloads.
    static func pack() -> (pack: MothPack, problem: String?) {
        if let cachedPack { return cachedPack }
        let loaded = MothPack.current()
        cachedPack = loaded
        return loaded
    }

    static func reloadPack() { cachedPack = nil }

    /// What the page needs, or nil when the moth is off.
    func configuration(theme: Theme) -> [String: Any] {
        guard isEnabled else { return ["enabled": false] }
        let (pack, _) = MothController.pack()
        let assetURL = pack.directory.appendingPathComponent(pack.manifest["asset"] as? String ?? "")
        let asset = (try? String(contentsOf: assetURL, encoding: .utf8)) ?? ""
        var config: [String: Any] = [
            "enabled": true,
            "manifest": pack.manifest,
            "asset": asset,
            "palette": MothPack.palette(for: theme),
            "variants": Array(MothPack.variants(for: theme)),
            "scale": pack.kind == .spritesheet ? 1 : 1,
            "housetrained": SettingsStore.shared.settings.garnishHousetrained,
            "seed": seed,
            "timeScale": MothController.timeScale,
            "allowNibble": path.map { !MothController.nibbledPaths.contains($0) } ?? false,
        ]
        if let path, let line = MothBookmarks.shared.line(for: path) {
            config["bookmark"] = ["line": line]
        }
        return config
    }

    /// A problem with a user pack, for the notice bar.
    var packProblem: String? { isEnabled ? MothController.pack().problem : nil }

    func handle(message: [String: Any]) {
        guard let event = message["event"] as? String else { return }
        switch event {
        case "perch":
            if let line = message["line"] as? Double, let path {
                perchedLine = line
                MothBookmarks.shared.set(line: line, for: path)
            }
        case "nibble":
            if let path { MothController.nibbledPaths.insert(path) }
        default:
            break
        }
    }

    /// On close: keep the moth's place, or failing that where the reading was.
    func flush(readingLine: Double) {
        guard isEnabled, let path else { return }
        MothBookmarks.shared.set(line: perchedLine ?? readingLine, for: path)
        MothBookmarks.shared.save()
    }
}
