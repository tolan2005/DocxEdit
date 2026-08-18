//
//  DocxIOTests.swift
//  DocxIOTests
//
//  Базовые тесты модуля DocxIO.
//

import XCTest
@testable import DocxCore
@testable import DocxIO
import MarkdownIO

final class DocxIOTests: XCTestCase {

    func testExportEmptyDocument() throws {
        let doc = DocumentModel()
        let data = try DocxIO.exportDocx(doc)
        XCTAssertGreaterThan(data.count, 0, "Exported DOCX must be non-empty")
    }

    func testExportAndImportSimpleText() throws {
        let p = Paragraph(runs: [Run(text: "Hello, world!", attributes: CharacterAttributes())])
        let doc = DocumentModel(sections: [DocumentSection(blocks: [.paragraph(p)])])
        let data = try DocxIO.exportDocx(doc)

        // Проверяем, что это валибный ZIP.
        let archive = try ZIPArchive(data: data)
        XCTAssertTrue(archive.hasEntry(named: "word/document.xml"))
    }

    func testExportContainsContentTypes() throws {
        let doc = DocumentModel()
        let data = try DocxIO.exportDocx(doc)
        let archive = try ZIPArchive(data: data)
        XCTAssertTrue(archive.hasEntry(named: "[Content_Types].xml"))
        XCTAssertTrue(archive.hasEntry(named: "_rels/.rels"))
    }

    func testMarkdownRoundTrip() {
        let md = "# Title\n\nHello, **world**!"
        let doc = try? MarkdownIO.importMarkdown(string: md)
        XCTAssertNotNil(doc)
        let exported = MarkdownIO.exportMarkdown(doc!)
        XCTAssertTrue(exported.contains("Hello, **world**!"))
    }
}

/// Минимальная обёртка над ZIPFoundation для тестов.
import ZIPFoundation
private final class ZIPArchive {
    let archive: Archive
    init(data: Data) throws {
        self.archive = try Archive(data: data, accessMode: .read)
    }
    func hasEntry(named path: String) -> Bool {
        for e in archive where e.path == path { return true }
        return false
    }
}
