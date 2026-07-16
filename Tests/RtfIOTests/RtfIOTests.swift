//
//  RtfIOTests.swift
//  v0.5.1: юнит-тесты RtfIO (2026-07-13).
//

import XCTest
@testable import DocxCore
@testable import RtfIO
import Foundation

final class RtfIOTests: XCTestCase {

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("docxedit-test-\(UUID().uuidString).\(ext)")
    }

    // v0.1.20: RTF-экспорт должен явно указывать documentType: .rtf, иначе
    // NSAttributedString сериализует как plain text и падает с ошибкой 66062
    // на не-ASCII (кириллице).
    func testCyrillicRtfExport() throws {
        let p = Paragraph(runs: [
            Run(text: "Привет, мир!", attributes: CharacterAttributes(bold: true)),
        ])
        let doc = DocumentModel(sections: [DocumentSection(blocks: [.paragraph(p)])])
        let url = tempURL("rtf")
        defer { try? FileManager.default.removeItem(at: url) }
        // Не должно бросить.
        XCTAssertNoThrow(try RtfIO.exportRTF(doc, to: url))
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
        // RTF-файл начинается с "{\rtf".
        let prefix = String(data: data.prefix(5), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("{\\rtf"), "не похоже на RTF: \(prefix)")
    }

    func testRtfRoundTrip() throws {
        let p = Paragraph(runs: [Run(text: "Hello, RTF!", attributes: CharacterAttributes(bold: true))])
        let doc = DocumentModel(sections: [DocumentSection(blocks: [.paragraph(p)])])
        let url = tempURL("rtf")
        defer { try? FileManager.default.removeItem(at: url) }
        try RtfIO.exportRTF(doc, to: url)
        let back = try RtfIO.importRTF(url: url)
        let paragraphs: [Paragraph] = back.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        let joined = paragraphs.flatMap { $0.runs }.map(\.text).joined()
        XCTAssertTrue(joined.contains("Hello, RTF!"), "текст утерян: \(joined)")
    }

    func testRtfMultiParagraphRoundTrip() throws {
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "first", attributes: .init())])),
            .paragraph(Paragraph(runs: [Run(text: "second", attributes: .init())])),
        ])])
        let url = tempURL("rtf")
        defer { try? FileManager.default.removeItem(at: url) }
        try RtfIO.exportRTF(doc, to: url)
        let back = try RtfIO.importRTF(url: url)
        let paragraphs: [Paragraph] = back.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        XCTAssertGreaterThanOrEqual(paragraphs.count, 2)
    }
}
