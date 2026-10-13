import Foundation

/// A self-contained HTML document in Legible's reading style: legible.css inline,
/// the default light theme, and the default dark theme under prefers-color-scheme.
/// No scripts, no external resources, so Quick Look can show it as-is.
public struct PreviewPage {
    public static let lightTheme = "oat-milk"
    public static let darkTheme = "burnt-toast"

    public let css: String

    /// `web` holds legible.css; `themes` holds the bundled theme files.
    public init(web: URL, themes: URL) throws {
        let base = try Self.read(web.appendingPathComponent("legible.css"))
        let light = try Self.rootBlock(of: themes.appendingPathComponent("\(Self.lightTheme).css"))
        let dark = try Self.rootBlock(of: themes.appendingPathComponent("\(Self.darkTheme).css"))
        css = base + "\n" + light + "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}\n"
            + "html, body { margin: 0; background: var(--bg); }\n"
    }

    public func html(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(Self.escape(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <main class="doc">
        \(body)
        </main>
        </body>
        </html>
        """
    }

    /// The `:root { … }` block of a theme file, without its header comment.
    static func rootBlock(of url: URL) throws -> String {
        let text = try read(url)
        guard let start = text.range(of: ":root"), let end = text.range(of: "}", range: start.upperBound..<text.endIndex) else {
            throw MarkdownRenderer.Error.missingResource("\(url.lastPathComponent) has no :root block")
        }
        return String(text[start.lowerBound..<end.upperBound])
    }

    private static func read(_ url: URL) throws -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw MarkdownRenderer.Error.missingResource(url.lastPathComponent)
        }
        return text
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
