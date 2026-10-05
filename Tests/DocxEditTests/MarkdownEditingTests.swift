import XCTest
import AppKit
@testable import DocxEdit

/// v1.10.3: команды ленты в гибридном MD — правка исходника Markdown.
@MainActor
final class MarkdownEditingTests: XCTestCase {
    private func textView(_ text: String, _ sel: NSRange) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = text
        tv.setSelectedRange(sel)
        return tv
    }

    func testWrapAndUnwrapBold() {
        let tv = textView("one two", NSRange(location: 4, length: 3))
        MarkdownEditing.wrap(tv, "**")
        XCTAssertEqual(tv.string, "one **two**")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 3))
        tv.setSelectedRange(NSRange(location: 4, length: 7))
        MarkdownEditing.wrap(tv, "**")
        XCTAssertEqual(tv.string, "one two")
    }

    func testToggleBulletListOnSelectedLines() {
        let tv = textView("a\nb\nc", NSRange(location: 0, length: 3))
        MarkdownEditing.toggleList(tv, numbered: false)
        XCTAssertEqual(tv.string, "- a\n- b\nc")
        MarkdownEditing.toggleList(tv, numbered: false)
        XCTAssertEqual(tv.string, "a\nb\nc")
    }

    func testNumberedListReplacesBullets() {
        let tv = textView("- a\n- b\n", NSRange(location: 0, length: 0))
        tv.setSelectedRange(NSRange(location: 0, length: 7))
        MarkdownEditing.toggleList(tv, numbered: true)
        XCTAssertEqual(tv.string, "1. a\n2. b\n")
    }

    func testHeadingReplacesExistingLevel() {
        let tv = textView("## Title\ntext", NSRange(location: 3, length: 0))
        MarkdownEditing.setHeading(tv, level: 1)
        XCTAssertEqual(tv.string, "# Title\ntext")
        MarkdownEditing.setHeading(tv, level: 0)
        XCTAssertEqual(tv.string, "Title\ntext")
    }

    func testIndentAndOutdent() {
        let tv = textView("- a", NSRange(location: 2, length: 0))
        MarkdownEditing.indent(tv, increase: true)
        XCTAssertEqual(tv.string, "  - a")
        MarkdownEditing.indent(tv, increase: false)
        XCTAssertEqual(tv.string, "- a")
    }

    func testLinkSelectsUrlPlaceholder() {
        let tv = textView("see docs", NSRange(location: 4, length: 4))
        MarkdownEditing.insertLink(tv)
        XCTAssertEqual(tv.string, "see [docs](https://)")
        XCTAssertEqual((tv.string as NSString).substring(with: tv.selectedRange()), "https://")
    }

    func testTableStartsOnNewLine() {
        let tv = textView("abc", NSRange(location: 3, length: 0))
        MarkdownEditing.insertTable(tv)
        XCTAssertTrue(tv.string.hasPrefix("abc\n| Столбец 1 |"))
    }

    func testParagraphStylesFromMenu() {
        let tv = textView("line", NSRange(location: 0, length: 0))
        MarkdownEditing.applyParagraphStyle(tv, id: "Quote")
        XCTAssertEqual(tv.string, "> line")
        MarkdownEditing.applyParagraphStyle(tv, id: "Normal")
        XCTAssertEqual(tv.string, "line")
        MarkdownEditing.applyParagraphStyle(tv, id: "Heading3")
        XCTAssertEqual(tv.string, "### line")
        MarkdownEditing.applyParagraphStyle(tv, id: "CodeBlock")
        XCTAssertEqual(tv.string, "```\n### line\n```")
    }
}
