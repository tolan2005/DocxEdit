import XCTest
@testable import DocxEdit

/// v1.10.7: когда автосохранение пишет в файл.
final class AutoSaveTests: XCTestCase {
    func testOnlySavedDocxOrMarkdownWithChanges() {
        let docx = URL(fileURLWithPath: "/tmp/a.docx"), md = URL(fileURLWithPath: "/tmp/b.MD")
        XCTAssertTrue(AutoSaveMode.canSave(isDirty: true, url: docx))
        XCTAssertTrue(AutoSaveMode.canSave(isDirty: true, url: md))
        XCTAssertFalse(AutoSaveMode.canSave(isDirty: false, url: docx))      // нечего сохранять
        XCTAssertFalse(AutoSaveMode.canSave(isDirty: true, url: nil))        // новый документ
        XCTAssertFalse(AutoSaveMode.canSave(isDirty: true, url: URL(fileURLWithPath: "/tmp/c.rtf")))
    }

    func testDelays() {
        XCTAssertNil(AutoSaveMode.off.delay)
        XCTAssertEqual(AutoSaveMode.interval.delay, 30)
        XCTAssertEqual(AutoSaveMode.pause.delay, 2)
    }
}
