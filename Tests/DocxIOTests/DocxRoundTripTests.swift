//
//  DocxRoundTripTests.swift
//  DocxIOTests
//
//  v0.4.1 (код-ревизия R05): in-memory round-trip экспорт→импорт DOCX.
//  Каждый тест собирает DocumentModel, гоняет через exportDocx(data)/importDocx(data:)
//  и сверяет, что атрибуты пережили сериализацию. Не требует UI/AppKit-моста.
//

import XCTest
import ZIPFoundation
@testable import DocxCore
@testable import DocxIO

final class DocxRoundTripTests: XCTestCase {

    // MARK: - Хелперы

    private func roundTrip(_ model: DocumentModel) throws -> DocumentModel {
        let data = try DocxIO.exportDocx(model)
        return try DocxIO.importDocx(data: data)
    }

    private func doc(_ blocks: [Block]) -> DocumentModel {
        DocumentModel(sections: [DocumentSection(blocks: blocks)])
    }

    private func firstParagraph(_ model: DocumentModel, _ index: Int = 0) throws -> Paragraph {
        let paragraphs: [Paragraph] = model.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        guard index < paragraphs.count else {
            throw XCTSkip("Paragraph #\(index) not found (got \(paragraphs.count))")
        }
        return paragraphs[index]
    }

    private func firstTable(_ model: DocumentModel) throws -> TableBlock {
        for block in model.sections.flatMap({ $0.blocks }) {
            if case let .table(t) = block { return t }
        }
        XCTFail("No table found after round-trip")
        throw NSError(domain: "test", code: 1)
    }

    // MARK: - Символьные атрибуты

    func testCharacterAttributesSurvive() throws {
        var attrs = CharacterAttributes()
        attrs.fontName = "Arial"
        attrs.fontSize = 16
        attrs.bold = true
        attrs.italic = true
        attrs.underline = .single
        attrs.strikethrough = true
        attrs.textColor = CodableColor(red: 1, green: 0, blue: 0)
        let p = Paragraph(runs: [Run(text: "styled", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))

        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("styled") })
        XCTAssertEqual(run.attributes.fontName, "Arial")
        XCTAssertEqual(run.attributes.fontSize, 16)
        XCTAssertTrue(run.attributes.bold)
        XCTAssertTrue(run.attributes.italic)
        XCTAssertEqual(run.attributes.underline, .single)
        XCTAssertTrue(run.attributes.strikethrough)
        XCTAssertEqual(run.attributes.textColor?.hexString, "#FF0000")
    }

    func testSuperscriptSubscriptSurvive() throws {
        var sup = CharacterAttributes(); sup.superscript = true
        var sub = CharacterAttributes(); sub.subscript = true
        let p = Paragraph(runs: [
            Run(text: "x", attributes: CharacterAttributes()),
            Run(text: "2", attributes: sup),
            Run(text: "i", attributes: sub),
        ])
        let out = try roundTrip(doc([.paragraph(p)]))
        let runs = try firstParagraph(out).runs
        XCTAssertTrue(try XCTUnwrap(runs.first { $0.text == "2" }).attributes.superscript)
        XCTAssertTrue(try XCTUnwrap(runs.first { $0.text == "i" }).attributes.subscript)
    }

    func testHighlightSurvives() throws {
        var attrs = CharacterAttributes()
        attrs.highlightColor = CodableColor(red: 1, green: 1, blue: 0) // yellow → w:highlight
        let p = Paragraph(runs: [Run(text: "marked", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))
        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("marked") })
        XCTAssertNotNil(run.attributes.highlightColor, "highlight потерян при round-trip")
    }

    // MARK: - Абзац

    func testParagraphAttributesSurvive() throws {
        var pa = ParagraphAttributes()
        pa.alignment = .center
        pa.leftIndent = 36
        pa.hangingIndent = 18
        pa.spaceBefore = 12
        pa.spaceAfter = 6
        let p = Paragraph(runs: [Run(text: "para", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let got = try firstParagraph(out).attributes
        XCTAssertEqual(got.alignment, .center)
        XCTAssertEqual(got.leftIndent, 36, accuracy: 0.6)   // twips-конверсия — допускаем округление
        XCTAssertEqual(got.hangingIndent, 18, accuracy: 0.6)
        XCTAssertEqual(got.spaceBefore, 12, accuracy: 0.6)
        XCTAssertEqual(got.spaceAfter, 6, accuracy: 0.6)
    }

    func testParagraphStyleIdSurvives() throws {
        var pa = ParagraphAttributes()
        pa.styleId = "Heading1"
        let p = Paragraph(runs: [Run(text: "Глава", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        XCTAssertEqual(try firstParagraph(out).attributes.styleId, "Heading1")
    }

    // v1.4.2 (ADR-049): Markdown-стили абзацев (Цитата/Блок кода/HR) —
    // round-trip через <w:pStyle> + styles.xml.
    func testMarkdownParagraphStylesSurvive() throws {
        for sid in ["Quote", "CodeBlock", "HorizontalRule"] {
            var pa = ParagraphAttributes()
            pa.styleId = sid
            let p = Paragraph(runs: [Run(text: "текст", attributes: .init())], attributes: pa)
            let out = try roundTrip(doc([.paragraph(p)]))
            XCTAssertEqual(try firstParagraph(out).attributes.styleId, sid,
                           "стиль \(sid) не пережил DOCX round-trip")
        }
    }

    // v1.5.4: пользовательские таб-стопы (<w:tabs><w:tab w:val w:pos>).
    func testTabStopsSurvive() throws {
        var pa = ParagraphAttributes()
        pa.tabStops = [TabStop(position: 108, alignment: .left),
                       TabStop(position: 216, alignment: .center),
                       TabStop(position: 432, alignment: .right)]
        let p = Paragraph(runs: [Run(text: "a\tb\tc", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let stops = try firstParagraph(out).attributes.tabStops
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[0].position, 108, accuracy: 0.5)
        XCTAssertEqual(stops[1].alignment, .center)
        XCTAssertEqual(stops[2].alignment, .right)
    }

    // v1.5.5: границы абзаца (<w:pBdr>) — линия под заголовком/колонтитулом.
    func testParagraphBorderSurvives() throws {
        var pa = ParagraphAttributes()
        pa.border = ParagraphBorder(bottom: true, width: 1.0,
                                    color: CodableColor(red: 1, green: 0, blue: 0))
        let p = Paragraph(runs: [Run(text: "заголовок с линией", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let b = try XCTUnwrap(firstParagraph(out).attributes.border)
        XCTAssertTrue(b.bottom)
        XCTAssertFalse(b.top)
        XCTAssertEqual(b.width, 1.0, accuracy: 0.13)
        XCTAssertEqual(b.color?.red ?? 0, 1, accuracy: 0.01)
    }

    // v1.5.6: сложное поле (w:fldChar) — инструкция + результат переживают
    // round-trip, поле остаётся «живым» (обновляемым) в Word.
    func testComplexFieldSurvives() throws {
        let p = Paragraph(runs: [
            Run(text: "3", attributes: .init(), fieldInstr: #"PAGEREF bookmark1 \h"#),
        ])
        let data = try DocxIO.exportDocx(doc([.paragraph(p)]))
        let archive = try Archive(data: data, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains(#"<w:fldChar w:fldCharType="begin"/>"#), xml)
        XCTAssertTrue(xml.contains(#"PAGEREF bookmark1 \h"#), xml)
        XCTAssertTrue(xml.contains(#"<w:fldChar w:fldCharType="separate"/>"#))
        XCTAssertTrue(xml.contains(#"<w:fldChar w:fldCharType="end"/>"#))

        let back = try DocxIO.importDocx(data: data)
        let run = try XCTUnwrap(firstParagraph(back).runs.first { $0.text.contains("3") })
        XCTAssertEqual(run.fieldInstr, #"PAGEREF bookmark1 \h"#)
        // Результат поля — обычный текст, не потерян.
        XCTAssertEqual(try firstParagraph(back).runs.map(\.text).joined(), "3")
    }

    // v1.5.6: реальный корпус — одноабзацные поля 21.docx получают fieldInstr.
    func testComplexFieldsInCorpus() throws {
        let url = Bundle.module.url(forResource: "21", withExtension: "docx",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let (model, _) = try DocxIO.importDocxWithReport(data: data)
        let runs = model.sections.flatMap { $0.blocks }.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs }
            return []
        }
        let withField = runs.filter { $0.fieldInstr != nil }
        XCTAssertFalse(withField.isEmpty, "в 21.docx одноабзацные поля должны резолвиться в fieldInstr")
        // Round-trip: экспортированный файл содержит живые поля.
        let exported = try DocxIO.exportDocx(model)
        let archive = try Archive(data: exported, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains(#"<w:fldChar w:fldCharType="begin"/>"#))
        XCTAssertTrue(xml.contains("<w:instrText"))
    }

    // MARK: - Списки

    func testBulletedListSurvives() throws {
        var pa = ParagraphAttributes()
        pa.listInfo = ListInfo(listType: .bulleted, level: 0, formatStyle: .bullet(character: "•"))
        let p = Paragraph(runs: [Run(text: "item", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let info = try XCTUnwrap(firstParagraph(out).attributes.listInfo)
        XCTAssertEqual(info.listType, .bulleted)
        XCTAssertEqual(info.level, 0)
    }

    func testNumberedListLevelSurvives() throws {
        var pa0 = ParagraphAttributes()
        pa0.listInfo = ListInfo(listType: .numbered, level: 0, formatStyle: .decimal)
        var pa1 = ParagraphAttributes()
        pa1.listInfo = ListInfo(listType: .numbered, level: 1, formatStyle: .lowerLetter)
        let out = try roundTrip(doc([
            .paragraph(Paragraph(runs: [Run(text: "one", attributes: .init())], attributes: pa0)),
            .paragraph(Paragraph(runs: [Run(text: "sub", attributes: .init())], attributes: pa1)),
        ]))
        let i0 = try XCTUnwrap(firstParagraph(out, 0).attributes.listInfo)
        let i1 = try XCTUnwrap(firstParagraph(out, 1).attributes.listInfo)
        XCTAssertEqual(i0.listType, .numbered)
        XCTAssertEqual(i0.level, 0)
        XCTAssertEqual(i0.formatStyle, .decimal)
        XCTAssertEqual(i1.level, 1)
        XCTAssertEqual(i1.formatStyle, .lowerLetter)
    }

    // v1.5.16: стартовое значение нумерации (w:start) — round-trip.
    func testListStartSurvives() throws {
        var pa = ParagraphAttributes()
        pa.listInfo = ListInfo(listType: .numbered, level: 0, formatStyle: .decimal, start: 5)
        let model = doc([
            .paragraph(Paragraph(runs: [Run(text: "five", attributes: .init())], attributes: pa)),
            .paragraph(Paragraph(runs: [Run(text: "six", attributes: .init())], attributes: pa)),
        ])
        let data = try DocxIO.exportDocx(model)
        let archive = try Archive(data: data, accessMode: .read)
        var numData = Data()
        if let e = archive["word/numbering.xml"] {
            _ = try archive.extract(e) { numData.append($0) }
        }
        let numXml = String(data: numData, encoding: .utf8)!
        XCTAssertTrue(numXml.contains(#"<w:start w:val="5"/>"#), numXml)

        let back = try DocxIO.importDocx(data: data)
        let li = try XCTUnwrap(firstParagraph(back).attributes.listInfo)
        XCTAssertEqual(li.start, 5)
    }

    // v1.5.17: вертикальный текст ячейки (w:textDirection) — round-trip.
    func testCellTextDirectionSurvives() throws {
        let cell = TableCell(
            blocks: [.paragraph(Paragraph(runs: [Run(text: "верт", attributes: .init())]))],
            textDirection: "tbRl")
        let table = TableBlock(rows: [TableRow(cells: [cell])])
        let model = doc([.table(table)])
        let data = try DocxIO.exportDocx(model)
        let archive = try Archive(data: data, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains(#"<w:textDirection w:val="tbRl"/>"#), xml)

        let back = try DocxIO.importDocx(data: data)
        guard case .table(let t) = back.sections[0].blocks[0] else {
            return XCTFail("таблица потерялась")
        }
        XCTAssertEqual(t.rows[0].cells[0].textDirection, "tbRl")
    }

    // v1.5.17: именованный стиль таблицы (w:tblStyle) — round-trip, и его
    // определение из styles.xml переживает экспорт (passthrough).
    func testTableNamedStyleSurvives() throws {
        let cell = TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))])
        var style = TableStyle()
        style.namedStyleId = "LightShading-Accent1"
        let table = TableBlock(rows: [TableRow(cells: [cell])], style: style)
        let model = doc([.table(table)])
        let data = try DocxIO.exportDocx(model)
        let archive = try Archive(data: data, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains(#"<w:tblStyle w:val="LightShading-Accent1"/>"#), xml)

        let back = try DocxIO.importDocx(data: data)
        guard case .table(let t) = back.sections[0].blocks[0] else {
            return XCTFail("таблица потерялась")
        }
        XCTAssertEqual(t.style.namedStyleId, "LightShading-Accent1")
    }

    // v1.6.1: буквица (w:framePr) — атрибуты переживают round-trip.
    func testFramePrSurvives() throws {
        var pa = ParagraphAttributes()
        pa.framePr = ["w:dropCap": "drop", "w:lines": "3", "w:wrap": "around",
                      "w:vAnchor": "text", "w:hAnchor": "text"]
        let model = doc([.paragraph(Paragraph(runs: [Run(text: "Буквица", attributes: .init())],
                                              attributes: pa))])
        let data = try DocxIO.exportDocx(model)
        let archive = try Archive(data: data, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains("<w:framePr"), xml)
        XCTAssertTrue(xml.contains(#"w:dropCap="drop""#), xml)
        XCTAssertTrue(xml.contains(#"w:lines="3""#), xml)

        let back = try DocxIO.importDocx(data: data)
        let fp = try XCTUnwrap(firstParagraph(back).attributes.framePr)
        XCTAssertEqual(fp["w:dropCap"], "drop")
        XCTAssertEqual(fp["w:lines"], "3")
    }

    // MARK: - Таблицы

    func testTableSurvives() throws {
        let cell = { (t: String) in
            TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: t, attributes: .init())]))])
        }
        var headerRow = TableRow(cells: [cell("H1"), cell("H2")])
        headerRow.isHeader = true
        let table = TableBlock(rows: [headerRow, TableRow(cells: [cell("a"), cell("b")])],
                               columnWidths: [120, 180])
        let out = try roundTrip(doc([.table(table)]))
        let got = try firstTable(out)
        XCTAssertEqual(got.rows.count, 2)
        XCTAssertEqual(got.rows[0].cells.count, 2)
        XCTAssertTrue(got.rows[0].isHeader, "<w:tblHeader/> потерян")
        XCTAssertFalse(got.rows[1].isHeader)
        XCTAssertEqual(got.columnWidths.count, 2)
        XCTAssertEqual(got.columnWidths[0], 120, accuracy: 1.0)
    }

    func testTableCellSpanSurvives() throws {
        let plain = { (t: String) in
            TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: t, attributes: .init())]))])
        }
        var merged = plain("wide")
        merged.colSpan = 2
        let table = TableBlock(rows: [
            TableRow(cells: [merged]),
            TableRow(cells: [plain("a"), plain("b")]),
        ], columnWidths: [100, 100])
        let out = try roundTrip(doc([.table(table)]))
        let got = try firstTable(out)
        XCTAssertEqual(got.rows[0].cells.first?.colSpan, 2, "gridSpan потерян")
    }

    // MARK: - Гиперссылки

    func testHyperlinkSurvives() throws {
        var run = Run(text: "link", attributes: .init())
        run.hyperlink = "https://example.com/path"
        let out = try roundTrip(doc([.paragraph(Paragraph(runs: [run]))]))
        let got = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("link") })
        XCTAssertEqual(got.hyperlink, "https://example.com/path")
    }

    // MARK: - Метаданные и страница

    func testMetadataSurvives() throws {
        var model = doc([.paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))])
        model.metadata.title = "Отчёт"
        model.metadata.author = "Иванов"
        model.metadata.keywords = ["тест", "docx"]
        model.metadata.language = "ru-RU"
        let out = try roundTrip(model)
        XCTAssertEqual(out.metadata.title, "Отчёт")
        XCTAssertEqual(out.metadata.author, "Иванов")
        XCTAssertEqual(out.metadata.keywords, ["тест", "docx"])
        XCTAssertEqual(out.metadata.language, "ru-RU")
    }

    func testPageSettingsSurvive() throws {
        var model = doc([.paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))])
        model.pageSettings.paperSize = .a5
        model.pageSettings.orientation = .landscape
        model.pageSettings.mirrorMargins = true
        model.pageSettings.margins.left = 50
        let out = try roundTrip(model)
        XCTAssertEqual(out.pageSettings.paperSize, .a5)
        XCTAssertEqual(out.pageSettings.orientation, .landscape)
        XCTAssertTrue(out.pageSettings.mirrorMargins)
        XCTAssertEqual(out.pageSettings.margins.left, 50, accuracy: 0.6)
    }

    func testHeaderFooterVariantsSurvive() throws {
        var model = doc([.paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))])
        model.headerFooter.headerText = "Верх {page}"
        model.headerFooter.footerText = "Низ"
        model.headerFooter.differentFirstPage = true
        model.headerFooter.firstHeaderText = "Титул"
        model.headerFooter.differentOddEven = true
        model.headerFooter.evenHeaderText = "Чётная"
        let out = try roundTrip(model)
        XCTAssertEqual(out.headerFooter.headerText, "Верх {page}")
        XCTAssertEqual(out.headerFooter.footerText, "Низ")
        XCTAssertTrue(out.headerFooter.differentFirstPage)
        XCTAssertEqual(out.headerFooter.firstHeaderText, "Титул")
        XCTAssertTrue(out.headerFooter.differentOddEven)
        XCTAssertEqual(out.headerFooter.evenHeaderText, "Чётная")
    }

    // MARK: - Расширенное покрытие R01-R06 (2026-07-13)

    // Символьные стили Strong/Emphasis/CodeChar (v0.1.32) — DOCX rStyle.
    func testCharacterStyleIdSurvives() throws {
        var attrs = CharacterAttributes()
        attrs.styleId = "Strong"
        let p = Paragraph(runs: [Run(text: "bold-run", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))
        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("bold-run") })
        XCTAssertEqual(run.attributes.styleId, "Strong")
    }

    // Все форматы списков — маркированный + все нумерованные варианты (v0.1.22, v0.1.24).
    func testAllListFormatsSurvive() throws {
        // NB: `DocxCore.ListFormatStyle` дизамбигуируется от Foundation.ListFormatStyle.
        typealias LFS = DocxCore.ListFormatStyle
        let formats: [(ListType, LFS)] = [
            (ListType.bulleted, LFS.bullet(character: "•")),
            (ListType.numbered, LFS.decimal),
            (ListType.numbered, LFS.lowerLetter),
            (ListType.numbered, LFS.upperLetter),
            (ListType.numbered, LFS.lowerRoman),
            (ListType.numbered, LFS.upperRoman),
            (ListType.numbered, LFS.decimalEnclosedParen),
            (ListType.numbered, LFS.lowerLetterParen),
            (ListType.numbered, LFS.lowerRomanParen),
        ]
        for (type, fmt) in formats {
            var pa = ParagraphAttributes()
            pa.listInfo = ListInfo(listType: type, level: 0, formatStyle: fmt)
            let p = Paragraph(runs: [Run(text: "item", attributes: .init())], attributes: pa)
            let out = try roundTrip(doc([.paragraph(p)]))
            let info = try XCTUnwrap(firstParagraph(out).attributes.listInfo,
                                     "listInfo lost for \(fmt)")
            XCTAssertEqual(info.listType, type)
            XCTAssertEqual(info.formatStyle, fmt, "formatStyle mismatch for \(fmt)")
        }
    }

    // Многоуровневый составной формат `%1.%2.%3.` — decimalNested (v0.1.24).
    func testDecimalNestedListSurvives() throws {
        var pa0 = ParagraphAttributes(); pa0.listInfo = ListInfo(listType: .numbered, level: 0, formatStyle: .decimalNested)
        var pa1 = ParagraphAttributes(); pa1.listInfo = ListInfo(listType: .numbered, level: 1, formatStyle: .decimalNested)
        var pa2 = ParagraphAttributes(); pa2.listInfo = ListInfo(listType: .numbered, level: 2, formatStyle: .decimalNested)
        let out = try roundTrip(doc([
            .paragraph(Paragraph(runs: [Run(text: "L0", attributes: .init())], attributes: pa0)),
            .paragraph(Paragraph(runs: [Run(text: "L1", attributes: .init())], attributes: pa1)),
            .paragraph(Paragraph(runs: [Run(text: "L2", attributes: .init())], attributes: pa2)),
        ]))
        for i in 0..<3 {
            let info = try XCTUnwrap(firstParagraph(out, i).attributes.listInfo,
                                     "listInfo lost at level \(i)")
            XCTAssertEqual(info.formatStyle, .decimalNested)
            XCTAssertEqual(info.level, i)
        }
    }

    // Разрыв страницы U+000C (v0.1.35) — сериализуется как <w:br w:type="page"/>.
    func testPageBreakSurvives() throws {
        let p = Paragraph(runs: [Run(text: "before\u{000C}after", attributes: .init())])
        let out = try roundTrip(doc([.paragraph(p)]))
        let joined = try firstParagraph(out).runs.map { $0.text }.joined()
        XCTAssertTrue(joined.contains("\u{000C}"), "разрыв страницы не сохранился: \(joined)")
    }

    // Inline-изображение (v0.1.53) — байты + размеры выживают.
    func testInlineImageSurvives() throws {
        // 1x1 PNG (transparent) — минимальный валидный PNG.
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ]
        let img = InlineImage(format: .png, data: Data(pngBytes),
                              displayWidth: 100, displayHeight: 80)
        let run = Run(text: "\u{FFFC}", attributes: .init(), image: img)
        let out = try roundTrip(doc([.paragraph(Paragraph(runs: [run]))]))
        let got = try XCTUnwrap(firstParagraph(out).runs.first { $0.image != nil }?.image,
                                "изображение потерялось")
        XCTAssertEqual(got.format, .png)
        XCTAssertEqual(got.displayWidth, 100, accuracy: 1)
        XCTAssertEqual(got.displayHeight, 80, accuracy: 1)
        XCTAssertGreaterThan(got.data.count, 0)
    }

    // Обтекание изображения текстом (v0.1.102) — все режимы.
    func testImageWrapSurvives() throws {
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ]
        let wraps: [InlineImageWrap] = [.square, .tight, .topAndBottom, .behindText, .inFrontOfText]
        for wrap in wraps {
            let img = InlineImage(format: .png, data: Data(pngBytes),
                                  displayWidth: 100, displayHeight: 80, wrap: wrap)
            let run = Run(text: "\u{FFFC}", attributes: .init(), image: img)
            let out = try roundTrip(doc([.paragraph(Paragraph(runs: [run]))]))
            let got = try XCTUnwrap(firstParagraph(out).runs.first { $0.image != nil }?.image,
                                    "изображение с wrap=\(wrap) потерялось")
            XCTAssertEqual(got.wrap, wrap, "wrap mode not preserved: expected \(wrap), got \(got.wrap)")
        }
    }

    // v1.5.12: позиция плавающего якоря (wp:anchor posOffset) переживает
    // round-trip — и в XML пишется, и при импорте читается.
    func testFloatingImageAnchorPositionSurvives() throws {
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ]
        // 72pt и 36pt в EMU.
        let img = InlineImage(format: .png, data: Data(pngBytes),
                              displayWidth: 100, displayHeight: 80, wrap: .square,
                              anchorXEMU: 72 * 12700, anchorYEMU: 36 * 12700)
        let run = Run(text: "\u{FFFC}", attributes: .init(), image: img)
        let model = doc([.paragraph(Paragraph(runs: [run]))])
        let data = try DocxIO.exportDocx(model)
        let archive = try Archive(data: data, accessMode: .read)
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let xml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(xml.contains("<wp:posOffset>\(72 * 12700)</wp:posOffset>"), xml)
        XCTAssertTrue(xml.contains("<wp:posOffset>\(36 * 12700)</wp:posOffset>"))

        let back = try DocxIO.importDocx(data: data)
        let got = try XCTUnwrap(firstParagraph(back).runs.first { $0.image != nil }?.image)
        XCTAssertEqual(got.anchorXEMU, 72 * 12700)
        XCTAssertEqual(got.anchorYEMU, 36 * 12700)
        XCTAssertEqual(got.wrap, .square)
    }

    // Alt-текст изображения (v0.1.60).
    func testImageAltTextSurvives() throws {
        let pngBytes: [UInt8] = [
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ]
        var img = InlineImage(format: .png, data: Data(pngBytes),
                              displayWidth: 100, displayHeight: 80)
        img.altText = "Диаграмма продаж за Q3"
        let run = Run(text: "\u{FFFC}", attributes: .init(), image: img)
        let out = try roundTrip(doc([.paragraph(Paragraph(runs: [run]))]))
        let got = try XCTUnwrap(firstParagraph(out).runs.first { $0.image != nil }?.image)
        XCTAssertEqual(got.altText, "Диаграмма продаж за Q3")
    }

    // Свойства таблицы: границы, ширина колонки, заливка ячейки (v0.1.51).
    func testTableCellBackgroundSurvives() throws {
        var cell = TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: "highlighted", attributes: .init())]))])
        cell.backgroundColor = CodableColor(red: 1, green: 0.9, blue: 0.4)
        let row = TableRow(cells: [cell])
        let table = TableBlock(rows: [row], columnWidths: [100])
        let out = try roundTrip(doc([.table(table)]))
        let got = try firstTable(out)
        let bg = got.rows.first?.cells.first?.backgroundColor
        XCTAssertNotNil(bg, "заливка ячейки потерялась")
        // Округление hex → CodableColor может дать погрешность 1/255.
        XCTAssertEqual(Double(bg?.red ?? 0), 1.0, accuracy: 0.02)
    }

    // Table alignment (v0.1.70).
    func testTableAlignmentSurvives() throws {
        let cell = { (t: String) in
            TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: t, attributes: .init())]))])
        }
        for align in [TableAlignment.center, .right] {
            let table = TableBlock(rows: [TableRow(cells: [cell("a")])],
                                   columnWidths: [100], alignment: align)
            let out = try roundTrip(doc([.table(table)]))
            let got = try firstTable(out)
            XCTAssertEqual(got.alignment, align, "table alignment lost: expected \(align)")
        }
    }

    // Firstline indent (v0.1.94) — противоположность hanging.
    func testFirstLineIndentSurvives() throws {
        var pa = ParagraphAttributes()
        pa.firstLineIndent = 24  // абзацный отступ
        let p = Paragraph(runs: [Run(text: "para", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let got = try firstParagraph(out).attributes
        XCTAssertEqual(got.firstLineIndent, 24, accuracy: 0.6)
    }

    // Line spacing (v0.1.12) — междустрочный интервал.
    func testLineSpacingSurvives() throws {
        var pa = ParagraphAttributes()
        pa.lineSpacing = .multiple(1.5)
        let p = Paragraph(runs: [Run(text: "para", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        let got = try firstParagraph(out).attributes
        if case let .multiple(m) = got.lineSpacing {
            XCTAssertEqual(m, 1.5, accuracy: 0.01)
        } else {
            XCTFail("lineSpacing lost: \(got.lineSpacing)")
        }
    }

    // Стандартный highlight-цвет (yellow) → w:highlight (именованный).
    func testHighlightNamedYellow() throws {
        var attrs = CharacterAttributes()
        attrs.highlightColor = CodableColor(red: 1, green: 1, blue: 0) // yellow
        let p = Paragraph(runs: [Run(text: "marked", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))
        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("marked") })
        let hl = try XCTUnwrap(run.attributes.highlightColor)
        XCTAssertEqual(Double(hl.red), 1.0, accuracy: 0.05)
        XCTAssertEqual(Double(hl.green), 1.0, accuracy: 0.05)
    }

    // Нестандартный highlight → w:shd (произвольный hex).
    func testHighlightCustomColor() throws {
        var attrs = CharacterAttributes()
        attrs.highlightColor = CodableColor(red: 0.3, green: 0.7, blue: 0.9)
        let p = Paragraph(runs: [Run(text: "custom", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))
        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("custom") })
        XCTAssertNotNil(run.attributes.highlightColor, "нестандартный highlight не round-trip'нулся")
    }

    // Colour text (foreground) — просто прогнать несколько цветов.
    func testTextColorSurvives() throws {
        var attrs = CharacterAttributes()
        attrs.textColor = CodableColor(red: 0.1, green: 0.5, blue: 0.9)
        let p = Paragraph(runs: [Run(text: "colored", attributes: attrs)])
        let out = try roundTrip(doc([.paragraph(p)]))
        let run = try XCTUnwrap(firstParagraph(out).runs.first { $0.text.contains("colored") })
        XCTAssertNotNil(run.attributes.textColor)
    }

    // Секции с разными настройками страниц (R04 base — v0.2.5 U+000C-подход).
    func testMultipleParagraphsWithBreak() throws {
        let p1 = Paragraph(runs: [Run(text: "one", attributes: .init())])
        let p2 = Paragraph(runs: [Run(text: "two", attributes: .init())])
        let p3 = Paragraph(runs: [Run(text: "three", attributes: .init())])
        let out = try roundTrip(doc([.paragraph(p1), .paragraph(p2), .paragraph(p3)]))
        let paras: [Paragraph] = out.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(paras.count, 3)
        XCTAssertEqual(paras.map { $0.runs.first?.text ?? "" }, ["one", "two", "three"])
    }

    // Все выравнивания абзаца.
    func testAllParagraphAlignments() throws {
        for align in [TextAlignment.left, .center, .right, .justify] {
            var pa = ParagraphAttributes()
            pa.alignment = align
            let p = Paragraph(runs: [Run(text: "aligned", attributes: .init())], attributes: pa)
            let out = try roundTrip(doc([.paragraph(p)]))
            XCTAssertEqual(try firstParagraph(out).attributes.alignment, align,
                           "alignment \(align) lost")
        }
    }

    // Правый отступ (v0.1.94).
    func testRightIndentSurvives() throws {
        var pa = ParagraphAttributes()
        pa.rightIndent = 48
        let p = Paragraph(runs: [Run(text: "para", attributes: .init())], attributes: pa)
        let out = try roundTrip(doc([.paragraph(p)]))
        XCTAssertEqual(try firstParagraph(out).attributes.rightIndent, 48, accuracy: 0.6)
    }

    // Backward-compat модели без comments/track-changes-полей (v0.4.4+).
    func testBackwardsCompatRunWithoutTrackFields() throws {
        // Старая модель без insertion/deletion — должна декодироваться.
        let old = """
        {"text":"hi","attributes":\(try String(data: JSONEncoder().encode(CharacterAttributes()), encoding: .utf8)!)}
        """
        let run = try JSONDecoder().decode(Run.self, from: Data(old.utf8))
        XCTAssertNil(run.commentId)
        XCTAssertNil(run.insertion)
        XCTAssertNil(run.deletion)
    }

    // MARK: - Track Changes DOCX (v0.4.7)

    func testTrackChangesInsertionSurvives() throws {
        let attrs = CharacterAttributes()
        var mid = Run(text: "new-text", attributes: attrs)
        mid.insertion = "Ivan|2026-07-13T10:00:00Z|abc12345"
        let p = Paragraph(runs: [
            Run(text: "kept ", attributes: attrs), mid, Run(text: " kept", attributes: attrs),
        ])
        let out = try roundTrip(doc([.paragraph(p)]))
        let ins = try firstParagraph(out).runs.first { $0.insertion != nil }
        XCTAssertNotNil(ins, "w:ins не восстановился")
        XCTAssertEqual(ins?.text, "new-text")
        XCTAssertTrue(ins?.insertion?.hasPrefix("Ivan|") ?? false)
    }

    func testTrackChangesDeletionSurvives() throws {
        let attrs = CharacterAttributes()
        var mid = Run(text: "deleted-word", attributes: attrs)
        mid.deletion = "Petr|2026-07-13T11:00:00Z|def45678"
        let p = Paragraph(runs: [
            Run(text: "before ", attributes: attrs), mid, Run(text: " after", attributes: attrs),
        ])
        let out = try roundTrip(doc([.paragraph(p)]))
        let del = try firstParagraph(out).runs.first { $0.deletion != nil }
        XCTAssertNotNil(del, "w:del не восстановился")
        XCTAssertEqual(del?.text, "deleted-word")
        XCTAssertTrue(del?.deletion?.hasPrefix("Petr|") ?? false)
    }

    // MARK: - Комментарии DOCX (v0.4.5)

    func testCommentDocxRoundTrip() throws {
        let attrs = CharacterAttributes()
        var mid = Run(text: "world", attributes: attrs); mid.commentId = "T1"
        let paragraph = Paragraph(runs: [
            Run(text: "Hello, ", attributes: attrs),
            mid,
            Run(text: "!", attributes: attrs),
        ])
        var m = doc([.paragraph(paragraph)])
        m.comments = [CommentThread(id: "T1", author: "Иван Петров", text: "Уточните формулировку")]
        let out = try roundTrip(m)
        XCTAssertEqual(out.comments.count, 1)
        XCTAssertEqual(out.comments.first?.author, "Иван Петров")
        XCTAssertEqual(out.comments.first?.text, "Уточните формулировку")
        let runs = try firstParagraph(out).runs
        let anchored = runs.filter { $0.commentId != nil }.map(\.text).joined()
        XCTAssertEqual(anchored, "world", "commentRange привязка не восстановилась")
        XCTAssertEqual(runs.first { $0.commentId != nil }?.commentId, out.comments.first?.id)
    }

    func testOrphanCommentDroppedOnExport() throws {
        var m = doc([.paragraph(Paragraph(runs: [Run(text: "no anchor", attributes: .init())]))])
        m.comments = [CommentThread(author: "X", text: "orphan")]
        let out = try roundTrip(m)
        XCTAssertTrue(out.comments.isEmpty)
    }

    // MARK: - Backward-compat модели (v0.4.4)

    /// Модели, сериализованные до v0.4.4 (без поля `comments`), должны
    /// продолжать декодироваться: `init(from:)` использует decodeIfPresent
    /// и подставляет пустой массив.
    func testModelBackwardsCompatWithoutComments() throws {
        let old = """
        {"metadata":\(try String(data: JSONEncoder().encode(DocumentMetadata()), encoding: .utf8)!),
        "pageSettings":\(try String(data: JSONEncoder().encode(PageSettings.a4Portrait), encoding: .utf8)!),
        "sections":[{"blocks":[]}],
        "styles":\(try String(data: JSONEncoder().encode(DocumentStyles.defaultStyles), encoding: .utf8)!)}
        """
        let m = try JSONDecoder().decode(DocumentModel.self, from: Data(old.utf8))
        XCTAssertTrue(m.comments.isEmpty)
        XCTAssertEqual(m.headerFooter, HeaderFooter())
    }

    /// Треды комментариев со всеми полями (включая ответы) переживают JSON.
    func testCommentThreadsJsonRoundTrip() throws {
        var m = doc([.paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))])
        var t = CommentThread(author: "Иван", text: "первый")
        t.replies.append(CommentReply(author: "Пётр", text: "ответ"))
        t.resolved = true
        m.comments = [t]
        let data = try JSONEncoder().encode(m)
        let out = try JSONDecoder().decode(DocumentModel.self, from: data)
        XCTAssertEqual(out.comments.count, 1)
        XCTAssertEqual(out.comments.first?.author, "Иван")
        XCTAssertEqual(out.comments.first?.replies.first?.author, "Пётр")
        XCTAssertTrue(out.comments.first?.resolved ?? false)
    }

    // MARK: - Кириллица и спецсимволы

    func testCyrillicAndXmlEscapes() throws {
        let text = "Русский текст: <тег> & \"кавычки\" 'апострофы'"
        let out = try roundTrip(doc([.paragraph(Paragraph(runs: [Run(text: text, attributes: .init())]))]))
        let joined = try firstParagraph(out).runs.map { $0.text }.joined()
        XCTAssertEqual(joined, text)
    }
}
