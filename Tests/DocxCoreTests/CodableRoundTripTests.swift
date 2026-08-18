//
//  CodableRoundTripTests.swift
//  DocxCoreTests
//
//  DocumentModel сериализуется в JSON для autorecover (v0.2.6). Проверяем,
//  что JSON round-trip не теряет ни одного поля — иначе восстановление после
//  краша даст неполный документ.
//

import XCTest
@testable import DocxCore
import Foundation

final class CodableRoundTripTests: XCTestCase {

    private func rt(_ m: DocumentModel) throws -> DocumentModel {
        let data = try JSONEncoder().encode(m)
        return try JSONDecoder().decode(DocumentModel.self, from: data)
    }

    // MARK: - Базовое

    func testEmptyModelRoundTrip() throws {
        let m = DocumentModel(sections: [])
        let back = try rt(m)
        XCTAssertEqual(back.sections.count, 0)
    }

    func testPlainTextRoundTrip() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "hello", attributes: .init())]))
        ])])
        let back = try rt(m)
        XCTAssertEqual(back.sections.first?.blocks.count, 1)
    }

    // MARK: - Все character-атрибуты

    func testAllCharacterAttributesRoundTrip() throws {
        let ca = CharacterAttributes(
            fontName: "Helvetica", fontSize: 14,
            bold: true, italic: true,
            underline: .double,
            strikethrough: true,
            textColor: CodableColor.fromHex("#123456")!,
            highlightColor: CodableColor.fromHex("#FFFF00")!,
            superscript: false, subscript: true,
            smallCaps: true, allCaps: false,
            styleId: "Strong"
        )
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "x", attributes: ca)]))
        ])])
        let back = try rt(m)
        let got = back.sections.first?.blocks.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.first?.attributes } else { return nil }
        }.first
        XCTAssertEqual(got?.fontName, "Helvetica")
        XCTAssertEqual(got?.fontSize, 14)
        XCTAssertEqual(got?.bold, true)
        XCTAssertEqual(got?.italic, true)
        XCTAssertEqual(got?.underline, .double)
        XCTAssertEqual(got?.strikethrough, true)
        XCTAssertEqual(got?.textColor?.hexString, "#123456")
        XCTAssertEqual(got?.highlightColor?.hexString, "#FFFF00")
        XCTAssertEqual(got?.subscript, true)
        XCTAssertEqual(got?.smallCaps, true)
        XCTAssertEqual(got?.styleId, "Strong")
    }

    // MARK: - Все paragraph-атрибуты

    func testAllParagraphAttributesRoundTrip() throws {
        var pa = ParagraphAttributes()
        pa.alignment = .justify
        pa.lineSpacing = .multiple(1.75)
        pa.spaceBefore = 12
        pa.spaceAfter = 6
        pa.leftIndent = 24
        pa.rightIndent = 18
        pa.firstLineIndent = 8
        pa.hangingIndent = 4
        pa.styleId = "Heading2"
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())], attributes: pa))
        ])])
        let back = try rt(m)
        let got = back.sections.first?.blocks.compactMap {
            if case let .paragraph(p) = $0 { return p.attributes } else { return nil }
        }.first
        XCTAssertEqual(got?.alignment, .justify)
        if case .multiple(let v) = got?.lineSpacing { XCTAssertEqual(v, 1.75) }
        else { XCTFail("lineSpacing не .multiple: \(String(describing: got?.lineSpacing))") }
        XCTAssertEqual(got?.spaceBefore, 12)
        XCTAssertEqual(got?.spaceAfter, 6)
        XCTAssertEqual(got?.leftIndent, 24)
        XCTAssertEqual(got?.rightIndent, 18)
        XCTAssertEqual(got?.firstLineIndent, 8)
        XCTAssertEqual(got?.hangingIndent, 4)
        XCTAssertEqual(got?.styleId, "Heading2")
    }

    // MARK: - PageSettings

    func testPageSettingsRoundTrip() throws {
        var m = DocumentModel(sections: [])
        m.pageSettings = PageSettings(
            paperSize: .a4,
            orientation: .landscape,
            margins: PageMargins(top: 40, bottom: 40, left: 60, right: 60)
        )
        let back = try rt(m)
        XCTAssertEqual(back.pageSettings.paperSize, .a4)
        XCTAssertEqual(back.pageSettings.orientation, .landscape)
        XCTAssertEqual(back.pageSettings.margins.top, 40)
    }

    // MARK: - Комментарии

    func testCommentsCodableRoundTrip() throws {
        var m = DocumentModel(sections: [])
        m.comments = [
            CommentThread(id: "c1", author: "Аня", text: "Заметка"),
            CommentThread(id: "c2", author: "Bob", text: "Note", resolved: true),
        ]
        let back = try rt(m)
        XCTAssertEqual(back.comments.count, 2)
        XCTAssertEqual(back.comments[0].author, "Аня")
        XCTAssertEqual(back.comments[1].resolved, true)
    }

    // MARK: - Комбинация: полноразмерный документ

    func testFullDocumentCodableRoundTrip() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "заголовок", attributes: CharacterAttributes(bold: true))
            ], attributes: {
                var p = ParagraphAttributes(); p.styleId = "Heading1"; return p
            }())),
            .paragraph(Paragraph(runs: [
                Run(text: "тело ", attributes: .init()),
                Run(text: "жирное", attributes: CharacterAttributes(bold: true)),
            ]))
        ])])
        m.metadata.title = "Тест"
        m.metadata.author = "Клод"
        let back = try rt(m)
        XCTAssertEqual(back.metadata.title, "Тест")
        XCTAssertEqual(back.metadata.author, "Клод")
        let paragraphs = back.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs.first?.attributes.styleId, "Heading1")
    }

    // MARK: - JSON стабилен (детерминированность)

    func testJsonIsDeterministicForSameModel() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "x", attributes: .init())]))
        ])])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let a = try enc.encode(m)
        let b = try enc.encode(m)
        XCTAssertEqual(a, b, "JSON encoding не детерминирован — сломает diff в autorecover")
    }
}
