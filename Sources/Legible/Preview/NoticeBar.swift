import AppKit

/// A small floating, non-blocking notice with optional buttons, shown at the
/// top centre of a document window (file changed on disk, settings errors…).
final class NoticeBar: NSView {
    struct Action {
        let title: String
        let handler: () -> Void
    }

    private let label = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private let background = NSVisualEffectView()
    private var actions: [Action] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 9
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

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    var message: String { label.stringValue }

    func show(_ message: String, actions: [Action]) {
        self.actions = actions
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        label.stringValue = message
        stack.addArrangedSubview(label)
        for (i, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(runAction(_:)))
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
            button.tag = i
            if i == 0 { button.keyEquivalent = "\r" }
            stack.addArrangedSubview(button)
        }
        let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")!,
                               target: self, action: #selector(hide))
        dismiss.bezelStyle = .accessoryBarAction
        dismiss.controlSize = .small
        dismiss.isBordered = false
        stack.addArrangedSubview(dismiss)
        layoutSubtreeIfNeeded()
        frame.size = NSSize(width: max(320, stack.fittingSize.width), height: max(40, stack.fittingSize.height))
        isHidden = false
        superview?.needsLayout = true
    }

    @objc func hide() {
        isHidden = true
    }

    @objc private func runAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        hide()
        actions[sender.tag].handler()
    }
}
