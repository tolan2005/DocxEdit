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

    func testTextIsNeverModified() {
        let src = "# H\n**b** *i* `c` [l](u)\n> q\n---"
        XCTAssertEqual(render(src).string, src)
    }
}
