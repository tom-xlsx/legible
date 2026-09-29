import AppKit

final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    let preview: PreviewView
    let editor = EditorView(frame: .zero)
    private let splitView = NSSplitView()
    private let findBar = FindBar(frame: .zero)
    private let noticeBar = NoticeBar(frame: .zero)
    private let token: String
    private var observers: [NSObjectProtocol] = []
    private var renderTimer: Timer?
    private var ignoreEditorScrollUntil = Date.distantPast
    private var ignorePreviewScrollUntil = Date.distantPast
    private static let editorWidthKey = "editorWidth"

    /// Set once the first render has completed (used by the snapshot and self-test jobs).
    private(set) var hasRendered = false
    /// Last reported top line of the preview (kept for session restore).
    private(set) var lastTopLine: Double = 0
    var onRendered: ((PreviewView.RenderInfo) -> Void)?
    private var afterNextRender: (() -> Void)?

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

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.frame = container.bounds
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = self
        editor.isHidden = true   // reading mode by default; never restored as visible
        splitView.addArrangedSubview(editor)
        splitView.addArrangedSubview(preview)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow - 1, forSubviewAt: 1)
        container.addSubview(splitView)

        findBar.isHidden = true
        findBar.frame.origin = NSPoint(x: container.bounds.width - findBar.frame.width - 14,
                                       y: container.bounds.height - findBar.frame.height - 14)
        findBar.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(findBar)

        noticeBar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        container.addSubview(noticeBar)
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        noticeBar.frame.origin = NSPoint(x: ((view.bounds.width - noticeBar.frame.width) / 2).rounded(),
                                         y: view.bounds.height - noticeBar.frame.height - 12)
    }

    /// The file changed on disk while there are unsaved edits: let the person decide.
    func showDiskChangeNotice(reload: @escaping () -> Void) {
        noticeBar.show("This file was changed on disk. Your unsaved edits are still here.", actions: [
            .init(title: "Reload", handler: reload),
            .init(title: "Keep Mine", handler: {}),
        ])
        view.needsLayout = true
    }

    var noticeBarForTesting: NoticeBar { noticeBar }

    override func viewDidLoad() {
        super.viewDidLoad()
        preview.onRendered = { [weak self] info in
            guard let self else { return }
            hasRendered = true
            let pending = afterNextRender
            afterNextRender = nil
            pending?()
            onRendered?(info)
        }
        preview.onScroll = { [weak self] line in
            self?.lastTopLine = line
            self?.previewDidScroll(toLine: line)
        }
        preview.zoom = Zoom.level
        editor.textView.delegate = self
        editor.onScroll = { [weak self] line in self?.editorDidScroll(toLine: line) }
        applyTheme()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ThemeManager.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyTheme()
        })
        observers.append(center.addObserver(forName: Zoom.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.preview.zoom = Zoom.level
        })
        observers.append(center.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        })
        applySettings()

        findBar.onQueryChange = { [weak self] query in self?.find(query, backwards: false) }
        findBar.onNext = { [weak self] in self?.findNext(backwards: false) }
        findBar.onPrevious = { [weak self] in self?.findNext(backwards: true) }
        findBar.onClose = { [weak self] in self?.hideFind() }

        render(preserveScroll: false)
    }

    func applyTheme() {
        let theme = ThemeManager.shared.effective
        preview.setTheme(css: theme.css)
        preview.setBackground(theme.backgroundColor)
        editor.apply(theme: theme)
        view.window?.backgroundColor = theme.backgroundColor
    }

    private var showingSettingsError = false

    func applySettings() {
        let store = SettingsStore.shared
        let s = store.settings
        var css = ":root {"
        if !s.fontBody.isEmpty { css += " --font-body: \(cssFontList(s.fontBody));" }
        if !s.fontMono.isEmpty { css += " --font-mono: \(cssFontList(s.fontMono));" }
        if s.fontSize > 0 { css += " --font-size: \(s.fontSize)px;" }
        if s.lineHeight > 0 { css += " --line-height: \(s.lineHeight);" }
        if s.measure > 0 { css += " --measure: \(s.measure)ch;" }
        css += " }"
        preview.setOverrides(css: css)
        editor.apply(settings: s)

        if let error = store.fileError {
            showingSettingsError = true
            noticeBar.show(error, actions: [.init(title: "Reveal File", handler: { store.revealFile() })])
            view.needsLayout = true
        } else if showingSettingsError {
            showingSettingsError = false
            noticeBar.hide()
        }
    }

    private func cssFontList(_ family: String) -> String {
        let quoted = "\"" + family.replacingOccurrences(of: "\"", with: "") + "\""
        return quoted + ", " + (family.lowercased().contains("mono") ? "ui-monospace, monospace" : "system-ui, sans-serif")
    }

    func render(preserveScroll: Bool) {
        preview.render(markdown: document.text,
                       docBase: DocumentRegistry.shared.base(for: token),
                       preserveScroll: preserveScroll)
    }

    /// Called by the document when its text was replaced from disk.
    func documentTextDidChangeExternally() {
        noticeBar.hide()
        if isEditorVisible {
            let line = editor.topLine
            editor.text = document.text
            editor.scroll(toLine: line)
        }
        render(preserveScroll: true)
    }

    // MARK: Editor

    var isEditorVisible: Bool { !editor.isHidden }

    func toggleEditor() {
        if isEditorVisible { hideEditor() } else { showEditor() }
    }

    func showEditor() {
        guard !isEditorVisible else { return }
        editor.text = document.text
        editor.isHidden = false
        let saved = UserDefaults.standard.double(forKey: Self.editorWidthKey)
        let width = saved > 0 ? CGFloat(saved) : splitView.bounds.width / 2
        splitView.setPosition(min(max(width, 240), splitView.bounds.width - 320), ofDividerAt: 0)
        editor.scroll(toLine: 0)
        view.window?.makeFirstResponder(editor.textView)
        view.window?.toolbar?.validateVisibleItems()
    }

    func hideEditor() {
        guard isEditorVisible else { return }
        UserDefaults.standard.set(Double(editor.frame.width), forKey: Self.editorWidthKey)
        editor.isHidden = true
        view.window?.makeFirstResponder(preview.webView)
        view.window?.toolbar?.validateVisibleItems()
    }

    private func scheduleRender() {
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            guard let self else { return }
            // After an edit the editor leads: once the new content is in, line the preview up with it.
            afterNextRender = { [weak self] in
                guard let self, isEditorVisible, SettingsStore.shared.settings.scrollSync else { return }
                ignorePreviewScrollUntil = Date().addingTimeInterval(0.25)
                preview.scroll(toLine: editor.topLine)
            }
            render(preserveScroll: true)
        }
    }

    // MARK: Scroll sync

    private func editorDidScroll(toLine line: Double) {
        guard isEditorVisible, SettingsStore.shared.settings.scrollSync, Date() > ignoreEditorScrollUntil else { return }
        ignorePreviewScrollUntil = Date().addingTimeInterval(0.25)
        preview.scroll(toLine: line)
    }

    private func previewDidScroll(toLine line: Double) {
        guard isEditorVisible, SettingsStore.shared.settings.scrollSync, Date() > ignorePreviewScrollUntil else { return }
        ignoreEditorScrollUntil = Date().addingTimeInterval(0.25)
        editor.scroll(toLine: line)
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
        find(findBar.query, backwards: backwards)
    }

    private func find(_ query: String, backwards: Bool) {
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

extension DocumentViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        editor.reindex()
        document.updateText(editor.text)
        scheduleRender()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }
}

extension DocumentViewController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        240
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView.bounds.width - 320
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
}
