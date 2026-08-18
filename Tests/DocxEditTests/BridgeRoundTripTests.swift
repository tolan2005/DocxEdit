//
//  BridgeRoundTripTests.swift
//  DocxEditTests
//
//  Headless-тесты моста DocumentModel ↔ NSAttributedString.
//  Не требует NSTextView/окна — только модель и attributed string.
//  Ловит рассинхроны, которые не видны round-trip через DocxIO.
//

import XCTest
import AppKit
@testable import DocxCore
@testable import DocxEdit

final class BridgeRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func doc(_ blocks: Block...) -> DocumentModel {
        DocumentModel(sections: [DocumentSection(blocks: blocks)])
    }

    private func para(_ runs: Run..., attrs: ParagraphAttributes = .init()) -> Block {
        .paragraph(Paragraph(runs: runs, attributes: attrs))
    }

    private func run(_ text: String, _ ca: CharacterAttributes = .init()) -> Run {
        Run(text: text, attributes: ca)
    }

    private func roundTrip(_ m: DocumentModel) -> DocumentModel {
        DocumentModel.from(attributed: m.toAttributedString())
    }

    private func paragraphs(_ m: DocumentModel) -> [Paragraph] {
        m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
    }

    // MARK: - Базовые атрибуты рана

    func testPlainTextSurvives() {
        let m = doc(para(run("Привет, мир!")))
        let r = roundTrip(m)
        XCTAssertEqual(paragraphs(r).first?.runs.map(\.text).joined(), "Привет, мир!")
    }

    func testBoldItalicUnderlineStrikethrough() {
        let attrs = CharacterAttributes(bold: true, italic: true,
                                       underline: .single, strikethrough: true)
        let r = roundTrip(doc(para(run("x", attrs))))
        let got = paragraphs(r).first?.runs.first?.attributes
        XCTAssertEqual(got?.bold, true)
        XCTAssertEqual(got?.italic, true)
        XCTAssertEqual(got?.underline, .single)
        XCTAssertEqual(got?.strikethrough, true)
    }

    func testFontSizeSurvives() {
        let r = roundTrip(doc(para(run("x", CharacterAttributes(fontSize: 24)))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.fontSize, 24)
    }

    func testTextColorSurvives() {
        let c = CodableColor.fromHex("#FF0000")!
        let r = roundTrip(doc(para(run("x", CharacterAttributes(textColor: c)))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.textColor?.hexString, "#FF0000")
    }

    func testHighlightColorSurvives() {
        let c = CodableColor.fromHex("#FFFF00")!
        let r = roundTrip(doc(para(run("x", CharacterAttributes(highlightColor: c)))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.highlightColor?.hexString, "#FFFF00")
    }

    // MARK: - Кастомные NSAttributedString-ключи (мост-специфичные)

    func testParagraphStyleIdSurvives() {
        var attrs = ParagraphAttributes()
        attrs.styleId = "Heading1"
        let r = roundTrip(doc(para(run("Глава"), attrs: attrs)))
        XCTAssertEqual(paragraphs(r).first?.attributes.styleId, "Heading1")
    }

    func testCharacterStyleIdSurvives() {
        var ca = CharacterAttributes()
        ca.styleId = "Strong"
        let r = roundTrip(doc(para(run("x", ca))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.styleId, "Strong")
    }

    // MARK: - Параграф-стиль (выравнивание, интервалы)

    func testAlignmentSurvives() {
        for a in [DocxCore.TextAlignment.left, .center, .right, .justify] {
            var pa = ParagraphAttributes()
            pa.alignment = a
            let r = roundTrip(doc(para(run("x"), attrs: pa)))
            XCTAssertEqual(paragraphs(r).first?.attributes.alignment, a, "alignment=\(a)")
        }
    }

    func testLineSpacingSurvives() {
        // Мост нормализует именованные варианты в .multiple(x) — это ок
        // (значение сохраняется), проверяем по числовому эквиваленту.
        func multiplier(_ ls: LineSpacing) -> CGFloat {
            switch ls {
            case .single: return 1.0
            case .onePoint15: return 1.15
            case .onePoint5: return 1.5
            case .double: return 2.0
            case .multiple(let v): return v
            case .exact(let v): return v
            case .atLeast(let v): return v
            }
        }
        for ls in [LineSpacing.single, .onePoint15, .onePoint5, .double] {
            var pa = ParagraphAttributes()
            pa.lineSpacing = ls
            let r = roundTrip(doc(para(run("x"), attrs: pa)))
            let got = paragraphs(r).first?.attributes.lineSpacing ?? .single
            XCTAssertEqual(Double(multiplier(got)), Double(multiplier(ls)),
                           accuracy: 0.01, "lineSpacing=\(ls)")
        }
    }

    func testIndentSurvives() {
        var pa = ParagraphAttributes()
        pa.leftIndent = 36
        pa.rightIndent = 18
        pa.firstLineIndent = 12
        let r = roundTrip(doc(para(run("x"), attrs: pa)))
        let got = paragraphs(r).first?.attributes
        XCTAssertEqual(Double(got?.leftIndent ?? -1), 36, accuracy: 0.5)
        XCTAssertEqual(Double(got?.rightIndent ?? -1), 18, accuracy: 0.5)
        XCTAssertEqual(Double(got?.firstLineIndent ?? -1), 12, accuracy: 0.5)
    }

    // MARK: - Списки — уровни через headIndent

    func testListLevelEncodedInHeadIndent() {
        for level in 0...8 {
            let (head, _) = listIndent(forLevel: level)
            let back = listLevel(fromHeadIndent: head)
            XCTAssertEqual(back, level, "level round-trip level=\(level) head=\(head)")
        }
    }

    // MARK: - Таб-стопы (v1.5.4)

    func testTabStopsSurviveBridge() {
        var pa = ParagraphAttributes()
        pa.tabStops = [TabStop(position: 100, alignment: .left),
                       TabStop(position: 250, alignment: .right)]
        let r = roundTrip(doc(para(run("a\tb"), attrs: pa)))
        let got = paragraphs(r).first?.attributes.tabStops ?? []
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(Double(got.first?.position ?? -1), 100, accuracy: 0.5)
        XCTAssertEqual(got.last?.alignment, .right)
    }

    func testDefaultTabStopsNotRecorded() {
        // Абзац без пользовательских табов не должен получать в модель
        // 12 дефолтных стопов NSParagraphStyle.
        let r = roundTrip(doc(para(run("plain"))))
        let got = paragraphs(r).first?.attributes.tabStops ?? []
        XCTAssertTrue(got.isEmpty, "дефолтные таб-стопы не должны писаться в модель: \(got)")
    }

    // MARK: - Границы абзаца (v1.5.5)

    func testParagraphBorderSurvivesBridge() {
        var pa = ParagraphAttributes()
        pa.border = ParagraphBorder(bottom: true, width: 2.0)
        let r = roundTrip(doc(para(run("x"), attrs: pa)))
        let b = paragraphs(r).first?.attributes.border
        XCTAssertNotNil(b)
        XCTAssertTrue(b?.bottom ?? false)
        XCTAssertEqual(Double(b?.width ?? -1), 2.0, accuracy: 0.01)
    }

    // MARK: - Пустой документ и краевые случаи

    func testEmptyDocumentSurvives() {
        let m = DocumentModel(sections: [DocumentSection(blocks: [])])
        let attributed = m.toAttributedString()
        XCTAssertEqual(attributed.length, 0)
        let back = DocumentModel.from(attributed: attributed)
        XCTAssertNotNil(back)
    }

    func testEmptyParagraphSurvives() {
        let m = doc(.paragraph(.empty))
        let attributed = m.toAttributedString()
        XCTAssertGreaterThanOrEqual(attributed.length, 0)
        let back = DocumentModel.from(attributed: attributed)
        XCTAssertGreaterThanOrEqual(back.sections.count, 1)
    }

    func testMultipleParagraphs() {
        let m = doc(
            para(run("first")),
            para(run("second")),
            para(run("third"))
        )
        let r = roundTrip(m)
        let texts = paragraphs(r).map { $0.runs.map(\.text).joined() }
        XCTAssertEqual(texts, ["first", "second", "third"])
    }

    // MARK: - Комбинации атрибутов

    func testCombinedAttributes() {
        let ca = CharacterAttributes(
            fontName: "Helvetica", fontSize: 20,
            bold: true, italic: true,
            underline: .single,
            textColor: CodableColor.fromHex("#00FF00")!
        )
        let r = roundTrip(doc(para(run("combo", ca))))
        let got = paragraphs(r).first?.runs.first?.attributes
        XCTAssertEqual(got?.bold, true)
        XCTAssertEqual(got?.italic, true)
        XCTAssertEqual(got?.underline, .single)
        XCTAssertEqual(got?.fontSize, 20)
        XCTAssertEqual(got?.textColor?.hexString, "#00FF00")
    }

    func testMixedRunsInParagraph() {
        let m = doc(para(
            run("bold ", CharacterAttributes(bold: true)),
            run("italic ", CharacterAttributes(italic: true)),
            run("plain")
        ))
        let r = roundTrip(m)
        let runs = paragraphs(r).first?.runs ?? []
        let joined = runs.map(\.text).joined()
        XCTAssertTrue(joined.contains("bold"))
        XCTAssertTrue(joined.contains("italic"))
        XCTAssertTrue(joined.contains("plain"))
        XCTAssertTrue(runs.contains { $0.attributes.bold == true && $0.text.contains("bold") })
        XCTAssertTrue(runs.contains { $0.attributes.italic == true && $0.text.contains("italic") })
    }

    // MARK: - Fallback шрифт (ADR-024)

    func testFallbackFontUsedForMissingFont() {
        let ca = CharacterAttributes(fontName: "ThisFontDoesNotExist_Zzz", fontSize: 14)
        let attrs = ca.nsAttributes(defaultFont: NSFont.systemFont(ofSize: 12),
                                    fallbackFontName: "Helvetica")
        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertEqual(Double(font?.pointSize ?? 0), 14, accuracy: 0.1)
        XCTAssertEqual(font?.familyName, "Helvetica")
    }

    func testDefaultFontFallbackWhenNoFallbackProvided() {
        let ca = CharacterAttributes(fontName: "ThisFontDoesNotExist_Zzz", fontSize: 14)
        let attrs = ca.nsAttributes(defaultFont: NSFont.systemFont(ofSize: 12))
        XCTAssertNotNil(attrs[.font])
    }

    // MARK: - Маркер списка — обратный разбор паттерна (ADR-026 п.4)

    func testListMarkerPrefixDetectedForBullet() {
        let bullet = DocxCore.ListFormatStyle.bullet(character: "•")
        let text = listMarkerText(for: bullet, counters: [1])
        XCTAssertFalse(text.isEmpty)
        let prefix = listMarkerPrefixLength(in: text + "content", for: bullet)
        XCTAssertEqual(prefix, text.count, "prefix должен указывать на длину маркера")
    }

    func testListMarkerPrefixDetectedForDecimal() {
        let dec = DocxCore.ListFormatStyle.decimal
        let text = listMarkerText(for: dec, counters: [1])
        let prefix = listMarkerPrefixLength(in: text + "item", for: dec)
        XCTAssertEqual(prefix, text.count)
    }

    // MARK: - Стабильность повторных раундтрипов

    func testStabilityAcrossRepeatedRoundTrips() {
        var m = doc(para(run("stable", CharacterAttributes(bold: true))))
        for _ in 0..<10 {
            m = DocumentModel.from(attributed: m.toAttributedString())
        }
        XCTAssertEqual(paragraphs(m).first?.runs.first?.attributes.bold, true)
        XCTAssertEqual(paragraphs(m).first?.runs.first?.text, "stable")
    }

    // MARK: - Sub/Superscript (v0.1.77)

    func testSuperscriptSurvives() {
        let r = roundTrip(doc(para(run("x", CharacterAttributes(superscript: true)))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.superscript, true)
    }

    func testSubscriptSurvives() {
        let r = roundTrip(doc(para(run("x", CharacterAttributes(subscript: true)))))
        XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.subscript, true)
    }

    // MARK: - Сноски (v0.5.3, R07)

    func testFootnoteIdSurvivesBridgeRoundTrip() {
        let m = doc(para(
            run("текст"),
            Run(text: "", attributes: .init(), footnoteId: "1")
        ))
        let r = roundTrip(m)
        let runs = paragraphs(r).flatMap { $0.runs }
        let ids = runs.map { $0.footnoteId ?? "nil" }
        XCTAssertTrue(runs.contains { $0.footnoteId == "1" },
                      "footnoteId потерян: \(ids)")
    }

    func testFootnoteAnchorNotMergedWithText() {
        // Мост не должен склеивать footnote-якорь с соседним текстовым раном.
        let m = doc(para(
            run("A"),
            Run(text: "", attributes: .init(), footnoteId: "1"),
            run("B")
        ))
        let r = roundTrip(m)
        let runs = paragraphs(r).flatMap { $0.runs }
        // Должно быть минимум 2 раза встретиться: один с fid и хотя бы один без.
        XCTAssertTrue(runs.contains { $0.footnoteId == "1" })
        XCTAssertTrue(runs.contains { $0.footnoteId == nil && !$0.text.isEmpty })
    }

    // MARK: - Underline вариации

    func testUnderlineVariations() {
        for s in [UnderlineStyle.single, .double, .dotted, .dashed] {
            let r = roundTrip(doc(para(run("x", CharacterAttributes(underline: s)))))
            XCTAssertEqual(paragraphs(r).first?.runs.first?.attributes.underline, s,
                           "underline=\(s)")
        }
    }
}
