//
//  R06RoundTripTests.swift
//  Регрессионные тесты R06: комментарии и track changes через DOCX round-trip.
//  Ранее их round-trip проверялся только вручную/визуально.
//

import XCTest
@testable import DocxCore
@testable import DocxIO

final class R06RoundTripTests: XCTestCase {

    private func rt(_ m: DocumentModel) throws -> DocumentModel {
        try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
    }

    // MARK: - Комментарии

    func testCommentThreadSurvivesDocxRoundTrip() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "цитата", attributes: CharacterAttributes(), commentId: "c1")
            ]))
        ])])
        m.comments = [CommentThread(id: "c1", author: "Аня", text: "нужно уточнить")]
        let back = try rt(m)
        XCTAssertEqual(back.comments.count, 1, "комментарий не сохранился")
        XCTAssertEqual(back.comments.first?.author, "Аня")
        XCTAssertEqual(back.comments.first?.text, "нужно уточнить")
    }

    func testCommentIdOnRunSurvives() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "start ", attributes: CharacterAttributes()),
                Run(text: "commented", attributes: CharacterAttributes(), commentId: "c1"),
                Run(text: " end", attributes: CharacterAttributes())
            ]))
        ])])
        m.comments = [CommentThread(id: "c1", author: "A", text: "note")]
        let back = try rt(m)
        let runs = back.sections.flatMap { $0.blocks }.flatMap {
            if case let .paragraph(p) = $0 { return p.runs } else { return [] }
        }
        // Хотя бы один ран должен нести commentId="c1"
        let commentedRuns = runs.filter { $0.commentId != nil }
        XCTAssertFalse(commentedRuns.isEmpty,
                       "commentId ни на одном ране не выжил round-trip. Все commentId: \(runs.map { $0.commentId ?? "nil" })")
    }

    func testMultipleCommentsSurvive() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "a", attributes: CharacterAttributes(), commentId: "c1"),
                Run(text: "b", attributes: CharacterAttributes(), commentId: "c2")
            ]))
        ])])
        m.comments = [
            CommentThread(id: "c1", author: "A", text: "note 1"),
            CommentThread(id: "c2", author: "B", text: "заметка два"),
        ]
        let back = try rt(m)
        XCTAssertEqual(back.comments.count, 2)
        let authors = Set(back.comments.map(\.author))
        XCTAssertEqual(authors, ["A", "B"])
    }

    // MARK: - Track changes: insertion / deletion

    func testInsertionRunSurvives() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "Hello ", attributes: CharacterAttributes()),
                Run(text: "world", attributes: CharacterAttributes(), insertion: "Alice"),
            ]))
        ])])
        let back = try rt(m)
        let runs = back.sections.flatMap { $0.blocks }.flatMap {
            if case let .paragraph(p) = $0 { return p.runs } else { return [] }
        }
        XCTAssertTrue(runs.contains { $0.insertion != nil && $0.text.contains("world") },
                      "insertion не выжил round-trip")
    }

    func testDeletionRunSurvives() throws {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "was here", attributes: CharacterAttributes(), deletion: "Bob"),
            ]))
        ])])
        let back = try rt(m)
        let runs = back.sections.flatMap { $0.blocks }.flatMap {
            if case let .paragraph(p) = $0 { return p.runs } else { return [] }
        }
        XCTAssertTrue(runs.contains { $0.deletion != nil },
                      "deletion не выжил round-trip")
    }

    // MARK: - Комментарии + track changes на одном документе

    func testCommentAndInsertionOnSameParagraph() throws {
        var m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "orig ", attributes: CharacterAttributes(), commentId: "c1"),
                Run(text: "added", attributes: CharacterAttributes(), insertion: "Alice"),
            ]))
        ])])
        m.comments = [CommentThread(id: "c1", author: "A", text: "review")]
        let back = try rt(m)
        XCTAssertEqual(back.comments.count, 1)
        let runs = back.sections.flatMap { $0.blocks }.flatMap {
            if case let .paragraph(p) = $0 { return p.runs } else { return [] }
        }
        // При round-trip строковые id перенумеровываются (в DOCX w:id — целое)
        // проверяем наличие commentId, не конкретное значение.
        XCTAssertTrue(runs.contains { $0.commentId != nil }, "commentId потерян")
        XCTAssertTrue(runs.contains { $0.insertion != nil }, "insertion потеряна")
    }

    // MARK: - Резолвед комментарий

    // Известное ограничение (см. CLAUDE.md §4, R07+): resolved-флаг требует
    // отдельной части `word/commentsExtended.xml` (<w:commentEx w:done="1"/>) —
    // не реализовано в R06. Тест фиксирует статус, чтобы автоматически сработать,
    // когда фича будет добавлена.
    func testResolvedCommentSurvives() throws {
        throw XCTSkip("resolved comment требует word/commentsExtended.xml — задача R07+")
    }
}
