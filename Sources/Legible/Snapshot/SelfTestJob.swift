import AppKit

/// `Legible --selftest=fixtures/kitchen-sink.md`
/// Opens the fixture, runs the in-page assertions (sanitising, copy text, ids…),
/// checks what Swift can see (page title untouched, no stray navigations), then
/// clicks the relative Markdown link and confirms a second document opened.
final class SelfTestJob {
    private let input: URL
    private var failures: [String] = []
    private var jsErrors: [String] = []

    init?(options: LaunchOptions) {
        guard let input = options.selfTestInput else { return nil }
        self.input = URL(fileURLWithPath: input)
    }

    func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.finish(fatal: "timed out waiting for the document to render")
        }
        NSDocumentController.shared.openDocument(withContentsOf: input, display: true) { [self] document, _, error in
            guard let document = document as? MarkdownDocument, let controller = document.viewController else {
                finish(fatal: "cannot open \(input.path): \(error?.localizedDescription ?? "unknown error")")
            }
            controller.preview.onError = { [weak self] message in self?.jsErrors.append(message) }
            let proceed = { [weak self, weak controller] in
                guard let self, let controller else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runAssertions(controller) }
            }
            if controller.hasRendered { proceed() } else { controller.onRendered = { _ in proceed() } }
        }
    }

    private func runAssertions(_ controller: DocumentViewController) {
        let preview = controller.preview
        preview.evaluate("Legible.selfTest()") { [self] result in
            failures += (result as? [String]) ?? ["Legible.selfTest() returned nothing"]
            check(preview.webView.title == "Legible", "page title is \"\(preview.webView.title ?? "nil")\", expected \"Legible\"")
            check(preview.blockedNavigations == 0, "page attempted \(preview.blockedNavigations) navigation(s) on its own")
            check(controller.hasRendered, "render never completed")

            // Clicking a relative .md link must open it in Legible.
            preview.evaluate("(() => { const a = [...document.querySelectorAll('a')].find(a => a.getAttribute('href').endsWith('sibling.md')); if (!a) return 'missing'; a.click(); return 'clicked'; })()") { [self] clicked in
                check(clicked as? String == "clicked", "sibling.md link not found in the fixture")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    let names = NSDocumentController.shared.documents.compactMap { $0.fileURL?.lastPathComponent }
                    check(names.contains("sibling.md"), "relative link did not open sibling.md (open: \(names.joined(separator: ", ")))")
                    finish(fatal: nil)
                }
            }
        }
    }

    private func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    private func finish(fatal: String?) -> Never {
        if let fatal { failures.append(fatal) }
        failures += jsErrors.map { "JS error: \($0)" }
        if failures.isEmpty {
            print("selftest: PASS (\(input.lastPathComponent))")
            exit(0)
        }
        for failure in failures { print("selftest: FAIL  \(failure)") }
        print("selftest: \(failures.count) failure(s)")
        exit(1)
    }
}
