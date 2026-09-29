import AppKit

final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    let preview: PreviewView
    private let token: String
    private var themeObserver: NSObjectProtocol?

    /// Set once the first render has completed (used by the snapshot job).
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
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    override func loadView() {
        preview.frame = NSRect(x: 0, y: 0, width: 980, height: 800)
        view = preview
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preview.onRendered = { [weak self] info in
            guard let self else { return }
            hasRendered = true
            onRendered?(info)
        }
        applyTheme()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.applyTheme() }
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
}
