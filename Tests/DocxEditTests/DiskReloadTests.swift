import XCTest
@testable import DocxEdit

/// Изменения файла на диске: слежение, подсветка изменённого участка.
@MainActor
final class DiskReloadTests: XCTestCase {
    func testChangedRange() {
        XCTAssertNil(DocumentSession.changedRange(old: "а\nб", new: "а\nб"))
        XCTAssertEqual(DocumentSession.changedRange(old: "раз\nдва\nтри", new: "раз\nДВА!\nтри"),
                       NSRange(location: 4, length: 4))
        XCTAssertEqual(DocumentSession.changedRange(old: "раз\n", new: "раз\nдва\n"),
                       NSRange(location: 4, length: 4))
    }

    private func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("doc.md")
        try "раз".write(to: f, atomically: false, encoding: .utf8)
        return f
    }

    private func waitForChanges(_ url: URL, write: (URL) throws -> Void) throws -> Int {
        var count = 0
        let w = FileWatcher(url: url) { count += 1 }
        try write(url)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        // Вторая запись после атомарной замены — подписка должна пережить подмену.
        try write(url)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        _ = w
        return count
    }

    func testWatcherSeesAtomicReplaceTwice() throws {
        let f = try tempFile()
        let n = try waitForChanges(f) { try "новое \(UUID())".write(to: $0, atomically: true, encoding: .utf8) }
        XCTAssertEqual(n, 2)
    }

    func testWatcherSeesInPlaceWrite() throws {
        let f = try tempFile()
        let n = try waitForChanges(f) { try "ещё \(UUID())".write(to: $0, atomically: false, encoding: .utf8) }
        XCTAssertEqual(n, 2)
    }

    /// Собственное сохранение (markSaved после записи) — не «чужое» изменение.
    func testOwnSaveIsNotReported() throws {
        let f = try tempFile()
        let s = DocumentSession()
        s.markSaved(url: f)
        try "своё".write(to: f, atomically: true, encoding: .utf8)
        s.markSaved(url: f)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertNil(s.diskChange)
        try FileManager.default.removeItem(at: f)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertEqual(s.diskChange, .deleted)
    }
}
