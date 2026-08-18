//
//  AttrRevisionRoundTripTests.swift
//  v0.5.8 (R08): DOCX round-trip track-changes ревизий атрибутов
//  (`<w:rPrChange>`). В MVP сохраняем ФАКТ ревизии (author/date/id), но не
//  старые атрибуты — writer эмитит `<w:rPr/>` пустым.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class AttrRevisionRoundTripTests: XCTestCase {

    func testAttributeRevisionSurvivesRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "обычный ", attributes: .init()),
                Run(text: "изменённый", attributes: .init(bold: true),
                    attributeRevision: "Иван|2026-07-16T10:00:00Z|1"),
                Run(text: " хвост", attributes: .init()),
            ]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let runs = back.sections.first?.blocks.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs } else { return [] }
        } ?? []
        let revised = runs.first { $0.attributeRevision != nil }
        XCTAssertNotNil(revised, "ревизия атрибутов потерялась в round-trip")
        // Автор и дата должны сохраниться; id может быть перенумерован
        // (writer генерирует свежий счётчик — nextRevisionId).
        let parts = (revised?.attributeRevision ?? "").split(separator: "|").map(String.init)
        XCTAssertEqual(parts.count, 3, "формат attributeRevision нарушен")
        XCTAssertEqual(parts[0], "Иван", "author потерян")
        XCTAssertEqual(parts[1], "2026-07-16T10:00:00Z", "date потерян")
        // Атрибуты рана (bold) должны сохраниться независимо от ревизии.
        XCTAssertTrue(revised?.attributes.bold == true,
                      "текущие атрибуты рана (bold) не должны теряться при наличии rPrChange")
    }

    func testRunWithoutRevisionDoesNotGetOne() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "чистый", attributes: .init())]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let runs = back.sections.first?.blocks.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs } else { return [] }
        } ?? []
        XCTAssertFalse(runs.contains { $0.attributeRevision != nil },
                       "у обычного рана не должно быть ревизии атрибутов")
    }
}
