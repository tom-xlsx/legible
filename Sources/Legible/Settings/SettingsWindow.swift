import AppKit
import SwiftUI

/// The Settings window (⌘,): a standard toolbar-tabbed preferences window
/// whose panes are SwiftUI views bound to SettingsStore.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: AnyView(pane.view))
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentViewController = tabs
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        windowFrameAutosaveName = "LegibleSettings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

enum SettingsPane: CaseIterable {
    case general, appearance, reading, editor, garnish

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .reading: return "Reading"
        case .editor: return "Editor"
        case .garnish: return "Garnish"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .reading: return "book"
        case .editor: return "square.split.2x1"
        case .garnish: return "leaf"
        }
    }

    @MainActor var view: any View {
        switch self {
        case .general: return GeneralPane()
        case .appearance: return AppearancePane()
        case .reading: return ReadingPane()
        case .editor: return EditorPane()
        case .garnish: return GarnishPane()
        }
    }
}
