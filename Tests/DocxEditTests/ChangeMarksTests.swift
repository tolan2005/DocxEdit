import XCTest
import AppKit
@testable import DocxEdit

final class ChangeMarksTests: XCTestCase {
    func testDiskChangeMarksAddedChangedDeleted() {
        var m = ChangeMarks()
        m.applyDiskChange(old: "a\nb\nc\nd", new: "a\nB\nc\nnew\n")
        // b → B изменена, d удалена/заменена на new и пустую строку.
        XCTAssertEqual(m.lines[1], .changed)
        XCTAssertNil(m.lines[0]); XCTAssertNil(m.lines[2])
        XCTAssertEqual(m.lines[3], .changed)
        var m2 = ChangeMarks()
        m2.applyDiskChange(old: "a\nb", new: "a\nx\nb")
        XCTAssertEqual(m2.lines, [1: .added])
        var m3 = ChangeMarks()
        m3.applyDiskChange(old: "a\nb\nc", new: "a\nc")
        XCTAssertEqual(m3.deletedBefore, [1])
        XCTAssertTrue(m3.lines.isEmpty)
    }

    /// Отметки копятся через несколько правок и сдвигаются.
    func testMarksAccumulateAndShift() {
        var m = ChangeMarks()
        m.applyDiskChange(old: "a\nb\nc", new: "a\nb\nc\nd")
        XCTAssertEqual(m.lines, [3: .added])
        m.applyDiskChange(old: "a\nb\nc\nd", new: "top\na\nb\nc\nd")
        XCTAssertEqual(m.lines, [0: .added, 4: .added])
        XCTAssertEqual(m.groupStarts, [0, 4])
    }

    /// Своя правка снимает отметку в своей строке и сдвигает остальные.
    func testOwnEditClearsAndShifts() {
        var m = ChangeMarks()
        m.applyDiskChange(old: "a\nb\nc", new: "a\nB\nc\nD")
        XCTAssertEqual(m.lines, [1: .changed, 3: .added])
        m.applyOwnEdit(old: "a\nB\nc\nD", new: "a\nBx\ny\nc\nD")
        XCTAssertEqual(m.lines, [4: .added])
    }

    /// Счётчик в статусной строке ведёт к следующему изменённому месту по кругу.
    @MainActor
    func testGoToNextChange() {
        let session = DocumentSession()
        let controller = DocumentController()
        controller.attach(session: session)
        let md = NSTextView(frame: .zero)
        md.string = "a\nb\nc\nd"
        controller.markdownTextView = md
        session.changeMarks.lines = [1: .changed, 3: .added]
        controller.goToNextChange()
        XCTAssertEqual(md.selectedRange().location, 2)   // строка «b»
        controller.goToNextChange()
        XCTAssertEqual(md.selectedRange().location, 6)   // строка «d»
        controller.goToNextChange()
        XCTAssertEqual(md.selectedRange().location, 2)   // по кругу
    }
}
