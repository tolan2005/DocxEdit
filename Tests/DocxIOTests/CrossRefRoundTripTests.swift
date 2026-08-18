//
//  CrossRefRoundTripTests.swift
//  v0.5.5 (R07): DOCX round-trip перекрёстных ссылок через <w:fldSimple w:instr=" REF ">.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class CrossRefRoundTripTests: XCTestCase {

    func testSingleCrossRefSurvivesRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "См. ", attributes: .init()),
                Run(text: "раздел 1", attributes: .init(), crossRef: "_Ref_intro"),
                Run(text: " далее.", attributes: .init()),
            ]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let runs = back.sections.first?.blocks.compactMap { block -> [Run]? in
            if case .paragraph(let p) = block { return p.runs } else { return nil }
        }.first ?? []
        let ref = runs.first { $0.crossRef != nil }
        XCTAssertEqual(ref?.crossRef, "_Ref_intro", "имя закладки cross-ref потеряно")
        XCTAssertEqual(ref?.text, "раздел 1", "текст cross-ref потерян")
    }

    func testMultipleCrossRefsInParagraph() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "См. ", attributes: .init()),
                Run(text: "гл. 1", attributes: .init(), crossRef: "chap1"),
                Run(text: " и ", attributes: .init()),
                Run(text: "гл. 2", attributes: .init(), crossRef: "chap2"),
            ]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let names = back.sections.first?.blocks.flatMap { block -> [String] in
            guard case .paragraph(let p) = block else { return [] }
            return p.runs.compactMap(\.crossRef)
        }.sorted() ?? []
        XCTAssertEqual(names, ["chap1", "chap2"])
    }

    func testCrossRefWithHyphenAndUnderscore() throws {
        // Имена закладок в Word часто вида "_Ref123456789" — не должны потеряться при парсе instr.
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "ссылка", attributes: .init(), crossRef: "_Ref123456789"),
            ]))
        ])])
        let back = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let ref = back.sections.first?.blocks.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs } else { return [] }
        }.first { $0.crossRef != nil }
        XCTAssertEqual(ref?.crossRef, "_Ref123456789")
    }
}
