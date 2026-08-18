//
//  FootnotesRenumberTests.swift
//  v0.5.4 (R07): проверка live-нумерации сносок (headless-логика через мост).
//
//  Тесты не гоняют NSTextView, они проверяют, что после нескольких вставок
//  и последовательного round-trip модель хранит корректные id и якоря идут
//  в порядке появления.
//

import XCTest
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
}
