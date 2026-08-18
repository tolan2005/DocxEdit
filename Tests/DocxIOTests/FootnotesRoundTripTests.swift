//
//  FootnotesRoundTripTests.swift
//  v0.5.2 (R07): DOCX round-trip сносок.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class FootnotesRoundTripTests: XCTestCase {

    private func rt(_ m: DocumentModel) throws -> DocumentModel {
        try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
    }

    func testSingleFootnoteSurvives() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "Тезис", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "1"),
                Run(text: " далее…", attributes: .init()),
            ]))
        ])])
        m.footnotes = [Footnote(id: "1", text: "Первичный источник, 2024, с. 42.")]

        let back = try rt(m)
        XCTAssertEqual(back.footnotes.count, 1, "сноска потеряна")
        XCTAssertEqual(back.footnotes.first?.text, "Первичный источник, 2024, с. 42.")

        let runs = back.sections.flatMap { $0.blocks }.flatMap {
            if case let .paragraph(p) = $0 { return p.runs } else { return [] }
        }
        XCTAssertTrue(runs.contains { $0.footnoteId != nil }, "footnoteId на ране пропал")
    }

    func testMultipleFootnotesSurvive() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "A", attributes: .init(), footnoteId: "1"),
                Run(text: " и B", attributes: .init(), footnoteId: "2"),
            ]))
        ])])
        m.footnotes = [
            Footnote(id: "1", text: "первая"),
            Footnote(id: "2", text: "вторая"),
        ]
        let back = try rt(m)
        XCTAssertEqual(back.footnotes.count, 2)
        let texts = Set(back.footnotes.map(\.text))
        XCTAssertEqual(texts, ["первая", "вторая"])
    }

    func testOrphanFootnoteNotSerialized() throws {
        // Сноска в модели, но без якоря в тексте — writer НЕ должен её писать.
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "текст", attributes: .init())]))
        ])])
        m.footnotes = [Footnote(id: "42", text: "осиротевшая")]

        let back = try rt(m)
        XCTAssertEqual(back.footnotes.count, 0,
                       "осиротевшая сноска попала в файл — Word не любит висячих")
    }

    func testCyrillicFootnoteText() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "Съешь", attributes: .init(), footnoteId: "1"),
            ]))
        ])])
        m.footnotes = [Footnote(id: "1", text: "См. Даль, «Толковый словарь», М., 1863.")]
        let back = try rt(m)
        XCTAssertEqual(back.footnotes.first?.text, "См. Даль, «Толковый словарь», М., 1863.")
    }

    func testFootnoteIdOnRunAllowsEmptyText() throws {
        // Anchor-ран может быть без текста (только footnoteReference).
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "утверждение", attributes: .init()),
                Run(text: "", attributes: .init(), footnoteId: "1"),
            ]))
        ])])
        m.footnotes = [Footnote(id: "1", text: "пояснение")]
        let back = try rt(m)
        let text = back.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
        XCTAssertTrue(text.contains("утверждение"), "текст утерян: \(text)")
        XCTAssertEqual(back.footnotes.count, 1)
    }
}
