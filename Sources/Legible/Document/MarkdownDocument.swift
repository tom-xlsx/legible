import AppKit

final class MarkdownDocument: NSDocument {
    private(set) var text = ""
    weak var viewController: DocumentViewController?

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
