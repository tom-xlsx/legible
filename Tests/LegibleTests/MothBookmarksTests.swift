import XCTest
@testable import Legible

final class MothBookmarksTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("moth-\(UUID().uuidString).json")
    }

    func testSaveAndRestore() {
        let url = temporaryURL()
        let store = MothBookmarks(fileURL: url)
        XCTAssertNil(store.line(for: "/a.md"))
        store.set(line: 42.5, for: "/a.md")
        store.set(line: 7, for: "/b.md")
        store.save()

        let reloaded = MothBookmarks(fileURL: url)
        XCTAssertEqual(reloaded.line(for: "/a.md"), 42.5)
        XCTAssertEqual(reloaded.line(for: "/b.md"), 7)
        reloaded.set(line: 100, for: "/a.md")
        XCTAssertEqual(reloaded.line(for: "/a.md"), 100)
        XCTAssertEqual(reloaded.entries.count, 2, "updating a path must not duplicate it")
        reloaded.remove(path: "/a.md")
        XCTAssertNil(reloaded.line(for: "/a.md"))
        try? FileManager.default.removeItem(at: url)
    }

    func testKeepsOnlyTheMostRecentFiveHundred() {
        let url = temporaryURL()
        let store = MothBookmarks(fileURL: url)
        for i in 0..<620 { store.set(line: Double(i), for: "/doc\(i).md") }
        XCTAssertEqual(store.entries.count, MothBookmarks.capacity)
        XCTAssertNil(store.line(for: "/doc0.md"), "oldest entries are dropped")
        XCTAssertNil(store.line(for: "/doc119.md"))
        XCTAssertEqual(store.line(for: "/doc120.md"), 120)
        XCTAssertEqual(store.line(for: "/doc619.md"), 619)
        // Touching an old entry makes it recent again.
        store.set(line: 1, for: "/doc120.md")
        store.set(line: 0, for: "/new.md")
        XCTAssertEqual(store.line(for: "/doc120.md"), 1)
        XCTAssertNil(store.line(for: "/doc121.md"))
        store.save()
        XCTAssertEqual(MothBookmarks(fileURL: url).entries.count, MothBookmarks.capacity)
        try? FileManager.default.removeItem(at: url)
    }

    func testMissingOrCorruptFileStartsEmpty() throws {
        let url = temporaryURL()
        XCTAssertTrue(MothBookmarks(fileURL: url).entries.isEmpty)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(MothBookmarks(fileURL: url).entries.isEmpty)
        try? FileManager.default.removeItem(at: url)
    }
}
