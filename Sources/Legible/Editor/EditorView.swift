import AppKit

/// Maps character offsets to line numbers and back, rebuilt whenever the text changes.
struct LineIndex {
    /// UTF-16 offset where each line starts; lineStarts[0] == 0.
    private(set) var lineStarts: [Int] = [0]

    init(_ text: String) {
        let ns = text as NSString
        var starts = [0]
        var i = 0
        let length = ns.length
        while i < length {
            var contentsEnd = 0, lineEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: i, length: 0))
            if lineEnd == i { break }
            if lineEnd < length { starts.append(lineEnd) }
            i = lineEnd
        }
        lineStarts = starts
    }

    var lineCount: Int { lineStarts.count }

    /// Zero-based line containing the character at `offset`.
    func line(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Character offset where `line` starts (clamped).
    func offset(ofLine line: Int) -> Int {
        lineStarts[max(0, min(line, lineStarts.count - 1))]
    }
}

/// The Markdown source editor: a plain NSTextView in a scroll view.
final class EditorView: NSView {
    let scrollView = NSScrollView()
    let textView: NSTextView

    /// Called with the fractional zero-based source line at the top of the visible area.
    var onScroll: ((Double) -> Void)?
    private(set) var lineIndex = LineIndex("")
    private var suppressScrollEvents = false

    override init(frame frameRect: NSRect) {
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        textView = NSTextView(frame: .zero, textContainer: container)
        super.init(frame: frameRect)

        textView.isRichText = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            reindex()
        }
    }

    func reindex() {
        lineIndex = LineIndex(textView.string)
    }

    func apply(settings: Settings) {
        let size = CGFloat(settings.editorFontSize)
        let font = settings.editorFont.isEmpty ? nil : NSFont(name: settings.editorFont, size: size)
        textView.font = font ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        setWraps(settings.editorWrap)
    }

    private func setWraps(_ wraps: Bool) {
        guard let container = textView.textContainer else { return }
        if wraps {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            scrollView.hasHorizontalScroller = true
        }
        textView.needsLayout = true
    }

    func apply(theme: Theme) {
        let bg = theme.backgroundColor
        let fg = theme.variable("fg").flatMap(NSColor.init(hex:)) ?? .textColor
        textView.backgroundColor = bg
        scrollView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = fg
        if let selection = theme.variable("selection-bg").flatMap(NSColor.init(hex:)) {
            textView.selectedTextAttributes = [.backgroundColor: selection,
                                               .foregroundColor: theme.variable("selection-fg").flatMap(NSColor.init(hex:)) ?? fg]
        }
    }

    // MARK: Scroll sync

    /// The fractional line at the top of the visible rect.
    var topLine: Double {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return 0 }
        let visible = scrollView.contentView.bounds
        let y = max(0, visible.origin.y - textView.textContainerInset.height)
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: y), in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        let line = lineIndex.line(at: char)
        let lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let fraction = lineRect.height > 0 ? Double(max(0, min(1, (y - lineRect.minY) / lineRect.height))) : 0
        return Double(line) + fraction
    }

    /// Scrolls so `line` (fractional, zero-based) sits at the top of the visible area.
    func scroll(toLine line: Double) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let whole = Int(line.rounded(.down))
        let offset = lineIndex.offset(ofLine: whole)
        let length = (textView.string as NSString).length
        layout.ensureLayout(for: container)   // lazy layout would under-report the document height
        let glyph = layout.glyphIndexForCharacter(at: min(offset, max(0, length - 1)))
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = rect.minY + rect.height * CGFloat(line - Double(whole)) + textView.textContainerInset.height
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        suppressScrollEvents = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        DispatchQueue.main.async { [weak self] in self?.suppressScrollEvents = false }
    }

    @objc private func boundsChanged() {
        guard !suppressScrollEvents else { return }
        onScroll?(topLine)
    }
}
