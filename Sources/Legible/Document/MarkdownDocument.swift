import AppKit

final class MarkdownDocument: NSDocument {
    private(set) var text = ""
    weak var viewController: DocumentViewController?
    private var watcher: FileWatcher?

    override var fileURL: URL? {
        didSet { watchFile() }
    }

    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        text = Self.decode(data)
        viewController?.documentTextDidChangeExternally()
    }

    /// Text edited in the editor pane. Change tracking comes from the undo manager the text view shares.
    func updateText(_ newText: String) {
        text = newText
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            self?.watcher?.acknowledgeOwnWrite()
            completionHandler(error)
        }
    }

    // MARK: Live reload

    private func watchFile() {
        watcher = nil
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in self?.fileChangedOnDisk() }
    }

    private func fileChangedOnDisk() {
        guard let url = fileURL, SettingsStore.shared.settings.liveReload else { return }
        if isDocumentEdited {
            viewController?.showDiskChangeNotice { [weak self] in self?.reloadFromDisk(url) }
        } else {
            reloadFromDisk(url)
        }
    }

    /// Re-reads the file, keeping the preview's scroll position. Discards unsaved edits.
    func reloadFromDisk(_ url: URL? = nil) {
        guard let url = url ?? fileURL else { return }
        do {
            try revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
        } catch {
            NSLog("Legible: reload failed: %@", error.localizedDescription)
        }
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    var directoryURL: URL? { fileURL?.deletingLastPathComponent() }

    /// Prefer UTF-8; fall back to Latin-1 so nothing is ever unreadable.
    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }
}
