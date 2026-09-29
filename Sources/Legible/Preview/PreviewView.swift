import AppKit
import WebKit

/// Hosts the WKWebView and the JS bridge. Swift → JS goes through `call`,
/// JS → Swift arrives in `receive`.
final class PreviewView: NSView {
    struct RenderInfo {
        struct Heading { let level: Int; let text: String; let id: String }
        let words: Int
        let headings: [Heading]
        let codeBlocks: Int
    }

    let webView: WKWebView
    var onRendered: ((RenderInfo) -> Void)?
    var onError: ((String) -> Void)?
    /// Fractional source line at the top of the viewport, reported as the user scrolls.
    var onScroll: ((Double) -> Void)?

    /// Navigations the page attempted that were not the page itself (self-test counts these).
    private(set) var blockedNavigations = 0

    private let bridge = Bridge()
    private var isReady = false
    private var queue: [String] = []

    init(token: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: AssetSchemeHandler.scheme)
        config.setURLSchemeHandler(DocumentSchemeHandler(), forURLScheme: DocumentSchemeHandler.scheme)
        config.userContentController.add(bridge, name: "legible")
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)

        bridge.owner = self
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)

        webView.load(URLRequest(url: AssetSchemeHandler.indexURL))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    // MARK: Swift → JS

    func render(markdown: String, docBase: String?, preserveScroll: Bool) {
        let payload: [String: Any] = [
            "markdown": markdown,
            "docBase": docBase ?? "",
            "preserveScroll": preserveScroll,
        ]
        call("Legible.render(\(jsLiteral(payload)))")
    }

    func setTheme(css: String) {
        call("Legible.setTheme(\(jsLiteral(css)))")
    }

    /// CSS applied after the theme (font and measure settings).
    func setOverrides(css: String) {
        call("Legible.setOverrides(\(jsLiteral(css)))")
    }

    func setBackground(_ color: NSColor) {
        webView.underPageBackgroundColor = color
    }

    /// Scrolls to a pixel offset, or to the first element matching a CSS selector.
    func scroll(to target: String) {
        if let y = Int(target) {
            call("window.scrollTo({top: \(y), behavior: 'instant'})")
        } else {
            call("document.querySelector(\(jsLiteral(target)))?.scrollIntoView({block: 'start', behavior: 'instant'})")
        }
    }

    /// Scrolls the preview so the given (fractional, zero-based) source line is at the top.
    func scroll(toLine line: Double) {
        call("Legible.scrollToLine(\(line))")
    }

    var zoom: CGFloat {
        get { webView.pageZoom }
        set { webView.pageZoom = newValue }
    }

    /// Selects the next/previous match and reports "index of total".
    func find(_ query: String, backwards: Bool, completion: @escaping (_ index: Int, _ total: Int) -> Void) {
        guard !query.isEmpty else { completion(0, 0); return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        webView.find(query, configuration: config) { [weak self] _ in
            self?.findStatus(query, completion: completion)
        }
    }

    func findStatus(_ query: String, completion: @escaping (_ index: Int, _ total: Int) -> Void) {
        evaluate("Legible.findStatus(\(jsLiteral(query)))") { result in
            let dict = result as? [String: Any]
            completion(dict?["index"] as? Int ?? 0, dict?["total"] as? Int ?? 0)
        }
    }

    func clearSelection() {
        call("window.getSelection().removeAllRanges()")
    }

    /// Runs `js` once the page is ready and hands back its result.
    func evaluate(_ js: String, completion: @escaping (Any?) -> Void) {
        guard isReady else {
            queue.append(js)   // fire-and-forget while loading; results only matter once ready
            completion(nil)
            return
        }
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error { self?.report("evaluateJavaScript: \(error.localizedDescription)") }
            completion(result)
        }
    }

    private func call(_ js: String) {
        guard isReady else { queue.append(js); return }
        webView.evaluateJavaScript(js) { [weak self] _, error in
            if let error { self?.report("evaluateJavaScript: \(error.localizedDescription)") }
        }
    }

    private func jsLiteral(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else {
            return "null"
        }
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    // MARK: JS → Swift

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let pending = queue
            queue.removeAll()
            pending.forEach(call)
        case "rendered":
            let headings = (message["headings"] as? [[String: Any]] ?? []).compactMap { h -> RenderInfo.Heading? in
                guard let level = h["level"] as? Int, let text = h["text"] as? String, let id = h["id"] as? String else { return nil }
                return RenderInfo.Heading(level: level, text: text, id: id)
            }
            onRendered?(RenderInfo(words: message["words"] as? Int ?? 0,
                                   headings: headings,
                                   codeBlocks: message["codeBlocks"] as? Int ?? 0))
        case "scroll":
            if let line = message["line"] as? Double { onScroll?(line) }
        case "copy":
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message["text"] as? String ?? "", forType: .string)
        case "error":
            report(message["message"] as? String ?? "unknown JS error")
        default:
            break
        }
    }

    private func report(_ text: String) {
        NSLog("Legible preview: %@", text)
        onError?(text)
    }
}

/// Keeps WKUserContentController from retaining the view (it holds handlers strongly).
private final class Bridge: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message.body)
    }
}

extension PreviewView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }

        // The page itself (and its #fragments) is the only thing the web view may navigate to.
        if url.scheme == AssetSchemeHandler.scheme {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard navigationAction.navigationType == .linkActivated else {
            blockedNavigations += 1
            NSLog("Legible: blocked navigation to %@", url.absoluteString)
            return
        }
        LinkOpener.open(url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report("navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report("load failed: \(error.localizedDescription)")
    }
}

/// Where links go: Markdown files open in Legible, other local files in their
/// default app, and everything with a network scheme in the default browser.
enum LinkOpener {
    static func open(_ url: URL) {
        switch url.scheme {
        case DocumentSchemeHandler.scheme:
            guard let file = DocumentRegistry.shared.resolve(token: url.host ?? "", path: url.path) else { return }
            if AppInfo.markdownExtensions.contains(file.pathExtension.lowercased()),
               SettingsStore.shared.settings.openMarkdownLinksInLegible {
                NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            } else {
                NSWorkspace.shared.open(file)
            }
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        default:
            NSLog("Legible: refusing to open %@", url.absoluteString)
        }
    }
}
