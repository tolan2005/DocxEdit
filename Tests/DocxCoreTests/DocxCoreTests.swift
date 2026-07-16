//
//  DocxCoreTests.swift
//  DocxCoreTests
//
//  Базовые тесты модуля DocxCore.
//

import XCTest
@testable import DocxCore
import EncodingDetector

final class DocxCoreTests: XCTestCase {

    func testEmptyDocument() {
        let doc = DocumentModel()
        XCTAssertEqual(doc.sections.count, 1)
        XCTAssertEqual(doc.paragraphCount, 1) // один пустой параграф
    }

    func testPlainText() {
        let p = Paragraph(runs: [
            Run(text: "Hello, "),
            Run(text: "world!", attributes: CharacterAttributes(bold: true)),
        ])
        let doc = DocumentModel(sections: [DocumentSection(blocks: [.paragraph(p)])])
        XCTAssertEqual(doc.plainText, "Hello, world!\n")
    }

    func testWordCount() {
        let p = Paragraph(runs: [Run(text: "one two three four")])
        XCTAssertEqual(DocumentStatisticsCalculator.countWords(in: p.runs[0].text), 4)
    }

    func testPageSettingsA4() {
        let s = PageSettings.a4Portrait
        XCTAssertEqual(s.paperSize, .a4)
        XCTAssertEqual(s.orientation, .portrait)
        XCTAssertEqual(s.pageSizeInPoints.width, 595, accuracy: 0.5)
        XCTAssertEqual(s.pageSizeInPoints.height, 842, accuracy: 0.5)
    }

    func testPageSettingsLandscape() {
        let s = PageSettings(paperSize: .a4, orientation: .landscape, margins: .standard)
        XCTAssertEqual(s.pageSizeInPoints.width, 842, accuracy: 0.5)
        XCTAssertEqual(s.pageSizeInPoints.height, 595, accuracy: 0.5)
    }

    func testColorFromHex() {
        let color = CodableColor.fromHex("#FF0000")
        XCTAssertNotNil(color)
        XCTAssertEqual(Double(color?.red ?? 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(color?.green ?? 0), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(color?.blue ?? 0), 0.0, accuracy: 0.01)
    }

    func testCharacterAttributesMerger() {
        var a = CharacterAttributes(bold: true)
        a = a.merged(with: CharacterAttributes(italic: true))
        XCTAssertTrue(a.bold)
        XCTAssertTrue(a.italic)
    }

    func testEncodingDetector_UTF8() {
        let s = "Привет, мир!"
        let data = s.data(using: .utf8)!
        let enc = EncodingDetector.detect(data: data)
        XCTAssertTrue(enc == .utf8 || enc == .utf8BOM, "Expected UTF-8, got \(enc.name)")
    }

    func testEncodingDetector_UTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("Hello".data(using: .utf8)!)
        let enc = EncodingDetector.detect(data: data)
        XCTAssertEqual(enc, .utf8BOM)
    }

    func testEncodingDetector_Windows1251() {
        let s = "Привет, мир!"
        guard let data = s.data(using: .windowsCP1251) else {
            XCTFail("Windows-1251 encoding unavailable")
            return
        }
        let enc = EncodingDetector.detect(data: data)
        XCTAssertEqual(enc, .windows1251)
    }

    func testEncodingDetector_ASCII() {
        let s = "Hello, world!"
        let data = s.data(using: .ascii)!
        let enc = EncodingDetector.detect(data: data)
        XCTAssertTrue(enc == .ascii || enc == .utf8, "Expected ASCII/UTF-8, got \(enc.name)")
    }

    func testRoundTrip() {
        let s = "Hello, мир!"
        let data = s.data(using: .utf8)!
        let enc = EncodingDetector.detect(data: data)
        let decoded = EncodingDetector.decode(data, using: enc)
        XCTAssertEqual(decoded, s)
    }

    // Расширенное покрытие детектора (2026-07-13).

    func testEncodingDetector_UTF16LE_BOM() {
        var data = Data([0xFF, 0xFE])  // BOM UTF-16LE
        data.append("Hello".data(using: .utf16LittleEndian)!)
        let enc = EncodingDetector.detect(data: data)
        XCTAssertEqual(enc, .utf16LE)
    }

    func testEncodingDetector_UTF16BE_BOM() {
        var data = Data([0xFE, 0xFF])  // BOM UTF-16BE
        data.append("Hello".data(using: .utf16BigEndian)!)
        let enc = EncodingDetector.detect(data: data)
        XCTAssertEqual(enc, .utf16BE)
    }

    func testEncodingDetector_KOI8R() {
        let s = "Привет, мир!"
        // Foundation.String.data(using:) не поддерживает произвольный rawValue —
        // получаем encoding через CoreFoundation (CFStringEncodings.KOI8_R = 0x0A02).
        let cf = CFStringConvertEncodingToNSStringEncoding(0x0A02)
        let ns = String.Encoding(rawValue: cf)
        guard let data = s.data(using: ns) else {
            XCTFail("KOI8-R encoding unavailable")
            return
        }
        let enc = EncodingDetector.detect(data: data)
        XCTAssertEqual(enc, .koi8r, "KOI8-R не распознан: got \(enc.name)")
    }

    func testEncodingDetector_EmptyData() {
        let enc = EncodingDetector.detect(data: Data())
        // Пустые данные — не должно упасть, любое разумное значение.
        XCTAssertNotNil(enc)
    }

    func testEncodingDetector_CP1251_RoundTrip() {
        let s = "Привет, мир!"
        let data = s.data(using: .windowsCP1251)!
        let enc = EncodingDetector.detect(data: data)
        let decoded = EncodingDetector.decode(data, using: enc)
        XCTAssertEqual(decoded, s, "CP1251 round-trip failed")
    }

    // Атрибуты и структура (2026-07-13).

    func testCharacterAttributesInherit() {
        let base = CharacterAttributes(fontName: "Arial", fontSize: 14, bold: true)
        let override = CharacterAttributes(italic: true)
        let merged = base.merged(with: override)
        XCTAssertEqual(merged.fontName, "Arial")
        XCTAssertEqual(merged.fontSize, 14)
        XCTAssertTrue(merged.bold)
        XCTAssertTrue(merged.italic)
    }

    func testStandardParagraphStylesAllPresent() {
        // Регрессия v0.1.26 — 7 стандартных стилей.
        let ids = StandardParagraphStyle.all.map(\.id)
        XCTAssertTrue(ids.contains("Normal"))
        for i in 1...6 { XCTAssertTrue(ids.contains("Heading\(i)")) }
    }

    func testStandardCharacterStylesAllPresent() {
        // Регрессия v0.1.32 — 3 стандартных символьных стиля.
        let ids = StandardCharacterStyle.all.map(\.id)
        XCTAssertTrue(ids.contains("Strong"))
        XCTAssertTrue(ids.contains("Emphasis"))
        XCTAssertTrue(ids.contains("CodeChar"))
    }

    func testPageSettingsA5() {
        let s = PageSettings(paperSize: .a5, orientation: .portrait, margins: .standard)
        // A5: 148×210mm → 419×595 pt (округл.).
        XCTAssertEqual(s.pageSizeInPoints.width, 419, accuracy: 1)
        XCTAssertEqual(s.pageSizeInPoints.height, 595, accuracy: 1)
    }

    func testPageSettingsLetter() {
        let s = PageSettings(paperSize: .letter, orientation: .portrait, margins: .standard)
        // Letter: 8.5×11 in → 612×792 pt.
        XCTAssertEqual(s.pageSizeInPoints.width, 612, accuracy: 0.5)
        XCTAssertEqual(s.pageSizeInPoints.height, 792, accuracy: 0.5)
    }

    func testColorFromHexShort() {
        // Проверка форматов без #.
        let c = CodableColor.fromHex("00FF00")
        XCTAssertNotNil(c)
        XCTAssertEqual(Double(c?.green ?? 0), 1.0, accuracy: 0.01)
    }

    func testColorFromHexInvalid() {
        XCTAssertNil(CodableColor.fromHex("#ZZZZZZ"))
        XCTAssertNil(CodableColor.fromHex(""))
    }

    func testCodableColorHexRoundTrip() {
        let c = CodableColor(red: 0.5, green: 0.3, blue: 0.1)
        let hex = c.hexString
        let back = CodableColor.fromHex(hex)
        XCTAssertEqual(Double(back?.red ?? 0), 0.5, accuracy: 0.01)
        XCTAssertEqual(Double(back?.green ?? 0), 0.3, accuracy: 0.01)
        XCTAssertEqual(Double(back?.blue ?? 0), 0.1, accuracy: 0.01)
    }
}
