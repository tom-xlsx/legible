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
        // AppKit inserts "Open Recent" after any openDocument: item automatically.
        file.addItem(.separator())
        file.item("Close", #selector(NSWindow.performClose(_:)), "w")
        file.item("Save", #selector(NSDocument.save(_:)), "s")
        file.item("Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        file.item("Show in Finder", #selector(DocumentWindowController.showInFinder(_:)), "r", mods: [.command, .shift])
        file.addItem(.separator())
        file.item("Use Legible for Markdown Files…", #selector(DefaultAppMenuTarget.makeDefault(_:)), target: DefaultAppMenuTarget.shared)
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
        edit.addItem(.separator())
        edit.item("Find…", #selector(DocumentWindowController.showFind(_:)), "f")
        edit.item("Find Next", #selector(DocumentWindowController.findNext(_:)), "g")
        edit.item("Find Previous", #selector(DocumentWindowController.findPrevious(_:)), "g", mods: [.command, .shift])
        main.item("Edit", nil).submenu = edit

        // View
        let view = NSMenu(title: "View")
        view.item("Show Editor", #selector(DocumentWindowController.toggleEditor(_:)), "e")
        view.addItem(.separator())
        let themes = NSMenu(title: "Theme")
        themes.delegate = ThemeManager.shared
        view.item("Theme", nil).submenu = themes
        view.item("Next Theme", #selector(ThemeManager.cycleTheme(_:)), "t", mods: [.command, .shift], target: ThemeManager.shared)
        view.addItem(.separator())
        view.item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+")
        view.item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "=").isHidden = true
        view.item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-")
        view.item("Actual Size", #selector(DocumentWindowController.zoomActual(_:)), "0")
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
