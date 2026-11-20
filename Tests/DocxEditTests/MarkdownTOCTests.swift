import XCTest
import AppKit
@testable import DocxEdit

@MainActor
final class MarkdownTOCTests: XCTestCase {
    private func textView(_ s: String) -> NSTextView {
        let tv = NSTextView(usingTextLayoutManager: false); tv.string = s; return tv
    }

    func testInsertAtCaret() {
        let tv = textView("\n# Введение\n## Цели проекта\n```\n# не заголовок\n```\n")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(MarkdownEditing.insertOrUpdateTOC(tv))
        XCTAssertTrue(tv.string.hasPrefix("<!-- toc -->\n- [Введение](#введение)\n  - [Цели проекта](#цели-проекта)\n<!-- /toc -->\n# Введение"))
    }

    func testUpdateKeepsCaretAndOnlyIfPresent() {
        let tv = textView("Текст\n# A\n")
        XCTAssertFalse(MarkdownEditing.insertOrUpdateTOC(tv, insertIfMissing: false))
        XCTAssertEqual(tv.string, "Текст\n# A\n")

        let tv2 = textView("<!-- toc -->\n- [Old](#old)\n<!-- /toc -->\n# A\n# B\nконец")
        let caret = (tv2.string as NSString).range(of: "конец").location
        tv2.setSelectedRange(NSRange(location: caret, length: 0))
        MarkdownEditing.insertOrUpdateTOC(tv2, insertIfMissing: false)
        XCTAssertTrue(tv2.string.hasPrefix("<!-- toc -->\n- [A](#a)\n- [B](#b)\n<!-- /toc -->"))
        XCTAssertEqual(tv2.selectedRange().location, (tv2.string as NSString).range(of: "конец").location)
    }
}
