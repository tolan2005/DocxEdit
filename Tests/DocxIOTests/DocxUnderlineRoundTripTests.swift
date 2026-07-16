//
//  DocxUnderlineRoundTripTests.swift
//  Регрессионные тесты фиксов моста v0.5.2:
//  - underline .double/.dotted/.dashed сохраняется в DOCX (не схлопывается в .single).
//  - Точные значения цветов (#FF0000 и т.п.) не дрейфуют.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class DocxUnderlineRoundTripTests: XCTestCase {

    private func rt(_ m: DocumentModel) throws -> DocumentModel {
        try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
    }

    private func firstRun(_ m: DocumentModel) -> Run? {
        for section in m.sections {
            for block in section.blocks {
                if case let .paragraph(p) = block, let r = p.runs.first {
                    return r
                }
            }
        }
        return nil
    }

    // MARK: - Underline

    func testDoubleUnderlineSurvivesDocxRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "double", attributes: CharacterAttributes(underline: .double))
            ]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(firstRun(back)?.attributes.underline, .double)
    }

    func testDottedUnderlineSurvivesDocxRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "dot", attributes: CharacterAttributes(underline: .dotted))
            ]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(firstRun(back)?.attributes.underline, .dotted)
    }

    func testDashedUnderlineSurvivesDocxRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "dash", attributes: CharacterAttributes(underline: .dashed))
            ]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(firstRun(back)?.attributes.underline, .dashed)
    }

    // MARK: - Точный цвет (регрессия calibrated → sRGB)

    func testExactRedColorSurvivesDocx() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "x", attributes: CharacterAttributes(
                    textColor: CodableColor.fromHex("#FF0000")!))
            ]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(firstRun(back)?.attributes.textColor?.hexString, "#FF0000",
                       "цвет дрейфует при DOCX round-trip (регрессия calibrated RGB)")
    }

    func testExactBlueColorSurvivesDocx() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "x", attributes: CharacterAttributes(
                    textColor: CodableColor.fromHex("#0000FF")!))
            ]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(firstRun(back)?.attributes.textColor?.hexString, "#0000FF")
    }
}
