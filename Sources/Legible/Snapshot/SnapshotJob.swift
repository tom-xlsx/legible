import AppKit
import WebKit

/// Command-line flags. Only `--key=value` forms, so AppKit never mistakes them for files.
struct LaunchOptions {
    var snapshotInput: String?
    var output: String?
    var theme: String?
    var size: (width: Int, height: Int)?
    var scroll: Int?

    var isHeadless: Bool { snapshotInput != nil }

    init(arguments: [String]) {
        for argument in arguments {
            guard argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") else { continue }
            let key = argument[argument.index(argument.startIndex, offsetBy: 2)..<eq]
            let value = String(argument[argument.index(after: eq)...])
            switch key {
            case "snapshot": snapshotInput = value
            case "out": output = value
            case "theme": theme = value
            case "scroll": scroll = Int(value)
            case "size":
                let parts = value.split(separator: "x").compactMap { Int($0) }
                if parts.count == 2 { size = (parts[0], parts[1]) }
            default: break
            }
        }
    }
}

/// `Legible --snapshot=in.md --out=out.png [--theme=id] [--size=WxH] [--scroll=Y]`
/// Renders a document, writes a PNG of the viewport, and exits non-zero if the
/// page reported any JavaScript error. Used by `make check` and for eyeballing themes.
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
                if let y = options.scroll { controller.preview.scroll(toY: y) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.capture(controller.preview.webView) }
            }
            if controller.hasRendered { proceed() } else { controller.onRendered = { _ in proceed() } }
        }
    }

    private func capture(_ webView: WKWebView) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { [self] image, error in
            guard let image, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fail("snapshot failed: \(error?.localizedDescription ?? "no image")")
            }
            do { try png.write(to: output) } catch { fail("cannot write \(output.path): \(error.localizedDescription)") }
            print("Wrote \(output.path) (\(Int(image.size.width))×\(Int(image.size.height)))")
            if errors.isEmpty { exit(0) }
            for message in errors { FileHandle.standardError.write(Data("JS error: \(message)\n".utf8)) }
            exit(1)
        }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("legible --snapshot: \(message)\n".utf8))
        exit(1)
    }
}
