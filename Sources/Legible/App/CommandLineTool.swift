import Foundation

/// Installs the bundled `legible` script into ~/.local/bin.
enum CommandLineTool {
    static var bundledURL: URL { AppInfo.resourcesRoot.appendingPathComponent("bin/legible") }
    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/legible")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: installURL.path)
    }

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: installURL.path) { try fm.removeItem(at: installURL) }
        try fm.copyItem(at: bundledURL, to: installURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path)
    }
}
