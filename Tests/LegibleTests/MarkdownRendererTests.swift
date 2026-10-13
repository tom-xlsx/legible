import XCTest
@testable import LegibleRender

/// The Quick Look path: the shared core run in JavaScriptCore, with raw HTML off.
final class MarkdownRendererTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let web = root.appendingPathComponent("Resources/web")
    static let themes = root.appendingPathComponent("Resources/themes")

    func kitchenSink() throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("fixtures/kitchen-sink.md"), encoding: .utf8)
    }

    func testRendersTheKitchenSink() throws {
        let renderer = try MarkdownRenderer(web: Self.web, rawHTML: false)
        let html = try renderer.render(try kitchenSink())
        XCTAssertTrue(html.contains("<h1 data-line=\"6\" id=\"kitchen-sink\">"), "h1 id and line offset past the front matter")
        XCTAssertTrue(html.contains("id=\"level-three\""), "first duplicate heading keeps its slug")
        XCTAssertTrue(html.contains("id=\"level-three-1\""), "second duplicate heading gets -1")
        XCTAssertTrue(html.contains("<details class=\"front-matter\">"), "front matter block")
        XCTAssertTrue(html.contains("hljs-keyword"), "syntax highlighting ran")
        XCTAssertTrue(html.contains("data-lang=\"swift\""), "language label")
        XCTAssertTrue(html.contains("class=\"footnotes\""), "footnotes section")
        XCTAssertTrue(html.contains("task-list-item-checkbox") && html.contains("disabled"), "task list checkboxes are disabled")
        XCTAssertTrue(html.contains("<table data-line="), "tables")
        XCTAssertTrue(html.contains("data-lang=\"mermaid\""), "mermaid fence stays a code block")
    }

    func testRawHTMLIsShownAsTextNotMarkup() throws {
        let renderer = try MarkdownRenderer(web: Self.web, rawHTML: false)
        let html = try renderer.render(try kitchenSink())
        for forbidden in ["<script", "<iframe", "<form", "<style", "<meta", "<base", "<object", "<embed", "<svg", "<video", "<audio", "onerror=\"", "href=\"javascript:", "<link"] {
            XCTAssertFalse(html.contains(forbidden), "\(forbidden) survived as markup")
        }
        XCTAssertTrue(html.contains("&lt;script&gt;"), "raw script tag shows as escaped text")
        XCTAssertTrue(html.contains("End of the malicious section."), "closing sentence survives")
        // Fenced HTML code is still shown as code.
        XCTAssertTrue(html.contains("this is text, not a script") && !html.contains("<script>alert"), "html code block shows its source as text")
    }

    func testRawHTMLOnKeepsMarkupForTheApp() throws {
        let renderer = try MarkdownRenderer(web: Self.web, rawHTML: true)
        let html = try renderer.render("<details><summary>Hi</summary>\n\nbody\n\n</details>")
        XCTAssertTrue(html.contains("<details>"), "the app's path keeps raw HTML for DOMPurify to filter")
    }

    func testEmptyAndPlainInput() throws {
        let renderer = try MarkdownRenderer(web: Self.web, rawHTML: false)
        XCTAssertEqual(try renderer.render(""), "")
        XCTAssertEqual(try renderer.render("Hello *world*"), "<p data-line=\"0\">Hello <em>world</em></p>\n")
    }

    func testVendorScriptListMatchesIndexHTML() throws {
        let index = try String(contentsOf: Self.web.appendingPathComponent("index.html"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"<script src="/(vendor/[^"]+)">"#)
        let inPage = regex.matches(in: index, range: NSRange(index.startIndex..., in: index))
            .map { String(index[Range($0.range(at: 1), in: index)!]) }
            .filter { $0 != "vendor/purify.min.js" }   // DOMPurify needs a DOM; the page only
        XCTAssertEqual(inPage, MarkdownRenderer.vendorScripts, "index.html and MarkdownRenderer load different vendor scripts")
    }

    func testPreviewPageEmbedsBothDefaultThemes() throws {
        let page = try PreviewPage(web: Self.web, themes: Self.themes)
        let html = page.html(body: "<p>x</p>", title: "a<b")
        XCTAssertTrue(html.contains("--bg: #f5f2eb"), "Oat Milk variables")
        XCTAssertTrue(html.contains("@media (prefers-color-scheme: dark) {\n:root {\n  --bg: #2b2926"), "Burnt Toast under the dark media query")
        XCTAssertTrue(html.contains("<title>a&lt;b</title>"))
        XCTAssertFalse(html.contains("<script"), "no scripts in the preview page")
        XCTAssertFalse(html.contains("/* @name"), "theme header comment is not copied")
        XCTAssertTrue(html.contains(".code-block"), "legible.css inlined")
    }
}
