import AppKit

/// The hidden personality features. While `hold` is on none of them run,
/// their shortcuts do nothing, and the app is entirely plain.
enum Garnish {
    private static var s: Settings { SettingsStore.shared.settings }

    static var held: Bool { s.garnishHold }
    static var mascot: Bool { !held && s.garnishMascot }
    static var copyMessages: Bool { !held && s.garnishCopyMessages }
    static var coffees: Bool { !held && s.garnishCoffees }
    static var deadpan: Bool { !held && s.garnishDeadpan }
    static var ornament: Bool { !held && s.garnishOrnament }
    static var dockIcon: Bool { !held && s.garnishDockIcon }

    // MARK: Copy

    static let copyTexts = [
        "Copied.", "Yoinked.", "It's yours now.", "Clipboard: updated.",
        "Taken.", "Duly copied.", "Noted. And copied.", "Off you go.",
    ]

    static let plainEmptyState = "This file is empty."
    static let emptyStates = [
        "Nothing to display. The file was checked twice.",
        "This document contains no text. Reading time: negligible.",
        "No content was found. This is not an error.",
        "The file is empty. Legible has no further comment.",
        "Zero words. The plate is clean.",
    ]

    static let plainAbout = "A Markdown reader for macOS.\nLicensed under the GPLv3."
    static let deadpanAbout = """
        Legible reads Markdown files. It renders them; it does not judge them.
        No data leaves this computer. There is nowhere for it to go.
        The themes are named after breakfast. This was deliberate.
        Licensed under the GPLv3. Served plain on request.
        """

    static func aboutCredits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        return NSAttributedString(string: deadpan ? deadpanAbout : plainAbout, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
    }

    /// Reading time expressed in coffees.
    static func coffees(minutes: Int) -> String {
        switch minutes {
        case ..<2: return "≈ one decaf"
        case 2..<5: return "≈ one espresso"
        case 5..<10: return "≈ one flat white"
        case 10..<20: return "≈ two coffees"
        case 20..<40: return "≈ a pot"
        default: return "≈ a pot and a lie-down"
        }
    }

    /// What the preview page needs to know.
    static var pageConfiguration: [String: Any] {
        [
            "ornament": ornament,
            "copyMessages": copyMessages ? copyTexts : ["Copied."],
            "emptyStates": deadpan ? emptyStates : [plainEmptyState],
        ]
    }

    static func toggleMascot() {
        guard !held else { return }
        var settings = SettingsStore.shared.settings
        settings.garnishMascot.toggle()
        SettingsStore.shared.settings = settings
    }
}

/// Adds the moth shortcut to the View menu only while the garnish is out.
final class ViewMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = ViewMenuDelegate()
    private static let tag = 7801

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let existing = menu.item(withTag: Self.tag) { menu.removeItem(existing) }
        if let separator = menu.items.last, separator.isSeparatorItem, menu.items.count > 1,
           menu.items[menu.items.count - 2].tag == Self.tag - 1 {
            menu.removeItem(separator)
        }
        guard !Garnish.held else { return }
        let separator = NSMenuItem.separator()
        separator.tag = Self.tag - 1
        menu.addItem(separator)
        let item = NSMenuItem(title: Garnish.mascot ? "Hide Moth" : "Show Moth", action: #selector(toggleMoth(_:)), keyEquivalent: "m")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        item.tag = Self.tag
        menu.addItem(item)
    }

    @objc private func toggleMoth(_ sender: Any?) {
        Garnish.toggleMascot()
    }
}

/// Keeps the Dock icon matched to the current theme while that garnish is on.
final class DockIconController {
    static let shared = DockIconController()
    private var observers: [NSObjectProtocol] = []
    private var lastKey = ""

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ThemeManager.didChange, object: nil, queue: .main) { [weak self] _ in self?.update() })
        observers.append(center.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in self?.update() })
        update()
    }

    func update() {
        guard Garnish.dockIcon else {
            if lastKey != "" { NSApp.applicationIconImage = nil; lastKey = "" }
            return
        }
        let theme = ThemeManager.shared.effective
        let key = theme.id + theme.css.hashValue.description
        guard key != lastKey else { return }
        lastKey = key
        NSApp.applicationIconImage = DockIcon.image(for: theme)
    }
}

/// Re-colours the app icon's SVG with a theme's palette.
enum DockIcon {
    static func image(for theme: Theme) -> NSImage? {
        guard let source = try? String(contentsOf: AppInfo.resourcesRoot.appendingPathComponent("legible.svg"), encoding: .utf8) else {
            return nil
        }
        func colour(_ name: String, _ fallback: String) -> NSColor {
            theme.variable(name).flatMap(NSColor.init(hex:)) ?? NSColor(hex: fallback)!
        }
        let bg = colour("bg", "#e9dfcc")
        let rule = colour("rule", "#c9b997")
        let plate = colour("code-bg", "#f1ebe0")
        let plateEdge = colour("code-border", "#cfc4b1")
        let accent = colour("link", "#cf8a2a")
        let ink = colour("fg", "#8f5514")
        let map: [String: NSColor] = [
            "#e9dfcc": bg.shifted(by: 0.04), "#d6c8ad": bg.shifted(by: -0.04), "#c9b997": rule,
            "#b9a884": rule, "#fbf8f2": plate.shifted(by: 0.05), "#f1ebe0": plate, "#e2d9c9": plate.shifted(by: -0.05),
            "#cfc4b1": plateEdge, "#dcd2c0": plateEdge,
            "#e2a441": accent.shifted(by: 0.12), "#cf8a2a": accent, "#a86518": accent.shifted(by: -0.15),
            "#8f5514": ink, "#f0c063": accent.shifted(by: 0.25), "#8a4f12": ink,
        ]
        var svg = source
        for (from, to) in map { svg = svg.replacingOccurrences(of: from, with: to.hexString) }
        return NSImage(data: Data(svg.utf8))
    }
}

extension NSColor {
    /// Lightens (positive) or darkens (negative) in sRGB, clamped.
    func shifted(by amount: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.sRGB) else { return self }
        func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v + amount)) }
        return NSColor(srgbRed: clamp(c.redComponent), green: clamp(c.greenComponent), blue: clamp(c.blueComponent), alpha: c.alphaComponent)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
