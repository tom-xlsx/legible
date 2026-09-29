import AppKit

/// A small floating find panel: search field, "n of m", previous/next, done.
final class FindBar: NSView {
    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let background = NSVisualEffectView()

    var query: String { searchField.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = false
        shadow = NSShadow()
        shadow?.shadowBlurRadius = 8
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.25)

        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 9
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)

        searchField.placeholderString = "Find"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        configure(previousButton, symbol: "chevron.up", label: "Previous match", action: #selector(previous))
        configure(nextButton, symbol: "chevron.down", label: "Next match", action: #selector(next))
        doneButton.bezelStyle = .accessoryBarAction
        doneButton.controlSize = .small
        doneButton.target = self
        doneButton.action = #selector(close)
        doneButton.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [searchField, countLabel, previousButton, nextButton, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 190),
            countLabel.widthAnchor.constraint(equalToConstant: 64),
        ])
        setCount(index: 0, total: 0, hasQuery: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.isBordered = true
        button.target = self
        button.action = action
        button.setAccessibilityLabel(label)
    }

    func setCount(index: Int, total: Int, hasQuery: Bool) {
        if !hasQuery { countLabel.stringValue = "" }
        else if total == 0 { countLabel.stringValue = "None" }
        else { countLabel.stringValue = "\(index) of \(total)" }
        previousButton.isEnabled = total > 0
        nextButton.isEnabled = total > 0
    }

    func focus() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    @objc private func previous() { onPrevious?() }
    @objc private func next() { onNext?() }
    @objc private func close() { onClose?() }
}

extension FindBar: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            shift ? onPrevious?() : onNext?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty { onClose?() } else {
                searchField.stringValue = ""
                onQueryChange?("")
            }
            return true
        default:
            return false
        }
    }
}
