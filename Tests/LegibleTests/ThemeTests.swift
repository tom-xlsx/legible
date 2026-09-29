import XCTest
@testable import Legible

final class ThemeTests: XCTestCase {
    func testParsesHeaderAndVariables() {
        let css = """
        /* @name Oat Milk
           @appearance light
           @description Soft off-white. */
        :root { --bg: #f5f2eb; --fg: #2c2a26; }
        """
        let theme = Theme.parse(css: css, id: "oat-milk")
        XCTAssertEqual(theme.name, "Oat Milk")
        XCTAssertEqual(theme.appearance, .light)
        XCTAssertEqual(theme.description, "Soft off-white.")
        XCTAssertEqual(theme.variable("bg"), "#f5f2eb")
        XCTAssertEqual(theme.variable("fg"), "#2c2a26")
        XCTAssertNil(theme.variable("missing"))
    }

    func testInfersNameAndAppearanceWhenHeaderMissing() {
        let theme = Theme.parse(css: ":root { --bg: #202020; }", id: "my-night-theme")
        XCTAssertEqual(theme.name, "My Night Theme")
        XCTAssertEqual(theme.appearance, .dark)
    }

    func testHexColours() {
        XCTAssertNotNil(NSColor(hex: "#abc"))
        XCTAssertNotNil(NSColor(hex: "#aabbcc"))
        XCTAssertNotNil(NSColor(hex: "#aabbccdd"))
        XCTAssertNil(NSColor(hex: "aabbcc"))
        XCTAssertNil(NSColor(hex: "#xyz"))
        XCTAssertTrue(NSColor(hex: "#101010")!.isDark)
        XCTAssertFalse(NSColor(hex: "#f5f2eb")!.isDark)
    }

    func testLaunchOptions() {
        let options = LaunchOptions(arguments: ["Legible", "--snapshot=in.md", "--out=out.png", "--theme=oat-milk", "--size=800x600", "--scroll=120"])
        XCTAssertEqual(options.snapshotInput, "in.md")
        XCTAssertEqual(options.output, "out.png")
        XCTAssertEqual(options.theme, "oat-milk")
        XCTAssertEqual(options.size?.width, 800)
        XCTAssertEqual(options.size?.height, 600)
        XCTAssertEqual(options.scroll, "120")
        XCTAssertTrue(options.isHeadless)
        XCTAssertFalse(LaunchOptions(arguments: ["Legible"]).isHeadless)
    }
}

final class LineIndexTests: XCTestCase {
    func testLineMapping() {
        let index = LineIndex("a\nbb\n\nccc")
        XCTAssertEqual(index.lineCount, 4)
        XCTAssertEqual(index.line(at: 0), 0)
        XCTAssertEqual(index.line(at: 1), 0)
        XCTAssertEqual(index.line(at: 2), 1)
        XCTAssertEqual(index.line(at: 4), 1)
        XCTAssertEqual(index.line(at: 5), 2)
        XCTAssertEqual(index.line(at: 6), 3)
        XCTAssertEqual(index.line(at: 99), 3)
        XCTAssertEqual(index.offset(ofLine: 3), 6)
        XCTAssertEqual(index.offset(ofLine: 42), 6)
        XCTAssertEqual(LineIndex("").lineCount, 1)
        XCTAssertEqual(LineIndex("x\n").lineCount, 1)
        XCTAssertEqual(LineIndex("x\r\ny").line(at: 3), 1)
    }
}
