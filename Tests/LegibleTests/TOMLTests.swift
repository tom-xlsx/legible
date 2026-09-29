import XCTest
@testable import Legible

final class TOMLTests: XCTestCase {
    let sample = """
    # Legible settings.
    # Edit freely; comments and order are kept.

    schema = 1

    [general]
    restore_windows = true   # bring windows back
    mystery_key = "kept as is"

    [appearance]
    light_theme = "oat-milk"
    dark_theme = 'burnt-toast'
    font_size = 0
    line_height = 1.6

    # trailing comment block
    """

    func testRoundTripIsByteIdentical() throws {
        let doc = try TOMLDocument(text: sample)
        XCTAssertEqual(doc.text, sample)
        let crlf = sample.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(try TOMLDocument(text: crlf).text, crlf)
        XCTAssertEqual(try TOMLDocument(text: "").text, "")
        XCTAssertEqual(try TOMLDocument(text: "a = 1").text, "a = 1")
        XCTAssertEqual(try TOMLDocument(text: "a = 1\n").text, "a = 1\n")
    }

    func testReadsValues() throws {
        let doc = try TOMLDocument(text: sample)
        XCTAssertEqual(doc.value(table: "", key: "schema"), .int(1))
        XCTAssertEqual(doc.value(table: "general", key: "restore_windows"), .bool(true))
        XCTAssertEqual(doc.value(table: "appearance", key: "light_theme"), .string("oat-milk"))
        XCTAssertEqual(doc.value(table: "appearance", key: "dark_theme"), .string("burnt-toast"))
        XCTAssertEqual(doc.value(table: "appearance", key: "font_size"), .int(0))
        XCTAssertEqual(doc.value(table: "appearance", key: "line_height"), .float(1.6))
        XCTAssertNil(doc.value(table: "appearance", key: "missing"))
        XCTAssertEqual(try TOMLDocument(text: #"s = "a\"b\\c\n\u00E9""#).value(table: "", key: "s"), .string("a\"b\\c\né"))
        XCTAssertEqual(try TOMLDocument(text: "n = -42").value(table: "", key: "n"), .int(-42))
        XCTAssertEqual(try TOMLDocument(text: "n = 1_000").value(table: "", key: "n"), .int(1000))
        XCTAssertEqual(try TOMLDocument(text: "f = 2.5e1").value(table: "", key: "f"), .float(25))
    }

    func testChangingOneSettingChangesExactlyOneLine() throws {
        var doc = try TOMLDocument(text: sample)
        doc.set(table: "appearance", key: "light_theme", value: .string("sourdough"))
        let before = sample.components(separatedBy: "\n")
        let after = doc.text.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count)
        let differing = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertEqual(differing.count, 1)
        XCTAssertEqual(differing.first?.element.1, "light_theme = \"sourdough\"")

        // Trailing comments on the changed line survive.
        var doc2 = try TOMLDocument(text: sample)
        doc2.set(table: "general", key: "restore_windows", value: .bool(false))
        XCTAssertTrue(doc2.text.contains("restore_windows = false   # bring windows back"))

        // Setting the same value again changes nothing.
        var doc3 = try TOMLDocument(text: sample)
        doc3.set(table: "appearance", key: "font_size", value: .int(0))
        XCTAssertEqual(doc3.text, sample)
    }

    func testCommentsBlankLinesOrderAndUnknownKeysSurviveAWrite() throws {
        var doc = try TOMLDocument(text: sample)
        doc.set(table: "appearance", key: "font_size", value: .int(18))
        doc.set(table: "general", key: "restore_windows", value: .bool(false))
        let text = doc.text
        XCTAssertTrue(text.hasPrefix("# Legible settings.\n# Edit freely; comments and order are kept.\n\nschema = 1\n\n[general]\n"))
        XCTAssertTrue(text.contains("mystery_key = \"kept as is\""))
        XCTAssertTrue(text.hasSuffix("\n# trailing comment block"))
        let keys = text.components(separatedBy: "\n").filter { $0.contains("=") }.map { $0.components(separatedBy: "=")[0].trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(keys, ["schema", "restore_windows", "mystery_key", "light_theme", "dark_theme", "font_size", "line_height"])
    }

    func testMissingKeyIsAppendedToItsSection() throws {
        var doc = try TOMLDocument(text: sample)
        doc.set(table: "general", key: "new_key", value: .string("x"))
        XCTAssertTrue(doc.text.contains("mystery_key = \"kept as is\"\nnew_key = \"x\"\n\n[appearance]"))
        doc.set(table: "appearance", key: "measure", value: .int(76))
        XCTAssertTrue(doc.text.contains("line_height = 1.6\nmeasure = 76\n\n# trailing comment block"))
        XCTAssertEqual(doc.value(table: "general", key: "new_key"), .string("x"))
    }

    func testMissingSectionIsAppendedAtTheEnd() throws {
        var doc = try TOMLDocument(text: sample)
        doc.set(table: "editor", key: "wrap", value: .bool(true))
        XCTAssertTrue(doc.text.hasSuffix("# trailing comment block\n\n[editor]\nwrap = true"))
        doc.set(table: "editor", key: "font_size", value: .int(13))
        XCTAssertTrue(doc.text.hasSuffix("[editor]\nwrap = true\nfont_size = 13"))

        var empty = try TOMLDocument(text: "")
        empty.set(table: "a", key: "b", value: .int(1))
        XCTAssertEqual(empty.text, "[a]\nb = 1\n")
    }

    func testRootKeyIsInsertedBeforeTheFirstTable() throws {
        var doc = try TOMLDocument(text: "# header comment\n\n[general]\nx = 1\n")
        doc.set(table: "", key: "schema", value: .int(1))
        XCTAssertEqual(doc.text, "# header comment\nschema = 1\n\n[general]\nx = 1\n")
    }

    func testParseErrorsReportTheRightLine() {
        func line(_ text: String) -> Int? {
            do { _ = try TOMLDocument(text: text); return nil } catch let error as TOMLDocument.ParseError { return error.line } catch { return -1 }
        }
        XCTAssertEqual(line("a = 1\nb = \nc = 3"), 2)
        XCTAssertEqual(line("a = 1\n\n\nno equals sign"), 4)
        XCTAssertEqual(line("[t]\nx = \"unterminated"), 2)
        XCTAssertEqual(line("x = 1\nx = 2"), 2)
        XCTAssertEqual(line("[t]\n[t]"), 2)
        XCTAssertEqual(line("x = yes"), 1)
        XCTAssertEqual(line("x = 1 2"), 1)
        XCTAssertEqual(line("a.b = 1"), 1)
        XCTAssertNil(line("x = 1 # fine"))
    }

    func testUnsupportedSyntaxIsAClearErrorNotSilentlyDropped() {
        func message(_ text: String) -> String {
            do { _ = try TOMLDocument(text: text); return "no error" } catch { return "\(error)" }
        }
        XCTAssertEqual(message("schema = 1\ntags = [\"a\", \"b\"]"), "line 2: arrays are not supported")
        XCTAssertEqual(message("point = { x = 1 }"), "line 1: inline tables are not supported")
        XCTAssertEqual(message("s = \"\"\"\nmulti\n\"\"\""), "line 1: multi-line strings are not supported")
        XCTAssertEqual(message("s = '''raw'''"), "line 1: multi-line strings are not supported")
        XCTAssertEqual(message("[[products]]\nname = \"x\""), "line 1: arrays of tables ([[…]]) are not supported")
        XCTAssertEqual(message("d = 1979-05-27"), "line 1: dates and times are not supported")
        XCTAssertEqual(message("[a.b]\nx = 1"), "line 1: table name \"a.b\" must be a plain name (letters, digits, - and _)")
    }

    func testSerialization() {
        XCTAssertEqual(TOMLDocument.Value.string("say \"hi\"\n").serialized, "\"say \\\"hi\\\"\\n\"")
        XCTAssertEqual(TOMLDocument.Value.float(1).serialized, "1.0")
        XCTAssertEqual(TOMLDocument.Value.float(1.25).serialized, "1.25")
        XCTAssertEqual(TOMLDocument.Value.int(-3).serialized, "-3")
        XCTAssertEqual(TOMLDocument.Value.bool(false).serialized, "false")
    }
}
