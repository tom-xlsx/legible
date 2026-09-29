import AppKit

/// A window that may be sized larger than the screen (used for tall snapshots).
final class DocumentWindow: NSWindow {
    var allowsOversize = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        allowsOversize ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

final class DocumentWindowController: NSWindowController {
    let viewController: DocumentViewController

    init(document: MarkdownDocument) {
        viewController = DocumentViewController(document: document)
        let window = DocumentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentViewController = viewController
        window.minSize = NSSize(width: 420, height: 300)
        window.tabbingMode = .disallowed
        window.backgroundColor = ThemeManager.shared.effective.backgroundColor
        super.init(window: window)
        shouldCascadeWindows = true
        windowFrameAutosaveName = "LegibleDocumentWindow"
        document.viewController = viewController

        let toolbar = NSToolbar(identifier: "LegibleDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @objc func toggleEditor(_ sender: Any?) { viewController.toggleEditor() }
    @objc func toggleTOC(_ sender: Any?) { viewController.toggleTOC() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = markdownDocument?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func showFind(_ sender: Any?) { viewController.showFind() }
    @objc func findNext(_ sender: Any?) { viewController.findNext(backwards: false) }
    @objc func findPrevious(_ sender: Any?) { viewController.findNext(backwards: true) }
    @objc func zoomIn(_ sender: Any?) { Zoom.step(+1) }
    @objc func zoomOut(_ sender: Any?) { Zoom.step(-1) }
    @objc func zoomActual(_ sender: Any?) { Zoom.level = 1 }

    @objc func reloadDocument(_ sender: Any?) {
        markdownDocument?.reloadFromDisk()
    }

}

extension DocumentWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleEditor(_:)):
            menuItem.title = viewController.isEditorVisible ? "Hide Editor" : "Show Editor"
            return true
        case #selector(toggleTOC(_:)):
            menuItem.title = viewController.isTOCVisible ? "Hide Table of Contents" : "Show Table of Contents"
            return true
        case #selector(showInFinder(_:)), #selector(reloadDocument(_:)):
            return markdownDocument?.fileURL != nil
        case #selector(zoomIn(_:)): return Zoom.level < Zoom.maximum
        case #selector(zoomOut(_:)): return Zoom.level > Zoom.minimum
        case #selector(zoomActual(_:)): return Zoom.level != 1
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return viewController.hasFindQuery
        default:
            return true
        }
    }
}

extension DocumentWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    private static let editorItem = NSToolbarItem.Identifier("toggleEditor")
    private static let tocItem = NSToolbarItem.Identifier("toggleTOC")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.tocItem, .flexibleSpace, Self.editorItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.tocItem, .flexibleSpace, Self.editorItem]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.editorItem:
            item.label = "Editor"
            item.toolTip = "Show or hide the editor (⌘E)"
            item.image = NSImage(systemSymbolName: "square.split.2x1", accessibilityDescription: "Editor")
            item.action = #selector(toggleEditor(_:))
        case Self.tocItem:
            item.label = "Contents"
            item.toolTip = "Show or hide the table of contents (⌘⌥T)"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Table of contents")
            item.action = #selector(toggleTOC(_:))
        default:
            return nil
        }
        item.paletteLabel = item.label
        item.target = self
        item.isBordered = true
        item.autovalidates = true
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.editorItem:
            item.image = NSImage(systemSymbolName: viewController.isEditorVisible ? "square.split.2x1.fill" : "square.split.2x1",
                                 accessibilityDescription: "Editor")
        case Self.tocItem:
            item.image = NSImage(systemSymbolName: viewController.isTOCVisible ? "sidebar.left" : "sidebar.leading",
                                 accessibilityDescription: "Table of contents")
        default:
            break
        }
        return true
    }
}
