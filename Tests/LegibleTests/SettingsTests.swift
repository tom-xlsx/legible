import XCTest
@testable import Legible

final class SettingsTests: XCTestCase {
    func testDefaultsWithNoFileOrEmptyFile() throws {
        let empty = try TOMLDocument(text: "")
        let loaded = Settings.load(from: empty)
        XCTAssertEqual(loaded.settings, Settings())
        XCTAssertTrue(loaded.warnings.isEmpty)
    }

    func testDefaultFileRoundTrips() throws {
        let text = Settings.defaultFileText()
        let doc = try TOMLDocument(text: text)
        XCTAssertEqual(doc.value(table: "", key: "schema"), .int(Settings.schemaVersion))
        XCTAssertEqual(Settings.load(from: doc).settings, Settings())
        // Every field is present, and every documented field has its comment right above it.
        for field in Settings.fields {
            XCTAssertNotNil(doc.value(table: field.table, key: field.key), "\(field.table).\(field.key) missing from default file")
            if !field.comment.isEmpty {
                XCTAssertTrue(text.contains("# \(field.comment)\n\(field.key) = "), "comment missing for \(field.key)")
            }
        }
        XCTAssertTrue(text.hasPrefix("# Legible settings."))
    }

    func testWrongTypeKeepsDefaultAndWarns() throws {
        let doc = try TOMLDocument(text: "[appearance]\nfont_size = \"big\"\nzoom = 2\n[reading]\nunknown = true\n")
        let loaded = Settings.load(from: doc)
        XCTAssertEqual(loaded.settings.fontSize, 0)
        XCTAssertEqual(loaded.settings.zoom, 2)          // ints are accepted for decimals
        XCTAssertEqual(loaded.warnings, ["[appearance] font_size has the wrong type; using the default"])
    }

    func testApplyPatchesOnlyChangedKeys() throws {
        var doc = try TOMLDocument(text: Settings.defaultFileText())
        let before = doc.text
        var settings = Settings()
        settings.lightTheme = "sourdough"
        settings.apply(to: &doc)
        let diff = zip(before.components(separatedBy: "\n"), doc.text.components(separatedBy: "\n")).filter { $0 != $1 }
        XCTAssertEqual(diff.count, 1)
        XCTAssertEqual(diff.first?.1, "light_theme = \"sourdough\"")
    }

    func testMigrationAddsSchemaInPlace() throws {
        let old = """
        # my settings

        [appearance]
        light_theme = "hashbrown"   # warm
        """
        var doc = try TOMLDocument(text: old)
        XCTAssertTrue(SettingsMigration.migrate(&doc))
        XCTAssertEqual(doc.text, """
        # my settings
        schema = 1

        [appearance]
        light_theme = "hashbrown"   # warm
        """)
        XCTAssertEqual(Settings.load(from: doc).settings.lightTheme, "hashbrown")
        XCTAssertFalse(SettingsMigration.migrate(&doc), "current schema must not migrate again")

        var current = try TOMLDocument(text: Settings.defaultFileText())
        let text = current.text
        XCTAssertFalse(SettingsMigration.migrate(&current))
        XCTAssertEqual(current.text, text)
    }

    func testStoreWritesFileAndReloadsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("legible-settings-\(UUID().uuidString)")
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.toml"))
        store.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path), "default file is created")
        let initial = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertEqual(initial, Settings.defaultFileText())

        store.settings.fontSize = 18
        let written = try String(contentsOf: store.fileURL, encoding: .utf8)
        let diff = zip(initial.components(separatedBy: "\n"), written.components(separatedBy: "\n")).filter { $0 != $1 }
        XCTAssertEqual(diff.map(\.1), ["font_size = 18"])

        // Edits on disk come back in, comments included.
        try written.replacingOccurrences(of: "font_size = 18", with: "font_size = 20  # bigger").write(to: store.fileURL, atomically: true, encoding: .utf8)
        store.loadFromDisk()
        XCTAssertEqual(store.settings.fontSize, 20)
        XCTAssertNil(store.fileError)

        // A broken file keeps the last good settings and names the line.
        try "schema = 1\n[appearance]\nfont_size = [1, 2]\n".write(to: store.fileURL, atomically: true, encoding: .utf8)
        store.loadFromDisk()
        XCTAssertEqual(store.settings.fontSize, 20)
        XCTAssertEqual(store.fileError, "settings.toml line 3: arrays are not supported. Using the last good settings.")

        store.resetToDefaults()
        XCTAssertEqual(store.settings, Settings())
        XCTAssertNil(store.fileError)
        try? FileManager.default.removeItem(at: dir)
    }
}
