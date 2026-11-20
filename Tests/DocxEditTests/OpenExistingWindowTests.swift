import XCTest
@testable import DocxEdit

/// Повторное открытие уже открытого файла находит его окно, а не грузит копию.
@MainActor
final class OpenExistingWindowTests: XCTestCase {
    func testFindsSessionByPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Отчёт.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let a = DocumentSession(), b = DocumentSession()
        b.markSaved(url: file)
        let viaDots = dir.appendingPathComponent("../\(dir.lastPathComponent)/Отчёт.md")
        XCTAssertTrue(AppDelegate.session(showing: viaDots, among: [a, b]) === b)
        XCTAssertNil(AppDelegate.session(showing: dir.appendingPathComponent("другой.md"), among: [a, b]))
    }

    /// Новые окна не делят один документ: сохранение одного не даёт путь другим.
    func testNewSessionsDoNotShareBridge() {
        let a = DocumentSession(), b = DocumentSession()
        b.markSaved(url: URL(fileURLWithPath: "/tmp/новый.docx"))
        XCTAssertNil(a.bridge.fileURL)
    }
}
