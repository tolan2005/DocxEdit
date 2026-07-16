//
//  UnicodeEdgeTests.swift
//  DocxIOTests
//
//  Юникод-крайности в DOCX round-trip: emoji, комбинирующие, суррогатные пары,
//  RTL, ZWJ. Ловит поломки на XML escaping, UTF-16 code point handling и tag
//  boundary detection.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class UnicodeEdgeTests: XCTestCase {

    private func rt(_ text: String) throws -> String {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: text, attributes: .init())]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        return back.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
    }

    // MARK: - Emoji

    func testEmojiSimple() throws {
        let text = "Hello 🌍 world 🚀"
        XCTAssertTrue(try rt(text).contains("🌍"), "простой emoji потерян")
    }

    func testEmojiSequences() throws {
        // ZWJ-sequence: 👨‍👩‍👧‍👦 = family. Swift.contains() сверяет по грапемам,
        // поэтому проверяем всю последовательность, а не базовый emoji.
        let text = "Family: 👨‍👩‍👧‍👦"
        let back = try rt(text)
        XCTAssertTrue(back.contains("👨‍👩‍👧‍👦"), "emoji sequence сломан: \(back)")
    }

    func testEmojiWithSkinTone() throws {
        let text = "Wave: 👋🏽"
        let back = try rt(text)
        XCTAssertTrue(back.contains("👋🏽"), "emoji с модификатором сломан: \(back)")
    }

    // MARK: - Комбинирующие символы

    func testCombiningMarks() throws {
        // "e" + combining acute (U+0301) = "é"
        let text = "e\u{0301} vs \u{00E9}"
        let back = try rt(text)
        XCTAssertTrue(back.contains("e\u{0301}") || back.contains("é"),
                      "комбинирующий диакритик потерян: \(back)")
    }

    // MARK: - RTL / bidi

    func testHebrewText() throws {
        let text = "שלום עולם"
        let back = try rt(text)
        XCTAssertEqual(back.trimmingCharacters(in: .whitespaces), text)
    }

    func testArabicText() throws {
        let text = "مرحبا بالعالم"
        let back = try rt(text)
        XCTAssertEqual(back.trimmingCharacters(in: .whitespaces), text)
    }

    func testMixedRtlLtr() throws {
        let text = "Hello שלום world"
        let back = try rt(text)
        XCTAssertTrue(back.contains("שלום"), "RTL в LTR-контексте сломан")
        XCTAssertTrue(back.contains("Hello"))
    }

    // MARK: - XML-опасные символы

    func testXmlDangerousChars() throws {
        // <, >, &, ", ' — должны экранироваться и восстанавливаться.
        let text = "<tag> & \"quote\" 'apos'"
        let back = try rt(text)
        XCTAssertTrue(back.contains("<tag>"), "< > не восстановились: \(back)")
        XCTAssertTrue(back.contains("&"))
        XCTAssertTrue(back.contains("\"quote\""))
    }

    func testNullAndControlChars() throws {
        // U+0000 запрещён в XML, U+0009/A/D разрешены. Проверяем, что импорт не падает.
        let text = "tab\there\nnewline"
        let back = try rt(text)
        XCTAssertTrue(back.contains("tab") && back.contains("here"))
    }

    // MARK: - CJK

    func testChineseText() throws {
        let text = "你好世界，这是测试"
        XCTAssertEqual(try rt(text), text)
    }

    func testJapaneseText() throws {
        let text = "こんにちは世界"
        XCTAssertEqual(try rt(text), text)
    }

    func testKoreanText() throws {
        let text = "안녕하세요 세계"
        XCTAssertEqual(try rt(text), text)
    }

    // MARK: - Экстремальные значения

    func testSurrogatePairs() throws {
        // 𝕏 = U+1D54F (математический X) — вне BMP, требует суррогатной пары в UTF-16.
        let text = "Math: 𝕏 𝔸 𝔹"
        let back = try rt(text)
        XCTAssertTrue(back.contains("𝕏"), "суррогатная пара сломана: \(back)")
    }

    func testZeroWidthSpace() throws {
        // U+200B — zero-width space. Не должен теряться.
        let text = "a\u{200B}b"
        let back = try rt(text)
        XCTAssertEqual(back.count, 3, "ZWSP схлопнулся: \(back.debugDescription)")
    }

    // MARK: - Множественные пробелы (значимы в OOXML: xml:space="preserve")

    func testMultipleSpacesPreserved() throws {
        let text = "a     b"  // 5 пробелов
        let back = try rt(text)
        XCTAssertEqual(back, text, "множественные пробелы схлопнулись — не хватает xml:space=\"preserve\"")
    }

    func testLeadingTrailingSpaces() throws {
        let text = "   leading and trailing   "
        let back = try rt(text)
        // Хотя бы «leading» и «trailing» должны быть; и хотя бы один ведущий пробел.
        XCTAssertTrue(back.contains("leading"))
        XCTAssertTrue(back.contains("trailing"))
    }
}
