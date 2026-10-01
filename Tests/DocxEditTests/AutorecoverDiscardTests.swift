import XCTest
@testable import DocxEdit

/// «Не сохранять» удаляет autorecover-копию — и она не должна воскреснуть
/// от тика таймера, пока контроллер ещё жив (ADR-055).
final class AutorecoverDiscardTests: XCTestCase {

    @MainActor
    func testDiscardedBackupIsNotRecreatedByTimer() {
        let session = DocumentSession()
        let controller = DocumentController()
        controller.attach(session: session)
        session.isMarkdownSourceMode = true
        session.markdownSource = "черновик"
        session.bridge.isDirty = true
        controller.startAutorecover(interval: 0.05)

        let dir = DocumentController.autorecoverDirectory
        let json = dir.appendingPathComponent(session.autorecoverFileName)
        let md = json.deletingPathExtension().appendingPathExtension("md")
        defer {
            controller.stopAutorecover()
            try? FileManager.default.removeItem(at: json)
            try? FileManager.default.removeItem(at: md)
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path), "precondition: таймер пишет копию")

        controller.discardAutorecoverBackup()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertFalse(FileManager.default.fileExists(atPath: json.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: md.path))
    }
}
