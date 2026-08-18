//
//  TocSdtRoundTripTests.swift
//  v0.5.6 (R07): DOCX round-trip блока оглавления через <w:sdt> с
//  docPartGallery="Table of Contents".
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class TocSdtRoundTripTests: XCTestCase {

    func testTocBlockSurvivesRoundTrip() throws {
        // Собираем: Заголовок 1, TOC-параграф с двумя строками, обычный текст.
        let toc1 = Paragraph(runs: [
            Run(text: "Оглавление", attributes: .init(), tocBlock: "toc"),
        ])
        let toc2 = Paragraph(runs: [
            Run(text: "1. Введение", attributes: .init(), tocBlock: "toc"),
        ])
        let toc3 = Paragraph(runs: [
            Run(text: "2. Основная часть", attributes: .init(), tocBlock: "toc"),
        ])
        let body = Paragraph(runs: [Run(text: "Первый абзац", attributes: .init())])
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(toc1), .paragraph(toc2), .paragraph(toc3), .paragraph(body),
        ])])
        let data = try DocxIO.exportDocx(m)
        let back = try DocxIO.importDocx(data: data)
        let paras: [Paragraph] = back.sections.first?.blocks.compactMap {
            if case .paragraph(let p) = $0 { return p } else { return nil }
        } ?? []
        XCTAssertEqual(paras.count, 4, "ожидалось 4 абзаца после round-trip")
        // Первые три — с tocBlock.
        for i in 0..<3 {
            XCTAssertTrue(paras[i].runs.contains { $0.tocBlock == "toc" },
                          "параграф \(i) должен нести tocBlock")
        }
        // Последний — без.
        XCTAssertFalse(paras[3].runs.contains { $0.tocBlock != nil },
                       "обычный текст не должен получать tocBlock")
    }

    func testDocumentWithoutTocRoundTripsCleanly() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "просто текст", attributes: .init())]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let paras: [Paragraph] = back.sections.first?.blocks.compactMap {
            if case .paragraph(let p) = $0 { return p } else { return nil }
        } ?? []
        XCTAssertFalse(paras.contains { $0.runs.contains { $0.tocBlock != nil } },
                       "обычный документ не должен получать tocBlock")
    }
}
