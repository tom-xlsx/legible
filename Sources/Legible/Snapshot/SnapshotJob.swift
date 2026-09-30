import AppKit
import WebKit

/// Command-line flags. Only `--key=value` forms, so AppKit never mistakes them for files.
struct LaunchOptions {
    var snapshotInput: String?
    var selfTestInput: String?
    var output: String?
    var theme: String?
    var size: (width: Int, height: Int)?
    var scroll: String?
    var eval: String?
    var find: String?
    var zoom: Double?
    var captureWindow = false
    var showEditor = false
    var showTOC = false
    var save = false
    var saveAs: String?
    var printDocuments = false
    var settingsPane: String?
    var aboutBox = false
    var mothSheet: String?
    var mothValidate: String?
    var pack: String?
    var poses: String?
    var mothState: String?
    var seed: UInt32?
    var mothSelfTestInput: String?
    var dockIcon = false
    var editText: String?
    var delay: Double = 0.8

    var isHeadless: Bool { snapshotInput != nil || selfTestInput != nil || settingsPane != nil || aboutBox || dockIcon || mothSheet != nil || mothValidate != nil || mothSelfTestInput != nil }

    init(arguments: [String]) {
        for argument in arguments {
            if argument == "--window" { captureWindow = true; continue }
            if argument == "--editor" { showEditor = true; continue }
            if argument == "--toc" { showTOC = true; continue }
            if argument == "--save" { save = true; continue }
            if argument == "--print-documents" { printDocuments = true; continue }
            if argument == "--about" { aboutBox = true; continue }
            if argument == "--moth-validate" { mothValidate = ""; continue }
            if argument == "--dock-icon" { dockIcon = true; continue }
            guard argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") else { continue }
            let key = argument[argument.index(argument.startIndex, offsetBy: 2)..<eq]
            let value = String(argument[argument.index(after: eq)...])
            switch key {
            case "snapshot": snapshotInput = value
            case "selftest": selfTestInput = value
            case "out": output = value
            case "theme": theme = value
            case "scroll": scroll = value
            case "eval": eval = value
            case "find": find = value
            case "zoom": zoom = Double(value)
            case "delay": delay = Double(value) ?? delay
            case "edit": editText = value
            case "save-as": saveAs = value
            case "settings-pane": settingsPane = value
            case "moth-sheet": mothSheet = value
            case "moth-validate": mothValidate = value
            case "pack": pack = value
            case "poses": poses = value
            case "moth-state": mothState = value
            case "seed": seed = UInt32(value)
            case "moth-selftest": mothSelfTestInput = value
            case "size":
                let parts = value.split(separator: "x").compactMap { Int($0) }
                if parts.count == 2 { size = (parts[0], parts[1]) }
            default: break
            }
        }
    }
}

/// `Legible --snapshot=in.md --out=out.png [--theme=id] [--size=WxH] [--scroll=Y|selector]
///          [--zoom=1.3] [--eval=JS] [--find=query] [--window] [--delay=seconds] [--editor] [--edit=text] [--save] [--toc] [--moth-state=pose] [--seed=N] [--save-as=path]`
/// `--snapshot=new` starts from an untitled document instead of a file; `--snapshot=clipboard` from the pasteboard text.
/// --editor opens the editor pane; --edit appends text to it (and implies --editor).
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
        if let seed = options.seed { MothController.seedOverride = seed }
        if options.mothState != nil { MothController.forceEnabled = true }
        if let themeID = options.theme {
            guard ThemeManager.shared.theme(themeID) != nil else {
                fail("unknown theme '\(themeID)'; available: \(ThemeManager.shared.themes.map(\.id).joined(separator: ", "))")
            }
            ThemeManager.shared.selectedID = themeID
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.fail("timed out waiting for the document to render")
        }

        let opened: (NSDocument?, Error?) -> Void = { [self] document, error in
            guard let document = document as? MarkdownDocument,
                  let controller = document.viewController,
                  let window = controller.view.window as? DocumentWindow else {
                fail("cannot open \(input.path): \(error?.localizedDescription ?? "unknown error")")
            }
            self.drive(document: document, controller: controller, window: window)
        }
        if input.lastPathComponent == "new" {
            // `--snapshot=new`: an untitled document, as ⌘N makes it.
            do { opened(try NSDocumentController.shared.openUntitledDocumentAndDisplay(true), nil) } catch { opened(nil, error) }
        } else if input.lastPathComponent == "clipboard" {
            // `--snapshot=clipboard`: as File › New from Clipboard makes it.
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            do { opened(try MarkdownDocument.makeUntitled(text: text, opensWithEditor: false), nil) } catch { opened(nil, error) }
        } else {
            NSDocumentController.shared.openDocument(withContentsOf: input, display: true) { document, _, error in opened(document, error) }
        }
    }

    private func drive(document: MarkdownDocument, controller: DocumentViewController, window: DocumentWindow) {
        do {
            if let size = options.size {
                window.allowsOversize = true
                window.setContentSize(NSSize(width: size.width, height: size.height))
            }
            controller.preview.onError = { [weak self] message in self?.errors.append(message) }
            var proceeded = false
            let proceed = { [weak self, weak controller] in
                guard let self, let controller, !proceeded else { return }
                proceeded = true
                controller.onRendered = nil
                if let zoom = options.zoom { Zoom.level = zoom }
                if options.showEditor || options.editText != nil { controller.showEditor() }
                if options.showTOC { controller.showTOC() }
                if let text = options.editText {
                    controller.editor.textView.setSelectedRange(NSRange(location: (controller.editor.text as NSString).length, length: 0))
                    controller.editor.textView.insertText(text, replacementRange: controller.editor.textView.selectedRange())
                }
                if let path = options.saveAs {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        document.save(to: URL(fileURLWithPath: path), ofType: "net.daringfireball.markdown", for: .saveAsOperation) { error in
                            print("save as: \(error.map { "failed: \($0.localizedDescription)" } ?? "ok"); fileURL=\(document.fileURL?.lastPathComponent ?? "nil"); title=\(window.title)")
                        }
                    }
                }
                if options.save {
                    // Let the text view close its undo group first, as happens between keystrokes.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("edited before save: \(document.isDocumentEdited)")
                        document.save(nil)
                        print("edited after save: \(document.isDocumentEdited)")
                    }
                }
                if let scroll = options.scroll {
                    // Wait out the render's own scroll and the sync feedback guard first, as a person would.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.preview.scroll(to: scroll) }
                }
                if let pose = options.mothState {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {   // after any --scroll
                        controller.preview.evaluate("LegibleMoth.debug.place(); LegibleMoth.debug.force(\(jsString(pose)))") { _ in }
                    }
                }
                if let js = options.eval { controller.preview.evaluate(js) { _ in } }
                if let query = options.find {
                    controller.showFind()
                    controller.findBarForTesting.searchField.stringValue = query
                    controller.findNext(backwards: false)
                }
                let overlays: [NSView] = self.options.captureWindow ? [controller.tocViewForTesting, controller.editor, controller.findBarForTesting, controller.noticeBarForTesting] : []
                DispatchQueue.main.asyncAfter(deadline: .now() + self.options.delay) {
                    controller.preview.evaluate("JSON.stringify(window.LegibleMoth ? LegibleMoth.status() : null)") { status in
                        print("moth: \(status as? String ?? "none")")
                    }
                    controller.preview.evaluate("Legible.topLine()") { line in
                        let editorLine = controller.isEditorVisible ? ", editor top line \(controller.editor.topLine)" : ""
                        print("preview top line \(line ?? "?")\(editorLine); notice: \(controller.noticeBarForTesting.isHidden ? "hidden" : controller.noticeBarForTesting.message); subtitle: \"\(window.subtitle)\"; current heading: \(controller.toc.currentID ?? "none")")
                        let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu
                        viewMenu?.delegate?.menuNeedsUpdate?(viewMenu!)
                        print("garnish: held=\(Garnish.held) last view item=\"\(viewMenu?.items.last?.title ?? "")\" dock icon custom=\(NSApp.applicationIconImage != nil && Garnish.dockIcon)")
                        print("panes: toc hidden=\(controller.tocViewForTesting.isHidden) \(controller.tocViewForTesting.frame); editor hidden=\(controller.editor.isHidden) \(controller.editor.frame); preview \(controller.preview.frame)")
                        self.capture(controller.preview.webView, in: controller.view, overlays: overlays)
                    }
                }
            }
            if controller.hasRendered { proceed() } else { controller.onRendered = { _ in proceed() } }
        }
    }

    private func write(_ png: Data, width: Int, height: Int) -> Never {
        MothBookmarks.shared.save()
        do { try png.write(to: output) } catch { fail("cannot write \(output.path): \(error.localizedDescription)") }
        print("Wrote \(output.path) (\(width)×\(height))")
        if errors.isEmpty { exit(0) }
        for message in errors { FileHandle.standardError.write(Data("JS error: \(message)\n".utf8)) }
        exit(1)
    }

    /// Snapshots the web view; with overlays, composes the whole content view
    /// (web content plus AppKit views such as the editor and find bar), since
    /// WKWebView snapshots only contain web content.
    private func capture(_ webView: WKWebView, in container: NSView, overlays: [NSView]) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { [self] webImage, error in
            guard let webImage else { fail("snapshot failed: \(error?.localizedDescription ?? "no image")") }
            var image = webImage
            if !overlays.isEmpty {
                image = NSImage(size: container.bounds.size)
                image.lockFocus()
                webImage.draw(in: container.convert(webView.bounds, from: webView))
                for overlay in overlays where !overlay.isHidden {
                    guard let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { continue }
                    overlay.cacheDisplay(in: overlay.bounds, to: rep)
                    NSImage(cgImage: rep.cgImage!, size: overlay.bounds.size)
                        .draw(in: container.convert(overlay.bounds, from: overlay))
                }
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


/// `Legible --settings-pane=general --out=out.png` renders one Settings pane to a PNG.
final class SettingsSnapshotJob {
    private let pane: String
    private let output: URL

    init?(options: LaunchOptions) {
        guard let pane = options.settingsPane, let output = options.output else { return nil }
        self.pane = pane
        self.output = URL(fileURLWithPath: output)
    }

    func run() {
        let controller = SettingsWindowController.shared
        controller.show()
        guard let window = controller.window, let tabs = window.contentViewController as? NSTabViewController else { exit(1) }
        guard let index = tabs.tabViewItems.firstIndex(where: { $0.label.lowercased() == pane.lowercased() }) else {
            FileHandle.standardError.write(Data("unknown pane '\(pane)'; use \(tabs.tabViewItems.map(\.label).joined(separator: ", "))\n".utf8))
            exit(1)
        }
        tabs.selectedTabViewItemIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: output) } catch { exit(1) }
            print("Wrote \(output.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
            exit(0)
        }
    }
}


/// `Legible --about --out=x.png` captures the About panel; `--dock-icon --theme=id --out=x.png` writes the themed Dock icon.
final class GarnishSnapshotJob {
    private let options: LaunchOptions
    private let output: URL

    init?(options: LaunchOptions) {
        guard options.aboutBox || options.dockIcon, let output = options.output else { return nil }
        self.options = options
        self.output = URL(fileURLWithPath: output)
    }

    func run() {
        if options.dockIcon {
            let theme = options.theme.flatMap { ThemeManager.shared.theme($0) } ?? ThemeManager.shared.effective
            guard let image = DockIcon.image(for: theme) else { FileHandle.standardError.write(Data("no icon\n".utf8)); exit(1) }
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
            print("Wrote \(output.path) (dock icon, \(theme.id))")
            exit(0)
        }
        (NSApp.delegate as? AppDelegate)?.showAbout(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            guard let panel = NSApp.windows.first(where: { $0.isVisible && !($0 is DocumentWindow) && $0 !== SettingsWindowController.shared.window }),
                  let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                FileHandle.standardError.write(Data("about panel not found among: \(NSApp.windows.map { "\($0.className) visible=\($0.isVisible)" })\n".utf8))
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
            print("Wrote \(output.path) (about)")
            exit(0)
        }
    }
}


private func jsString(_ s: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
    return String(decoding: data, as: UTF8.self)
}
