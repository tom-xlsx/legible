import AppKit
import LegibleRender
import WebKit

/// `Legible --quicklook=in.md --out=out.png|out.html [--size=WxH]`
/// Builds the page the Quick Look extension would return and either writes it or
/// renders it in an offscreen web view, so previews can be checked without Quick Look.
final class QuickLookSnapshotJob: NSObject, WKNavigationDelegate {
    private let input: URL
    private let output: URL
    private let size: NSSize
    private var webView: WKWebView?

    init?(options: LaunchOptions) {
        guard let input = options.quickLookInput, let output = options.output else { return nil }
        self.input = URL(fileURLWithPath: input)
        self.output = URL(fileURLWithPath: output)
        self.size = NSSize(width: options.size?.width ?? 900, height: options.size?.height ?? 700)
    }

    func run() {
        do {
            let renderer = try MarkdownRenderer(web: AppInfo.webRoot, rawHTML: false)
            let page = try PreviewPage(web: AppInfo.webRoot, themes: AppInfo.bundledThemesRoot)
            let markdown = try String(contentsOf: input, encoding: .utf8)
            let html = page.html(body: try renderer.render(markdown), title: input.lastPathComponent)
            if output.pathExtension == "html" {
                try html.write(to: output, atomically: true, encoding: .utf8)
                print("Wrote \(output.path) (quick look page)")
                exit(0)
            }
            let webView = WKWebView(frame: NSRect(origin: .zero, size: size))
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: nil)
            self.webView = webView
        } catch {
            FileHandle.standardError.write(Data("quicklook: \(error)\n".utf8))
            exit(1)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write(Data("quicklook: snapshot failed: \(error.map { "\($0)" } ?? "no image")\n".utf8))
                    exit(1)
                }
                try? png.write(to: self.output)
                print("Wrote \(self.output.path) (quick look preview, \(Int(self.size.width))×\(Int(self.size.height)))")
                exit(0)
            }
        }
    }
}
