import Foundation

/// Bundle facts and well-known locations.
enum AppInfo {
    static let name = "Legible"

    /// Full version line, e.g. "0.3.0 (142, a1b2c3d)" — written into Info.plist by scripts/build-app.sh.
    static var versionDescription: String {
        Bundle.main.object(forInfoDictionaryKey: "LegibleVersionDescription") as? String ?? "0.0.0 (unbundled)"
    }

    static var resourcesRoot: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    static var webRoot: URL { resourcesRoot.appendingPathComponent("web", isDirectory: true) }
    static var bundledThemesRoot: URL { resourcesRoot.appendingPathComponent("themes", isDirectory: true) }

    /// ~/Library/Application Support/Legible
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(name, isDirectory: true)
    }

    static var userThemesDirectory: URL { supportDirectory.appendingPathComponent("Themes", isDirectory: true) }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]
}
