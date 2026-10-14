import Foundation
import JavaScriptCore

/// Renders Markdown to an HTML fragment with the same markdown-it pipeline the app's
/// page uses (Resources/web/legible-core.js), run in JavaScriptCore so no web view is
/// needed. Used by the Quick Look extension and by the app's `--quicklook` check.
public final class MarkdownRenderer {
    public enum Error: Swift.Error, CustomStringConvertible {
        case missingResource(String)
        case javaScript(String)
        public var description: String {
            switch self {
            case .missingResource(let name): return "missing resource \(name)"
            case .javaScript(let message): return "JavaScript: \(message)"
            }
        }
    }

    /// Scripts the core needs, in the order index.html loads them (a test keeps the two in step).
    public static let vendorScripts = [
        "vendor/markdown-it.min.js",
        "vendor/markdown-it-footnote.min.js",
        "vendor/markdown-it-task-lists.min.js",
        "vendor/markdown-it-mark.min.js",
        "vendor/highlight.min.js",
        "vendor/languages/dockerfile.min.js",
        "vendor/languages/nginx.min.js",
        "vendor/languages/http.min.js",
    ]

    private let context: JSContext
    private let renderFunction: JSValue
    private let queue = DispatchQueue(label: "legible.render")

    /// `web` is the folder holding legible-core.js and vendor/.
    /// `rawHTML` false shows raw HTML in the source as text (the Quick Look preview has no sanitiser).
    public init(web: URL, rawHTML: Bool) throws {
        guard let context = JSContext() else { throw Error.javaScript("could not create a JSContext") }
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        for name in Self.vendorScripts + ["legible-core.js"] {
            let url = web.appendingPathComponent(name)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { throw Error.missingResource(name) }
            context.evaluateScript(source, withSourceURL: url)
            if let failure { throw Error.javaScript("\(name): \(failure)") }
        }
        context.evaluateScript("var __legibleRenderer = LegibleCore.create({ html: \(rawHTML) });")
        if let failure { throw Error.javaScript(failure) }
        guard let fn = context.evaluateScript("__legibleRenderer.render"), fn.isObject else {
            throw Error.javaScript("LegibleCore.create returned no render function")
        }
        self.context = context
        self.renderFunction = fn
    }

    /// The HTML fragment for `markdown` (front matter block, headings with ids, highlighted code).
    public func render(_ markdown: String) throws -> String {
        try queue.sync {
            var failure: String?
            context.exceptionHandler = { _, exception in failure = exception?.toString() }
            let result = renderFunction.call(withArguments: [markdown])
            if let failure { throw Error.javaScript(failure) }
            guard let html = result?.forProperty("html")?.toString() else { throw Error.javaScript("render returned nothing") }
            return html
        }
    }
}
