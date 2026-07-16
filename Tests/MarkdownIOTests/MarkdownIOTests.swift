//
//  MarkdownIOTests.swift
//  v0.5.1: юнит-тесты MarkdownIO (2026-07-13).
//

import XCTest
@testable import DocxCore
@testable import MarkdownIO

final class MarkdownIOTests: XCTestCase {

    func testHeadingImport() throws {
        let md = "# Заголовок 1\n\nОбычный текст."
        let doc = try MarkdownIO.importMarkdown(string: md)
        let paragraphs: [Paragraph] = doc.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        XCTAssertGreaterThanOrEqual(paragraphs.count, 2)
        // Первый абзац — заголовок с styleId = Heading1.
        XCTAssertEqual(paragraphs.first?.attributes.styleId, "Heading1")
    }

    func testBoldItalicImport() throws {
        let md = "**жирный** и *курсив*"
        let doc = try MarkdownIO.importMarkdown(string: md)
        let paragraphs: [Paragraph] = doc.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        let bold = paragraphs.flatMap { $0.runs }.first { $0.text.contains("жирный") }
        let italic = paragraphs.flatMap { $0.runs }.first { $0.text.contains("курсив") }
        XCTAssertTrue(bold?.attributes.bold ?? false, "не сохранён bold")
        XCTAssertTrue(italic?.attributes.italic ?? false, "не сохранён italic")
    }

    func testListImport() throws {
        let md = "- один\n- два\n- три"
        let doc = try MarkdownIO.importMarkdown(string: md)
        let paragraphs: [Paragraph] = doc.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(paragraphs.filter { $0.attributes.listInfo != nil }.count, 3)
    }

    func testExportRoundTripBoldItalic() throws {
        let md = "текст с **жирным** и *курсивом*"
        let doc = try MarkdownIO.importMarkdown(string: md)
        let out = MarkdownIO.exportMarkdown(doc)
        // Bold/italic-маркеры должны сохраниться (порядок/точность деталей —
        // не проверяем, только присутствие).
        XCTAssertTrue(out.contains("**"))
        XCTAssertTrue(out.contains("*"))
    }

    func testCyrillicCommonMark() throws {
        // Регрессия v0.1.20: экспорт кириллицы не должен ломаться.
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "Кириллица", attributes: .init())])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("Кириллица"), "кириллица потеряна")
    }
}
