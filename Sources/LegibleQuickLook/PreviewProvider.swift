import Foundation
import LegibleRender
import QuickLookUI

/// Data-based Quick Look preview: Markdown in, a self-contained HTML page out.
/// Quick Look renders the page itself; this process never shows a view.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    /// One renderer per process; a JSContext is cheap to keep and each preview reuses it.
    private static let renderer: Result<(MarkdownRenderer, PreviewPage), Swift.Error> = {
        Result {
            let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
            let renderer = try MarkdownRenderer(web: resources, rawHTML: false)
            let page = try PreviewPage(web: resources, themes: resources.appendingPathComponent("themes"))
            return (renderer, page)
        }
    }()

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let (renderer, page) = try Self.renderer.get()
        let data = try Data(contentsOf: request.fileURL)
        let markdown = String(decoding: data, as: UTF8.self)
        let html = page.html(body: try renderer.render(markdown), title: request.fileURL.lastPathComponent)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 700)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
        reply.title = request.fileURL.lastPathComponent
        return reply
    }
}
