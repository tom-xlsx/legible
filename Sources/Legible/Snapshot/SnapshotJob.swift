import AppKit
import WebKit

/// Command-line flags. Only `--key=value` forms, so AppKit never mistakes them for files.
struct LaunchOptions {
    var snapshotInput: String?
    var selfTestInput: String?
    var output: String?
    var theme: String?
    var size: (width: Int, height: Int)?
    var scroll: Int?
    var eval: String?
    var find: String?
    var zoom: Double?
    var captureWindow = false

    var isHeadless: Bool { snapshotInput != nil || selfTestInput != nil }

    init(arguments: [String]) {
        for argument in arguments {
            if argument == "--window" { captureWindow = true; continue }
            guard argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") else { continue }
            let key = argument[argument.index(argument.startIndex, offsetBy: 2)..<eq]
            let value = String(argument[argument.index(after: eq)...])
            switch key {
            case "snapshot": snapshotInput = value
            case "selftest": selfTestInput = value
            case "out": output = value
            case "theme": theme = value
            case "scroll": scroll = Int(value)
            case "eval": eval = value
            case "find": find = value
            case "zoom": zoom = Double(value)
            case "size":
                let parts = value.split(separator: "x").compactMap { Int($0) }
                if parts.count == 2 { size = (parts[0], parts[1]) }
            default: break
            }
        }
    }
}

/// `Legible --snapshot=in.md --out=out.png [--theme=id] [--size=WxH] [--scroll=Y]
///          [--zoom=1.3] [--eval=JS] [--find=query] [--window]`
/// Renders a document, writes a PNG of the viewport (or the whole window with
/// --window, which includes AppKit overlays such as the find bar), and exits
/// non-zero if the page reported any JavaScript error. Used by `make check`
/// and for eyeballing themes and states.
final class SnapshotJob {
    private let input: URL
    private let output: URL
    private let options: LaunchOptions
    private var errors: [String] = []

    init?(options: LaunchOptions) {
        guard let input = options.snapshotInput, let output = options.output else { return nil }
        self.input = URL(fileURLWithPath: input)
        self.output = URL(fileURLWithPath: output)
        self.options = options
    }

    func run() {
        if let themeID = options.theme {
            guard ThemeManager.shared.theme(themeID) != nil else {
                fail("unknown theme '\(themeID)'; available: \(ThemeManager.shared.themes.map(\.id).joined(separator: ", "))")
            }
            ThemeManager.shared.selectedID = themeID
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.fail("timed out waiting for the document to render")
        }

        NSDocumentController.shared.openDocument(withContentsOf: input, display: true) { [self] document, _, error in
            guard let document = document as? MarkdownDocument,
                  let controller = document.viewController,
                  let window = controller.view.window as? DocumentWindow else {
                fail("cannot open \(input.path): \(error?.localizedDescription ?? "unknown error")")
            }
            if let size = options.size {
                window.allowsOversize = true
                window.setContentSize(NSSize(width: size.width, height: size.height))
            }
            controller.preview.onError = { [weak self] message in self?.errors.append(message) }
            let proceed = { [weak self, weak controller] in
                guard let self, let controller else { return }
                if let zoom = options.zoom { Zoom.level = zoom }
                if let y = options.scroll { controller.preview.scroll(toY: y) }
                if let js = options.eval { controller.preview.evaluate(js) { _ in } }
                if let query = options.find {
                    controller.showFind()
                    controller.findBarForTesting.searchField.stringValue = query
                    controller.findNext(backwards: false)
                }
                let overlays: [NSView] = self.options.captureWindow ? [controller.findBarForTesting] : []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.capture(controller.preview.webView, overlays: overlays)
                }
            }
            if controller.hasRendered { proceed() } else { controller.onRendered = { _ in proceed() } }
        }
    }

    private func write(_ png: Data, width: Int, height: Int) -> Never {
        do { try png.write(to: output) } catch { fail("cannot write \(output.path): \(error.localizedDescription)") }
        print("Wrote \(output.path) (\(width)×\(height))")
        if errors.isEmpty { exit(0) }
        for message in errors { FileHandle.standardError.write(Data("JS error: \(message)\n".utf8)) }
        exit(1)
    }

    /// Snapshots the web view and draws any AppKit overlays (e.g. the find bar) on top,
    /// since WKWebView snapshots only contain web content.
    private func capture(_ webView: WKWebView, overlays: [NSView]) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { [self] image, error in
            guard let image else { fail("snapshot failed: \(error?.localizedDescription ?? "no image")") }
            for overlay in overlays where !overlay.isHidden {
                guard let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { continue }
                overlay.cacheDisplay(in: overlay.bounds, to: rep)
                let frame = webView.convert(overlay.frame, from: overlay.superview)
                image.lockFocus()
                NSImage(cgImage: rep.cgImage!, size: overlay.bounds.size).draw(in: frame)
                image.unlockFocus()
            }
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fail("snapshot failed: \(error?.localizedDescription ?? "no image")")
            }
            write(png, width: Int(image.size.width), height: Int(image.size.height))
        }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("legible --snapshot: \(message)\n".utf8))
        exit(1)
    }
}
