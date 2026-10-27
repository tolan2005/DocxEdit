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

    func testTabOnListLineInMultilineDocument() {
        // Раньше: NSRangeException (диапазон regex = длина документа, а не строки).
        let tv = textView("intro\n- a\nend", NSRange(location: 9, length: 0))
        XCTAssertTrue(MarkdownEditing.indentListLine(tv, increase: true))
        XCTAssertEqual(tv.string, "intro\n  - a\nend")
        XCTAssertEqual(tv.selectedRange().location, 11)
        XCTAssertTrue(MarkdownEditing.indentListLine(tv, increase: false))
        XCTAssertEqual(tv.string, "intro\n- a\nend")
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertFalse(MarkdownEditing.indentListLine(tv, increase: true))
    }

    func testEnterContinuesListsAndTasks() {
        let tv = textView("1. a", NSRange(location: 4, length: 0))
        XCTAssertTrue(MarkdownEditing.continueList(tv))
        XCTAssertEqual(tv.string, "1. a\n2. ")
        tv.string = "  3) b"; tv.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(MarkdownEditing.continueList(tv))
        XCTAssertEqual(tv.string, "  3) b\n  4) ")
        tv.string = "- [x] done"; tv.setSelectedRange(NSRange(location: 10, length: 0))
        XCTAssertTrue(MarkdownEditing.continueList(tv))
        XCTAssertEqual(tv.string, "- [x] done\n- [ ] ")
    }

    func testEnterOnEmptyItemEndsList() {
        let tv = textView("- a\n- ", NSRange(location: 6, length: 0))
        XCTAssertTrue(MarkdownEditing.continueList(tv))
        XCTAssertEqual(tv.string, "- a\n")
        tv.string = "plain"; tv.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(MarkdownEditing.continueList(tv))
    }

    func testImageFileInsideFolderIsRelativeOutsideIsCopied() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base.appendingPathComponent("pics"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base); try? fm.removeItem(at: outside) }
        let inner = base.appendingPathComponent("pics/a b.png")
        let outer = outside.appendingPathComponent("c.png")
        try Data([1]).write(to: inner); try Data([2]).write(to: outer)

        let tv = textView("", NSRange(location: 0, length: 0))
        MarkdownEditing.insertImageFile(tv, inner, baseURL: base)
        XCTAssertEqual(tv.string, "![a b](pics/a%20b.png)\n")
        MarkdownEditing.insertImageFile(tv, outer, baseURL: base)
        let copied = try fm.contentsOfDirectory(atPath: base.appendingPathComponent("images").path)
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(tv.string.hasSuffix("![c](images/\(copied[0]))\n"))
    }

    func testPastedImageSavedAsPng() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true }
        let tv = textView("x", NSRange(location: 1, length: 0))
        XCTAssertTrue(MarkdownEditing.insertImageData(tv, image, baseURL: base))
        let files = try fm.contentsOfDirectory(atPath: base.appendingPathComponent("images").path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(".png"))
        XCTAssertEqual(tv.string, "x\n![](images/\(files[0]))\n")
    }

    func testCommandShortcutsByKeyCodeOnAnyLayout() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .titled, backing: .buffered, defer: true)
        let tv = MarkdownTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(tv)
        window.makeFirstResponder(tv)
        tv.string = "one two"
        func press(_ code: UInt16, _ chars: String) -> Bool {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: code)!
            return tv.performKeyEquivalent(with: e)
        }
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        XCTAssertTrue(press(11, "и"))            // ⌘B на РУ-раскладке
        XCTAssertEqual(tv.string, "one **two**")
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        XCTAssertTrue(press(34, "ш"))            // ⌘I
        XCTAssertEqual(tv.string, "*one* **two**")
        tv.setSelectedRange(NSRange(location: 1, length: 3))
        XCTAssertTrue(press(40, "л"))            // ⌘K
        XCTAssertEqual(tv.string, "*[one](https://)* **two**")
        XCTAssertFalse(press(0, "ф"))            // ⌘A — не наш
    }

    func testCaretStateReflectsMarkdownUnderCaret() {
        let text = "## Title **bold** *it* ~~x~~\n1. item\n- b\n> q" as NSString
        var st = MarkdownEditing.caretState(text, at: 12)       // внутри **bold**
        XCTAssertTrue(st.bold); XCTAssertFalse(st.italic)
        XCTAssertEqual(st.styleId, "Heading2"); XCTAssertNil(st.list)
        st = MarkdownEditing.caretState(text, at: 20)           // внутри *it*
        XCTAssertTrue(st.italic); XCTAssertFalse(st.bold)
        st = MarkdownEditing.caretState(text, at: 25)           // внутри ~~x~~
        XCTAssertTrue(st.strike)
        st = MarkdownEditing.caretState(text, at: 5)            // Title — без разметки
        XCTAssertFalse(st.bold || st.italic || st.strike)
        XCTAssertEqual(MarkdownEditing.caretState(text, at: 32).list, .numbered)
        XCTAssertEqual(MarkdownEditing.caretState(text, at: 38).list, .bulleted)
        XCTAssertEqual(MarkdownEditing.caretState(text, at: 43).styleId, "Quote")
    }

    func testPasteUrlOverSelectionMakesLink() {
        let tv = textView("see docs here", NSRange(location: 4, length: 4))
        XCTAssertTrue(MarkdownEditing.linkSelection(tv, url: " https://ex.com/a?b=1\n"))
        XCTAssertEqual(tv.string, "see [docs](https://ex.com/a?b=1) here")
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        XCTAssertFalse(MarkdownEditing.linkSelection(tv, url: "just text"))
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(MarkdownEditing.linkSelection(tv, url: "https://ex.com"))
    }

    func testHeadingsForNavigatorSkipCodeBlocks() {
        let md = "# Один\ntext\n```\n# не заголовок\n```\n### Три  \n#без пробела\n##   \n"
        let h = MarkdownEditing.headings(md)
        XCTAssertEqual(h.map(\.text), ["Один", "Три"])
        XCTAssertEqual(h.map(\.level), [1, 3])
        XCTAssertEqual(h.map(\.location), [0, 35])
    }

    func testFormatTableAlignsColumns() {
        let src = "до\n|Имя|Цена|Статус|\n|-|--:|:-:|\n| Яблоко | 5 |ok|\n|a\\|b|120\n\nпосле"
        let tv = textView(src, NSRange(location: 6, length: 0))
        XCTAssertTrue(MarkdownEditing.formatTable(tv))
        XCTAssertEqual(tv.string, """
        до
        | Имя    | Цена | Статус |
        | ------ | ---: | :----: |
        | Яблоко |    5 |   ok   |
        | a\\|b   |  120 |        |

        после
        """)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertFalse(MarkdownEditing.formatTable(tv))
    }

    func testLinkUnderCaretAndResolution() {
        let text = "см. [главу](глава%202.md#итоги) и ![](img/a.png), [сайт](https://ex.com)\n" as NSString
        XCTAssertEqual(MarkdownEditing.link(in: text, at: 6), "глава%202.md#итоги")
        XCTAssertEqual(MarkdownEditing.link(in: text, at: 37), "img/a.png")
        XCTAssertNil(MarkdownEditing.link(in: text, at: 1))
        let base = URL(fileURLWithPath: "/docs")
        XCTAssertEqual(MarkdownEditing.resolveLink("глава%202.md#итоги", baseURL: base),
                       .file(URL(fileURLWithPath: "/docs/глава 2.md")))
        XCTAssertEqual(MarkdownEditing.resolveLink("https://ex.com", baseURL: base), .web(URL(string: "https://ex.com")!))
        XCTAssertEqual(MarkdownEditing.resolveLink("#Итоги-года", baseURL: base), .anchor("Итоги-года"))
        XCTAssertNil(MarkdownEditing.resolveLink("a.md", baseURL: nil))
        XCTAssertEqual(MarkdownEditing.slug("Итоги года: 2026!"), "итоги-года-2026")
    }

    func testPasteSpreadsheetBecomesAlignedTable() {
        XCTAssertNil(MarkdownEditing.markdownTable(fromTSV: "просто текст\nбез табов"))
        XCTAssertNil(MarkdownEditing.markdownTable(fromTSV: "одна\tстрока"))
        let tv = textView("до", NSRange(location: 2, length: 0))
        XCTAssertTrue(MarkdownEditing.pasteTable(tv, tsv: "Имя\tЦена\r\nЯблоко\t5\r\na|b\t\n"))
        XCTAssertEqual(tv.string, """
        до
        | Имя    | Цена |
        | ------ | ---- |
        | Яблоко | 5    |
        | a\\|b   |      |

        """)
    }
}
