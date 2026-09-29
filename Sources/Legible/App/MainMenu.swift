import AppKit

/// The main menu, built in code so the theme submenu can preview on hover.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        // Application
        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.item("About \(AppInfo.name)", #selector(AppDelegate.showAbout(_:)))
        appMenu.addItem(.separator())
        appMenu.item("Settings…", nil, ",").isEnabled = false
        appMenu.addItem(.separator())
        let services = NSMenu(title: "Services")
        appMenu.item("Services", nil).submenu = services
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.item("Hide \(AppInfo.name)", #selector(NSApplication.hide(_:)), "h")
        appMenu.item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", mods: [.command, .option])
        appMenu.item("Show All", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        appMenu.item("Quit \(AppInfo.name)", #selector(NSApplication.terminate(_:)), "q")
        main.item(AppInfo.name, nil).submenu = appMenu

        // File
        let file = NSMenu(title: "File")
        file.item("Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = RecentDocumentsMenu.shared
        file.item("Open Recent", nil).submenu = recent
        file.addItem(.separator())
        file.item("Close", #selector(NSWindow.performClose(_:)), "w")
        file.item("Save", #selector(NSDocument.save(_:)), "s")
        file.item("Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        file.item("Show in Finder", #selector(DocumentWindowController.showInFinder(_:)), "r", mods: [.command, .shift])
        main.item("File", nil).submenu = file

        // Edit
        let edit = NSMenu(title: "Edit")
        edit.item("Undo", Selector(("undo:")), "z")
        edit.item("Redo", Selector(("redo:")), "z", mods: [.command, .shift])
        edit.addItem(.separator())
        edit.item("Cut", #selector(NSText.cut(_:)), "x")
        edit.item("Copy", #selector(NSText.copy(_:)), "c")
        edit.item("Paste", #selector(NSText.paste(_:)), "v")
        edit.item("Select All", #selector(NSText.selectAll(_:)), "a")
        main.item("Edit", nil).submenu = edit

        // View
        let view = NSMenu(title: "View")
        let themes = NSMenu(title: "Theme")
        themes.delegate = ThemeManager.shared
        view.item("Theme", nil).submenu = themes
        view.item("Next Theme", #selector(ThemeManager.cycleTheme(_:)), "t", mods: [.command, .shift], target: ThemeManager.shared)
        view.addItem(.separator())
        view.item("Reload", #selector(DocumentWindowController.reloadDocument(_:)), "r")
        main.item("View", nil).submenu = view

        // Window
        let window = NSMenu(title: "Window")
        window.item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        window.item("Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        window.item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        main.item("Window", nil).submenu = window
        NSApp.windowsMenu = window

        // Help
        let help = NSMenu(title: "Help")
        main.item("Help", nil).submenu = help
        NSApp.helpMenu = help

        return main
    }
}

extension NSMenu {
    @discardableResult
    func item(_ title: String, _ action: Selector?, _ key: String = "",
              mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.target = target
        addItem(item)
        return item
    }
}

/// Populates File › Open Recent from NSDocumentController (no private API needed).
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
