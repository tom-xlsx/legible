import Foundation

/// Maps each open document to an opaque token and the directory tree its
/// relative links may reach: the enclosing git repository if there is one,
/// otherwise the document's own folder. Nothing outside that root is served.
final class DocumentRegistry {
    static let shared = DocumentRegistry()

    private struct Entry {
        let root: URL             // symlink-resolved
        let relativeDirectory: String  // document dir relative to root, "" at root
    }

    private var entries: [String: Entry] = [:]

    func register(directory: URL?) -> String {
        let token = UUID().uuidString.lowercased()
        guard let directory else { return token }
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let root = Self.projectRoot(for: resolvedDirectory)
        var relative = String(resolvedDirectory.path.dropFirst(root.path.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        entries[token] = Entry(root: root, relativeDirectory: relative)
        return token
    }

    func unregister(_ token: String) {
        entries[token] = nil
    }

    /// The base URL relative links in the document resolve against, e.g. legible-doc://<token>/docs/
    func base(for token: String) -> String? {
        guard let entry = entries[token] else { return nil }
        var url = URL(string: "\(DocumentSchemeHandler.scheme)://\(token)/")!
        if !entry.relativeDirectory.isEmpty {
            url = url.appendingPathComponent(entry.relativeDirectory, isDirectory: true)
        }
        return url.absoluteString
    }

    /// Resolves a request path to a file inside the token's root, or nil.
    func resolve(token: String, path: String) -> URL? {
        guard let entry = entries[token] else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        return SchemeFileServer.contained(entry.root.appendingPathComponent(decoded), within: entry.root)
    }

    private static func projectRoot(for directory: URL) -> URL {
        var current = directory
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path == "/" { return directory }
            current = parent
        }
    }
}
