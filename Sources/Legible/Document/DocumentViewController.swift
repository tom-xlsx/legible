import AppKit
import SwiftUI

/// Hosts the three panes (table of contents, editor, preview) in a split view
/// controller, plus the floating find bar and notice bar.
final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    let preview: PreviewView
    let editor = EditorView(frame: .zero)
    let toc = TOCModel()
    private(set) lazy var moth = MothController(document: document)

    private let tocView: NSHostingView<TOCView>
    private let split = NSSplitViewController()
    private var tocItem: NSSplitViewItem!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private let findBar = FindBar(frame: .zero)
    private let noticeBar = NoticeBar(frame: .zero)
    private let token: String
    private var observers: [NSObjectProtocol] = []
    private var renderTimer: Timer?
    private var ignoreEditorScrollUntil = Date.distantPast
    private var ignorePreviewScrollUntil = Date.distantPast
    private static let editorWidthKey = "editorWidth"
    private static let tocWidthKey = "tocWidth"

    /// Set once the first render has completed (used by the snapshot and self-test jobs).
    private(set) var hasRendered = false
    /// Last reported top line of the preview (kept for session restore).
    private(set) var lastTopLine: Double = 0
    private(set) var wordCount = 0
    var onRendered: ((PreviewView.RenderInfo) -> Void)?
    private var afterNextRender: (() -> Void)?

    init(document: MarkdownDocument) {
        self.document = document
        token = DocumentRegistry.shared.register(directory: document.directoryURL)
        preview = PreviewView(token: token)
        tocView = NSHostingView(rootView: TOCView(model: toc))
        super.init(nibName: nil, bundle: nil)
        toc.onSelect = { [weak self] id in self?.preview.scroll(toHeading: id) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        moth.flush(readingLine: lastTopLine)
        DocumentRegistry.shared.unregister(token)
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 800))

        tocItem = NSSplitViewItem(viewController: WrapperViewController(view: tocView))
        tocItem.canCollapse = true
        tocItem.isCollapsed = true
        tocItem.minimumThickness = 160
        tocItem.maximumThickness = 360
        tocItem.holdingPriority = .defaultLow + 2

        editorItem = NSSplitViewItem(viewController: WrapperViewController(view: editor))
        editorItem.canCollapse = true
        editorItem.isCollapsed = true   // reading mode by default; never restored as visible
        editorItem.minimumThickness = 240
        editorItem.holdingPriority = .defaultLow

        previewItem = NSSplitViewItem(viewController: WrapperViewController(view: preview))
        previewItem.minimumThickness = 320
        previewItem.holdingPriority = .defaultLow - 1

        split.addSplitViewItem(tocItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(previewItem)
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        addChild(split)
        split.view.frame = container.bounds
        split.view.autoresizingMask = [.width, .height]
        container.addSubview(split.view)

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

    override func viewDidLoad() {
        super.viewDidLoad()
        preview.onRendered = { [weak self] info in
            guard let self else { return }
            hasRendered = true
            toc.headings = info.headings.map { TOCModel.Heading(level: $0.level, text: $0.text, id: $0.id) }
            let current = toc.currentID
            if current == nil || !toc.headings.contains(where: { $0.id == current }) {
                toc.currentID = toc.headings.first?.id
            }
            updateReadingTime(words: info.words)
            let pending = afterNextRender
            afterNextRender = nil
            pending?()
            onRendered?(info)
        }
        preview.onMothMessage = { [weak self] message in self?.moth.handle(message: message) }
        preview.onScroll = { [weak self] info in
            guard let self else { return }
            lastTopLine = info.line
            if let id = info.headingID, toc.currentID != id { toc.currentID = id }
            previewDidScroll(toLine: info.line)
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
        observers.append(center.addObserver(forName: PreviewView.externalLinkOpened, object: preview, queue: .main) { [weak self] _ in
            self?.preview.mothEvent("external-link")
        })
        applySettings()

        findBar.onQueryChange = { [weak self] query in self?.find(query, backwards: false) }
        findBar.onNext = { [weak self] in self?.findNext(backwards: false) }
        findBar.onPrevious = { [weak self] in self?.findNext(backwards: true) }
        findBar.onClose = { [weak self] in self?.hideFind() }

        if SettingsStore.shared.settings.tocSidebar { showTOC() }
        render(preserveScroll: false)
    }

    func applyTheme() {
        let theme = ThemeManager.shared.effective
        preview.setTheme(css: theme.css)
        preview.setBackground(theme.backgroundColor)
        editor.apply(theme: theme)
        toc.apply(theme: theme)
        view.window?.backgroundColor = theme.backgroundColor
        if hasRendered {
            var garnish = Garnish.pageConfiguration
            garnish["moth"] = moth.configuration(theme: theme)
            preview.configure(garnish: garnish)
        }
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
        var garnish = Garnish.pageConfiguration
        garnish["moth"] = moth.configuration(theme: ThemeManager.shared.effective)
        preview.configure(garnish: garnish)
        editor.apply(settings: s)
        view.window?.subtitle = s.showReadingTime && hasRendered ? ReadingTime.label(words: wordCount) : ""

        if let error = store.fileError {
            showingSettingsError = true
            noticeBar.show(error, actions: [.init(title: "Reveal File", handler: { store.revealFile() })])
            view.needsLayout = true
        } else if let problem = moth.packProblem {
            showingSettingsError = true
            noticeBar.show(problem, actions: [.init(title: "Show Folder", handler: { NSWorkspace.shared.activateFileViewerSelecting([MothPack.userDirectory]) })])
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
        MothController.reloadPack()
        preview.mothEvent("reload")
        if isEditorVisible {
            let line = editor.topLine
            editor.text = document.text
            editor.scroll(toLine: line)
        }
        render(preserveScroll: true)
    }

    /// The file changed on disk while there are unsaved edits: let the person decide.
    func showDiskChangeNotice(reload: @escaping () -> Void) {
        noticeBar.show("This file was changed on disk. Your unsaved edits are still here.", actions: [
            .init(title: "Reload", handler: reload),
            .init(title: "Keep Mine", handler: {}),
        ])
        view.needsLayout = true
    }

    // MARK: Panes

    private var dividerThickness: CGFloat { split.splitView.dividerThickness }

    var isEditorVisible: Bool { !editorItem.isCollapsed }
    var isTOCVisible: Bool { !tocItem.isCollapsed }

    func toggleEditor() {
        if isEditorVisible { hideEditor() } else { showEditor() }
    }

    func showEditor() {
        guard !isEditorVisible else { return }
        editor.text = document.text
        let saved = UserDefaults.standard.double(forKey: Self.editorWidthKey)
        let leading = isTOCVisible ? tocView.frame.width + dividerThickness : 0
        let width = max(240, min(saved > 0 ? CGFloat(saved) : split.view.bounds.width / 2, split.view.bounds.width - leading - 320))
        expand(editorItem, view: editor, dividerIndex: 1, position: leading + width, width: width)
        editor.scroll(toLine: 0)
        view.window?.makeFirstResponder(editor.textView)
        view.window?.toolbar?.validateVisibleItems()
        preview.mothEvent("editor-open")
    }

    func hideEditor() {
        guard isEditorVisible else { return }
        UserDefaults.standard.set(Double(editor.frame.width), forKey: Self.editorWidthKey)
        editorItem.isCollapsed = true
        view.window?.makeFirstResponder(preview.webView)
        view.window?.toolbar?.validateVisibleItems()
        preview.mothEvent("editor-close")
    }

    func toggleTOC() {
        if isTOCVisible { hideTOC() } else { showTOC() }
    }

    func showTOC() {
        guard !isTOCVisible else { return }
        let saved = UserDefaults.standard.double(forKey: Self.tocWidthKey)
        let width = max(160, min(saved > 0 ? CGFloat(saved) : 230, 360))
        expand(tocItem, view: tocView, dividerIndex: 0, position: width, width: width)
        view.window?.toolbar?.validateVisibleItems()
    }

    /// Expands a pane with a single layout pass: the pane is given its width before it
    /// uncollapses, so the preview resizes once instead of twice (which showed as a flicker).
    private func expand(_ item: NSSplitViewItem, view pane: NSView, dividerIndex: Int, position: CGFloat, width: CGFloat) {
        pane.frame.size.width = width
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            item.isCollapsed = false
            split.splitView.layoutSubtreeIfNeeded()
            if abs(pane.frame.width - width) > 1 {
                split.splitView.setPosition(position, ofDividerAt: dividerIndex)
            }
        }
    }

    func hideTOC() {
        guard isTOCVisible else { return }
        UserDefaults.standard.set(Double(tocView.frame.width), forKey: Self.tocWidthKey)
        tocItem.isCollapsed = true
        view.window?.toolbar?.validateVisibleItems()
    }

    var findBarForTesting: FindBar { findBar }
    var noticeBarForTesting: NoticeBar { noticeBar }
    var tocViewForTesting: NSView { tocView }

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

    // MARK: Reading time

    private func updateReadingTime(words: Int) {
        wordCount = words
        view.window?.subtitle = SettingsStore.shared.settings.showReadingTime ? ReadingTime.label(words: words) : ""
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

    func showFind() {
        if findBar.isHidden { preview.mothEvent("find-open") }
        findBar.isHidden = false
        findBar.focus()
    }

    func hideFind() {
        if !findBar.isHidden { preview.mothEvent("find-close") }
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

/// Wraps a plain view as a view controller for NSSplitViewController.
private final class WrapperViewController: NSViewController {
    private let wrapped: NSView

    init(view: NSView) {
        wrapped = view
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func loadView() {
        wrapped.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        view = wrapped
    }
}

/// Reading time at a steady 230 words per minute.
enum ReadingTime {
    static let wordsPerMinute = 230.0

    static func minutes(words: Int) -> Int {
        Int((Double(words) / wordsPerMinute).rounded(.up))
    }

    static func label(words: Int) -> String {
        guard words > 0 else { return "" }
        let m = minutes(words: words)
        if Garnish.coffees { return Garnish.coffees(minutes: m) }
        return m <= 1 ? "1 min read" : "\(m) min read"
    }
}
