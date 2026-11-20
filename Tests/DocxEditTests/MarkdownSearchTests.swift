import XCTest
import AppKit
@testable import DocxEdit

/// Поиск и замена в Markdown (гибрид/исходник) идут по редактору исходника.
@MainActor
final class MarkdownSearchTests: XCTestCase {
    func testSearchUsesMarkdownEditor() {
        let session = DocumentSession()
        session.mode = .markdown
        let controller = DocumentController()
        controller.attach(session: session)
        session.isMarkdownSourceMode = true
        let md = NSTextView(frame: .zero)
        md.string = "кот и ещё кот"
        controller.markdownTextView = md
        let opts = DocumentController.SearchOptions(useRegex: false, caseSensitive: false, wholeWord: false)
        XCTAssertTrue(controller.searchTextView === md)
        XCTAssertEqual(controller.countMatches(pattern: "кот", options: opts), 2)
        XCTAssertTrue(controller.findNext(pattern: "кот", options: opts))
        XCTAssertEqual(md.selectedRange(), NSRange(location: 0, length: 3))
        XCTAssertEqual(controller.replaceAll(pattern: "кот", replacement: "пёс", options: opts), 2)
        XCTAssertEqual(md.string, "пёс и ещё пёс")
    }
}
