import XCTest
import AppKit
@testable import DocxEdit

final class MarkdownHybridRendererTests: XCTestCase {
    private let base = NSFont.systemFont(ofSize: 15)

    /// Рендерит текст с курсором в позиции `caret` (по умолчанию — в конце, отдельной строкой).
    private func render(_ text: String, caret: Int? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let ns = text as NSString
        let sel = NSRange(location: caret ?? ns.length, length: 0)
        MarkdownHybridRenderer.render(storage, baseFont: base,
                                      active: MarkdownHybridRenderer.activeRange(in: ns, selection: sel))
        return storage
    }

    private func isHidden(_ s: NSTextStorage, _ at: Int) -> Bool {
        (s.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor) == .clear
    }

    private func font(_ s: NSTextStorage, _ at: Int) -> NSFont {
        s.attribute(.font, at: at, effectiveRange: nil) as! NSFont
    }

    func testHeadingOutsideCaretHidesMarkerAndEnlarges() {
        let s = render("# Заголовок\n\nтекст", caret: 14)
        XCTAssertTrue(isHidden(s, 0))
        XCTAssertTrue(isHidden(s, 1))
        XCTAssertGreaterThan(font(s, 2).pointSize, base.pointSize * 1.5)
        XCTAssertTrue(font(s, 2).fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testHeadingUnderCaretShowsMarker() {
        let s = render("# Заголовок\n\nтекст", caret: 3)
        XCTAssertFalse(isHidden(s, 0))
        XCTAssertGreaterThan(font(s, 2).pointSize, base.pointSize * 1.5)
    }

    func testBoldAndItalicHideMarkers() {
        let s = render("a **жир** и *кур*\n\nx")
        XCTAssertTrue(isHidden(s, 2))
        XCTAssertTrue(isHidden(s, 3))
        XCTAssertTrue(font(s, 4).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(isHidden(s, 7))
        let italicAt = ("a **жир** и *кур*" as NSString).range(of: "кур").location
        XCTAssertTrue(isHidden(s, italicAt - 1))
        XCTAssertTrue(font(s, italicAt).fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testLinkShowsOnlyText() {
        let s = render("см. [сайт](https://example.com)\n\nx")
        let ns = "см. [сайт](https://example.com)" as NSString
        XCTAssertTrue(isHidden(s, ns.range(of: "[").location))
        XCTAssertFalse(isHidden(s, ns.range(of: "сайт").location))
        XCTAssertTrue(isHidden(s, ns.range(of: "https").location))
    }

    func testInlineMarkupInsideCodeBlockIsNotRendered() {
        let src = "```\n**не жир**\n```\n\nx"
        let s = render(src)
        XCTAssertTrue(isHidden(s, 0))
        XCTAssertFalse(isHidden(s, 4))
        XCTAssertTrue(font(s, 6).fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testCaretOnEmptyLastLineDoesNotRevealPreviousParagraph() {
        let src = "a **b** c\n"
        let s = render(src, caret: (src as NSString).length)
        XCTAssertTrue(isHidden(s, 2))
    }

    func testTextIsNeverModified() {
        let src = "# H\n**b** *i* `c` [l](u)\n> q\n---"
        XCTAssertEqual(render(src).string, src)
    }

    private func glyph(_ s: NSTextStorage, _ at: Int) -> String? {
        s.attribute(MarkdownHybridRenderer.glyphKey, at: at, effectiveRange: nil) as? String
    }

    func testBulletRendersAsDotWithHangingIndent() {
        let s = render("- пункт\n  * вложенный\n\nx")
        XCTAssertEqual(glyph(s, 0), "•")
        XCTAssertEqual(glyph(s, ("- пункт\n  " as NSString).length), "•")
        let ps = s.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(ps?.headIndent ?? 0, 0)
    }

    func testTaskItemsRenderAsCheckboxes() {
        let src = "- [ ] купить\n- [x] готово\n\nx"
        let s = render(src)
        XCTAssertTrue(isHidden(s, 0))
        XCTAssertTrue(isHidden(s, 2))
        XCTAssertEqual(glyph(s, 3), "☐")
        XCTAssertNotNil(s.attribute(.link, at: 3, effectiveRange: nil))
        let doneBox = ("- [ ] купить\n- [" as NSString).length
        XCTAssertEqual(glyph(s, doneBox), "☑")
        let doneText = (src as NSString).range(of: "готово").location
        XCTAssertNotNil(s.attribute(.strikethroughStyle, at: doneText, effectiveRange: nil))
    }

    func testNumberedListGetsHangingIndentAndNoGlyph() {
        let s = render("1. первый\n2. второй\n\nx")
        XCTAssertNil(glyph(s, 0))
        let ps = s.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(ps?.headIndent ?? 0, 0)
    }

    func testHorizontalRuleIsNotABullet() {
        XCTAssertNil(glyph(render("---\n\nx"), 0))
    }

    func testHorizontalRuleBecomesLineOutsideCaret() {
        let s = render("---\n\nx")
        XCTAssertNotNil(s.attribute(MarkdownHybridRenderer.ruleKey, at: 0, effectiveRange: nil))
        XCTAssertTrue(isHidden(s, 0))
        XCTAssertNil(render("---\n\nx", caret: 1).attribute(MarkdownHybridRenderer.ruleKey, at: 0, effectiveRange: nil))
    }
}

final class MarkdownHybridImageTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let img = NSImage(size: NSSize(width: 200, height: 100))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill(); img.unlockFocus()
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("pic.png"))
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: dir) }

    private func render(_ text: String, caret: Int) -> NSTextStorage {
        let s = NSTextStorage(string: text)
        MarkdownHybridRenderer.render(s, baseFont: .systemFont(ofSize: 15),
            active: MarkdownHybridRenderer.activeRange(in: text as NSString, selection: NSRange(location: caret, length: 0)),
            baseURL: dir, maxImageWidth: 100)
        return s
    }

    func testImageLineHiddenAndHeightReserved() {
        let src = "![картинка](pic.png)\n\nx"
        let s = render(src, caret: (src as NSString).length)
        XCTAssertNotNil(s.attribute(MarkdownHybridRenderer.imageKey, at: 0, effectiveRange: nil))
        let altAt = (src as NSString).range(of: "картинка").location
        XCTAssertEqual(s.attribute(.foregroundColor, at: altAt, effectiveRange: nil) as? NSColor, .clear)
        let ps = s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.minimumLineHeight ?? 0, 50, accuracy: 0.5)   // 200×100 → ширина 100
    }

    func testImageUnderCaretShowsMarkup() {
        let s = render("![картинка](pic.png)\n\nx", caret: 2)
        XCTAssertNil(s.attribute(MarkdownHybridRenderer.imageKey, at: 0, effectiveRange: nil))
    }

    func testMissingOrRemoteImageStaysText() {
        let src = "![a](nope.png)\n![b](https://example.com/x.png)\n\nx"
        let s = render(src, caret: (src as NSString).length)
        XCTAssertNil(s.attribute(MarkdownHybridRenderer.imageKey, at: 0, effectiveRange: nil))
        XCTAssertNil(s.attribute(MarkdownHybridRenderer.imageKey, at: 16, effectiveRange: nil))
    }
}

final class MarkdownHybridTableTests: XCTestCase {
    private let src = "| Имя | **Кол-во** |\n|:---|---:|\n| яблоко | 3 |\n| груша | 12 |\n\nx"

    private func render(caret: Int) -> NSTextStorage {
        let s = NSTextStorage(string: src)
        MarkdownHybridRenderer.render(s, baseFont: .systemFont(ofSize: 15),
            active: MarkdownHybridRenderer.activeRange(in: src as NSString, selection: NSRange(location: caret, length: 0)))
        return s
    }

    func testTableOutsideCaretIsParsedAndHidden() throws {
        let s = render(caret: (src as NSString).length)
        let table = try XCTUnwrap(s.attribute(MarkdownHybridRenderer.tableKey, at: 0, effectiveRange: nil)
                                  as? MarkdownHybridRenderer.MarkdownTable)
        XCTAssertEqual(table.rows, [["Имя", "Кол-во"], ["яблоко", "3"], ["груша", "12"]])
        XCTAssertEqual(table.alignments, [.left, .right])
        XCTAssertEqual(s.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, .clear)
        let rowLine = s.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(rowLine?.minimumLineHeight ?? 0, table.rowHeight, accuracy: 0.01)
        let sepAt = (src as NSString).range(of: "|:---").location
        let sepLine = s.attribute(.paragraphStyle, at: sepAt, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertLessThan(sepLine?.maximumLineHeight ?? 99, 1)
    }

    func testTableUnderCaretShowsMarkdown() {
        let s = render(caret: (src as NSString).range(of: "груша").location)
        XCTAssertNil(s.attribute(MarkdownHybridRenderer.tableKey, at: 0, effectiveRange: nil))
    }

    func testPipeTextWithoutSeparatorIsNotATable() {
        let s = NSTextStorage(string: "| просто текст |\n\nx")
        MarkdownHybridRenderer.render(s, baseFont: .systemFont(ofSize: 15), active: NSRange(location: 18, length: 0))
        XCTAssertNil(s.attribute(MarkdownHybridRenderer.tableKey, at: 0, effectiveRange: nil))
    }
}
