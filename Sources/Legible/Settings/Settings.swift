import Foundation

/// Every setting, with a sensible default. The app works with no file at all.
struct Settings: Equatable {
    static let schemaVersion = 1

    // [general]
    var restoreWindows = true

    // [appearance]
    var theme = "system"          // "system" follows the appearance; otherwise a theme id
    var lightTheme = "oat-milk"
    var darkTheme = "burnt-toast"
    var fontBody = ""             // empty = theme's font
    var fontMono = ""
    var fontSize = 0              // px; 0 = theme's size
    var lineHeight = 0.0          // 0 = theme's
    var measure = 0               // ch; 0 = theme's
    var zoom = 1.0

    // [reading]
    var tocSidebar = false
    var showReadingTime = true
    var openMarkdownLinksInLegible = true
    var liveReload = true

    // [editor]
    var editorFont = ""           // empty = system monospace
    var editorFontSize = 13
    var editorWrap = true
    var scrollSync = true

    // [garnish]
    var garnishHold = true
    var garnishMascot = true
    var garnishCopyMessages = true
    var garnishCoffees = true
    var garnishDeadpan = true
    var garnishOrnament = true
    var garnishDockIcon = true
}

/// Describes one key in settings.toml: where it lives, how to read and write it, and its comment.
struct SettingField {
    let table: String
    let key: String
    let comment: String
    let read: (TOMLDocument.Value, inout Settings) -> Bool   // false = wrong type
    let write: (Settings) -> TOMLDocument.Value

    static func bool(_ table: String, _ key: String, _ path: WritableKeyPath<Settings, Bool>, _ comment: String) -> SettingField {
        .init(table: table, key: key, comment: comment,
              read: { value, settings in
                  guard case .bool(let b) = value else { return false }
                  settings[keyPath: path] = b
                  return true
              },
              write: { .bool($0[keyPath: path]) })
    }

    static func int(_ table: String, _ key: String, _ path: WritableKeyPath<Settings, Int>, _ comment: String) -> SettingField {
        .init(table: table, key: key, comment: comment,
              read: { value, settings in
                  guard case .int(let i) = value else { return false }
                  settings[keyPath: path] = i
                  return true
              },
              write: { .int($0[keyPath: path]) })
    }

    static func double(_ table: String, _ key: String, _ path: WritableKeyPath<Settings, Double>, _ comment: String) -> SettingField {
        .init(table: table, key: key, comment: comment,
              read: { value, settings in
                  switch value {
                  case .float(let d): settings[keyPath: path] = d
                  case .int(let i): settings[keyPath: path] = Double(i)
                  default: return false
                  }
                  return true
              },
              write: { .float($0[keyPath: path]) })
    }

    static func string(_ table: String, _ key: String, _ path: WritableKeyPath<Settings, String>, _ comment: String) -> SettingField {
        .init(table: table, key: key, comment: comment,
              read: { value, settings in
                  guard case .string(let s) = value else { return false }
                  settings[keyPath: path] = s
                  return true
              },
              write: { .string($0[keyPath: path]) })
    }
}

extension Settings {
    static let tableComments: [(String, String)] = [
        ("general", "Startup and integration."),
        ("appearance", "Themes, type and measure. Empty strings and zeros mean \"use the theme's own value\"."),
        ("reading", "Reading mode behaviour."),
        ("editor", "The editor pane (⌘E)."),
        ("garnish", "Served plain."),
    ]

    static let fields: [SettingField] = [
        .bool("general", "restore_windows", \.restoreWindows, "Reopen the documents that were open at quit."),

        .string("appearance", "theme", \.theme, "\"system\" follows light/dark mode using the two defaults below; or pin a theme id (e.g. \"sourdough\")."),
        .string("appearance", "light_theme", \.lightTheme, "Theme used in light mode."),
        .string("appearance", "dark_theme", \.darkTheme, "Theme used in dark mode."),
        .string("appearance", "font_body", \.fontBody, "Body font family, e.g. \"Charter\". Empty keeps the theme's font."),
        .string("appearance", "font_mono", \.fontMono, "Code font family. Empty keeps the theme's font."),
        .int("appearance", "font_size", \.fontSize, "Base size in pixels. 0 keeps the theme's size."),
        .double("appearance", "line_height", \.lineHeight, "Line height as a multiplier, e.g. 1.6. 0 keeps the theme's."),
        .int("appearance", "measure", \.measure, "Maximum text column width in characters, e.g. 76. 0 keeps the theme's."),
        .double("appearance", "zoom", \.zoom, "Page zoom (⌘+ / ⌘−). 1.0 is actual size."),

        .bool("reading", "toc_sidebar", \.tocSidebar, "Show the table-of-contents sidebar when a document opens."),
        .bool("reading", "show_reading_time", \.showReadingTime, "Show an estimated reading time."),
        .bool("reading", "open_markdown_links_in_legible", \.openMarkdownLinksInLegible, "Open links to other Markdown files in Legible (false: in the default app)."),
        .bool("reading", "live_reload", \.liveReload, "Re-render when the file changes on disk."),

        .string("editor", "font", \.editorFont, "Editor font family. Empty uses the system monospace font."),
        .int("editor", "font_size", \.editorFontSize, "Editor font size in points."),
        .bool("editor", "wrap", \.editorWrap, "Wrap long lines in the editor."),
        .bool("editor", "scroll_sync", \.scrollSync, "Keep the editor and preview scrolled together."),

        .bool("garnish", "hold", \.garnishHold, "Hold the garnish."),
        .bool("garnish", "mascot", \.garnishMascot, ""),
        .bool("garnish", "copy_messages", \.garnishCopyMessages, ""),
        .bool("garnish", "reading_time_coffees", \.garnishCoffees, ""),
        .bool("garnish", "deadpan", \.garnishDeadpan, ""),
        .bool("garnish", "end_ornament", \.garnishOrnament, ""),
        .bool("garnish", "dock_icon", \.garnishDockIcon, ""),
    ]

    /// Reads settings out of a parsed document; unknown keys are ignored and
    /// wrong types keep their defaults, each reported as a warning.
    static func load(from document: TOMLDocument) -> (settings: Settings, warnings: [String]) {
        var settings = Settings()
        var warnings: [String] = []
        for field in fields {
            guard let value = document.value(table: field.table, key: field.key) else { continue }
            if !field.read(value, &settings) {
                warnings.append("[\(field.table)] \(field.key) has the wrong type; using the default")
            }
        }
        return (settings, warnings)
    }

    /// Writes every field whose value differs from what the document already holds.
    func apply(to document: inout TOMLDocument) {
        for field in Self.fields {
            let value = field.write(self)
            if document.value(table: field.table, key: field.key) != value {
                document.set(table: field.table, key: field.key, value: value)
            }
        }
    }

    /// The commented file written when none exists (and by Reset to Defaults).
    static func defaultFileText(for settings: Settings = Settings()) -> String {
        var out = """
        # Legible settings.
        #
        # This file is read when Legible starts and whenever it changes; edits apply
        # immediately. Legible only ever rewrites the single line a setting lives on,
        # so comments, order and any extra keys you add are kept. Delete the file (or
        # use Reset to Defaults) to start again.
        #
        # Valid values are strings in quotes, whole numbers, decimals and true/false.

        schema = \(schemaVersion)

        """
        for (table, comment) in tableComments {
            out += "\n# \(comment)\n[\(table)]\n"
            for field in fields where field.table == table {
                if !field.comment.isEmpty { out += "# \(field.comment)\n" }
                out += "\(field.key) = \(field.write(settings).serialized)\n"
            }
        }
        return out
    }
}

/// Brings an older settings file up to the current schema, in place.
enum SettingsMigration {
    /// Returns true if the document was changed.
    static func migrate(_ document: inout TOMLDocument) -> Bool {
        var version = 0
        if case .int(let v)? = document.value(table: "", key: "schema") { version = v }
        guard version < Settings.schemaVersion else { return false }
        // Schema 0 → 1: the first versioned layout; nothing to rename.
        document.set(table: "", key: "schema", value: .int(Settings.schemaVersion))
        return true
    }
}
