//
//  OdtRoundTripTests.swift
//  v0.6.1 (R09): ODT import/export через NSAttributedString.
//

import XCTest
@testable import DocxCore
@testable import RtfIO

final class OdtRoundTripTests: XCTestCase {

    func testPlainTextRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "Привет, мир", attributes: .init())]))
        ])])
        let back = try OdtIO.importODT(data: try OdtIO.exportODT(m))
        let text = back.sections.first?.blocks.compactMap {
            if case .paragraph(let p) = $0 {
                return p.runs.map(\.text).joined()
            } else { return nil }
        }.joined() ?? ""
        XCTAssertTrue(text.contains("Привет"), "текст потерян в ODT round-trip")
    }

    func testBoldItalicRoundTrip() throws {
        var bold = CharacterAttributes(); bold.bold = true
        var italic = CharacterAttributes(); italic.italic = true
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "жирный", attributes: bold),
                Run(text: " и ", attributes: .init()),
                Run(text: "курсив", attributes: italic),
            ]))
        ])])
        let back = try OdtIO.importODT(data: try OdtIO.exportODT(m))
        let runs = back.sections.first?.blocks.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs } else { return [] }
        } ?? []
        XCTAssertTrue(runs.contains { $0.text.contains("жирный") && $0.attributes.bold },
                      "bold потерян в ODT")
        XCTAssertTrue(runs.contains { $0.text.contains("курсив") && $0.attributes.italic },
                      "italic потерян в ODT")
    }
}
