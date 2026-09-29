import AppKit

final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    let preview: PreviewView
    private let findBar = FindBar(frame: .zero)
    private let token: String
    private var observers: [NSObjectProtocol] = []

    /// Set once the first render has completed (used by the snapshot and self-test jobs).
    private(set) var hasRendered = false
    var onRendered: ((PreviewView.RenderInfo) -> Void)?

    init(document: MarkdownDocument) {
        self.document = document
        token = DocumentRegistry.shared.register(directory: document.directoryURL)
        preview = PreviewView(token: token)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        DocumentRegistry.shared.unregister(token)
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 800))
        preview.frame = container.bounds
        preview.autoresizingMask = [.width, .height]
        container.addSubview(preview)

        findBar.isHidden = true
        findBar.frame.origin = NSPoint(x: container.bounds.width - findBar.frame.width - 14,
                                       y: container.bounds.height - findBar.frame.height - 14)
        findBar.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(findBar)
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preview.onRendered = { [weak self] info in
            guard let self else { return }
            hasRendered = true
            onRendered?(info)
        }
        preview.zoom = Zoom.level
        applyTheme()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ThemeManager.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyTheme()
        })
        observers.append(center.addObserver(forName: Zoom.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.preview.zoom = Zoom.level
        })

        findBar.onQueryChange = { [weak self] query in self?.find(query, backwards: false, moveSelection: true) }
        findBar.onNext = { [weak self] in self?.findNext(backwards: false) }
        findBar.onPrevious = { [weak self] in self?.findNext(backwards: true) }
        findBar.onClose = { [weak self] in self?.hideFind() }

        render(preserveScroll: false)
    }

    func applyTheme() {
        let theme = ThemeManager.shared.effective
        preview.setTheme(css: theme.css)
        preview.setBackground(theme.backgroundColor)
        view.window?.backgroundColor = theme.backgroundColor
    }

    func render(preserveScroll: Bool) {
        preview.render(markdown: document.text,
                       docBase: DocumentRegistry.shared.base(for: token),
                       preserveScroll: preserveScroll)
    }

    // MARK: Find

    var hasFindQuery: Bool { !findBar.query.isEmpty }
    var findBarForTesting: FindBar { findBar }

    func showFind() {
        findBar.isHidden = false
        findBar.focus()
    }

    func hideFind() {
        findBar.isHidden = true
        view.window?.makeFirstResponder(preview.webView)
    }

    func findNext(backwards: Bool) {
        if findBar.isHidden { showFind() }
        find(findBar.query, backwards: backwards, moveSelection: true)
    }

    private func find(_ query: String, backwards: Bool, moveSelection: Bool) {
        guard !query.isEmpty else {
            findBar.setCount(index: 0, total: 0, hasQuery: false)
            preview.clearSelection()
            return
        }
        preview.find(query, backwards: backwards) { [weak self] index, total in
            self?.findBar.setCount(index: index, total: total, hasQuery: true)
        }
    }
}
