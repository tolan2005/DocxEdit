import XCTest
import AppKit
@testable import DocxEdit
@testable import DocxCore

/// v1.6.0: подсветка синтаксиса Markdown (MarkdownSyntaxHighlighter).
final class MarkdownHighlighterTests: XCTestCase {

    private let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private func highlighted(_ md: String) -> NSTextStorage {
        let storage = NSTextStorage(string: md)
        MarkdownSyntaxHighlighter.highlight(storage, baseFont: baseFont)
        return storage
    }

    private func color(at loc: Int, in s: NSTextStorage) -> NSColor? {
        s.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? NSColor
    }

    func testHeadingColoredAndBold() {
        let s = highlighted("# Заголовок\nтекст")
        XCTAssertEqual(color(at: 0, in: s), .systemBlue)
        let f = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(f?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testCodeFenceDimmed() {
        let s = highlighted("```swift\nlet x = 1\n```\nпосле")
        XCTAssertEqual(color(at: 2, in: s), .secondaryLabelColor)
        XCTAssertNotNil(s.attribute(.backgroundColor, at: 12, effectiveRange: nil))
    }

    func testListMarkerOrange() {
        let s = highlighted("- первый\n1. второй")
        XCTAssertEqual(color(at: 0, in: s), .systemOrange)
    }

    func testLinkIndigo() {
        let s = highlighted("смотри [сайт](https://example.com) тут")
        let linkLoc = (s.string as NSString).range(of: "[сайт]").location
        XCTAssertEqual(color(at: linkLoc, in: s), .systemIndigo)
    }

    func testBlockquoteGreen() {
        let s = highlighted("> цитата\nтекст")
        XCTAssertEqual(color(at: 0, in: s), .systemGreen)
    }

    @MainActor
    func testSourceModeSessionRoundTrip() {
        // Сессия: вход в исходный режим экспортирует модель в MD, правка
        // исходника обновляет модель (best-effort), выход — визуальный режим.
        let session = DocumentSession()
        session.mode = .markdown
        var p = ParagraphAttributes()
        p.styleId = "Heading1"
        session.bridge.replaceModel(DocumentModel(sections: [
            DocumentSection(blocks: [
                .paragraph(Paragraph(runs: [Run(text: "Тест", attributes: .init())],
                                     attributes: p)),
            ]),
        ]))
        session.enterMarkdownSourceMode()
        XCTAssertTrue(session.isMarkdownSourceMode)
        XCTAssertTrue(session.markdownSource.contains("# Тест"),
                      "экспорт MD должен содержать заголовок: \(session.markdownSource)")
        session.applyMarkdownSource(session.markdownSource + "\n\nНовая строка\n")
        let texts = session.bridge.model.sections.flatMap { $0.blocks }.compactMap { b -> String? in
            if case .paragraph(let pp) = b { return pp.runs.map(\.text).joined() }
            return nil
        }.joined()
        XCTAssertTrue(texts.contains("Новая строка"), "модель не синхронизировалась: \(texts)")
        session.exitMarkdownSourceMode()
        XCTAssertFalse(session.isMarkdownSourceMode)
        XCTAssertGreaterThan(session.attributedText.length, 0)
    }
}
