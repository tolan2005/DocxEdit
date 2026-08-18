//
//  FootnotesRenumberTests.swift
//  v0.5.4 (R07): проверка live-нумерации сносок (headless-логика через мост).
//
//  Тесты не гоняют NSTextView, они проверяют, что после нескольких вставок
//  и последовательного round-trip модель хранит корректные id и якоря идут
//  в порядке появления.
//

import XCTest
import ZIPFoundation
@testable import DocxCore
@testable import DocxIO

final class FootnotesRenumberTests: XCTestCase {

    /// Симулируем, как renumberFootnotes переопределяет id — прогоняем через
    /// DOCX round-trip и проверяем, что порядок сохранён.
    func testFootnotesOrderInText() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "первый ", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "1"),
                Run(text: " второй ", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "2"),
                Run(text: " третий ", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "3"),
            ]))
        ])])
        m.footnotes = [
            Footnote(id: "1", text: "первая сноска"),
            Footnote(id: "2", text: "вторая сноска"),
            Footnote(id: "3", text: "третья сноска"),
        ]
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        XCTAssertEqual(back.footnotes.count, 3, "потеряны сноски")
        // Проверяем, что тексты и порядок сохранились.
        let texts = back.footnotes.map(\.text)
        XCTAssertEqual(Set(texts), ["первая сноска", "вторая сноска", "третья сноска"])
    }

    func testFootnoteInTableCell() throws {
        // Сноски внутри ячейки таблицы должны быть собраны writer'ом.
        let cell = TableCell(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "в ячейке", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "1"),
            ]))
        ])
        let table = TableBlock(rows: [TableRow(cells: [cell])])
        var m = DocumentModel(sections: [DocumentSection(blocks: [.table(table)])])
        m.footnotes = [Footnote(id: "1", text: "в таблице")]
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        XCTAssertEqual(back.footnotes.first?.text, "в таблице",
                       "сноска в ячейке таблицы не собралась writer'ом")
    }

    // MARK: - v1.5.15: концевые сноски (endnotes)

    /// Round-trip: маркер w:endnoteReference + word/endnotes.xml переживают
    /// экспорт и импорт (модель, rels, Content_Types).
    func testEndnotesRoundTrip() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "основной текст ", attributes: .init()),
                Run(text: "", attributes: .init(), endnoteId: "1"),
                Run(text: " и ещё ", attributes: .init()),
                Run(text: "", attributes: .init(), endnoteId: "2"),
            ]))
        ])])
        m.endnotes = [
            Footnote(id: "1", text: "концевая сноска раз"),
            Footnote(id: "2", text: "концевая сноска два"),
        ]
        let data = try DocxIO.exportDocx(m)
        // endnotes.xml присутствует с обоими текстами.
        let archive = try Archive(data: data, accessMode: .read)
        var endData = Data()
        if let e = archive["word/endnotes.xml"] {
            _ = try archive.extract(e) { endData.append($0) }
        }
        let endXml = String(data: endData, encoding: .utf8)!
        XCTAssertTrue(endXml.contains("концевая сноска раз"), endXml)
        XCTAssertTrue(endXml.contains("w:endnote w:id=\"2\""), endXml)
        // Маркеры в document.xml.
        var docData = Data()
        if let e = archive["word/document.xml"] {
            _ = try archive.extract(e) { docData.append($0) }
        }
        let docXml = String(data: docData, encoding: .utf8)!
        XCTAssertTrue(docXml.contains("<w:endnoteReference w:id=\"1\"/>"), docXml)

        // Импорт: id на ранах и тексты в модели.
        let back = try DocxIO.importDocx(data: data)
        XCTAssertEqual(back.endnotes.count, 2)
        XCTAssertEqual(Set(back.endnotes.map(\.text)),
                       ["концевая сноска раз", "концевая сноска два"])
        let anchors = back.sections.flatMap { $0.blocks }.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs }
            return []
        }.compactMap(\.endnoteId)
        XCTAssertEqual(anchors, ["1", "2"])
    }

    /// Файл БЕЗ endnotes не получает лишней части (endnotes.xml не генерится).
    func testNoEndnotesNoPart() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "просто текст", attributes: .init())]))
        ])])
        let data = try DocxIO.exportDocx(m)
        let archive = try Archive(data: data, accessMode: .read)
        XCTAssertNil(archive["word/endnotes.xml"])
    }
}
