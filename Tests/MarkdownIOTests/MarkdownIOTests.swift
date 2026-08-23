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

    // MARK: - v1.4.2 (ADR-049): blockquote / code fence / HR / списки / экранирование

    private func paragraphs(_ doc: DocumentModel) -> [Paragraph] {
        doc.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p } else { return nil }
        }
    }

    func testBlockquoteImportExport() throws {
        let doc = try MarkdownIO.importMarkdown(string: "> цитата\n> вторая строка")
        let ps = paragraphs(doc)
        // CommonMark: соседние строки цитаты — один абзац с soft break.
        XCTAssertEqual(ps.count, 1)
        XCTAssertEqual(ps[0].attributes.styleId, "Quote")
        XCTAssertTrue(ps[0].runs.map(\.text).joined().contains("цитата\nвторая строка"))
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("> цитата"), "blockquote не экспортирован: \(out)")
        XCTAssertTrue(out.contains("> вторая строка"))
    }

    func testCodeBlockImportExport() throws {
        let md = "```swift\nlet a = 1\nlet b = 2\n```"
        let doc = try MarkdownIO.importMarkdown(string: md)
        let ps = paragraphs(doc)
        XCTAssertEqual(ps.count, 2)
        XCTAssertTrue(ps.allSatisfy { $0.attributes.styleId == "CodeBlock" })
        XCTAssertEqual(ps[0].runs.first?.text, "let a = 1")
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("```"), "fence потерян: \(out)")
        XCTAssertTrue(out.contains("let a = 1\nlet b = 2"))
        // Внутри fence — без inline-маркеров/экранирования.
        XCTAssertFalse(out.contains("\\l"), "код не должен экранироваться")
    }

    func testHorizontalRuleImportExport() throws {
        let doc = try MarkdownIO.importMarkdown(string: "текст\n\n---\n\nпосле")
        let ps = paragraphs(doc)
        XCTAssertTrue(ps.contains { $0.attributes.styleId == "HorizontalRule" })
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("\n---\n") || out.hasPrefix("---\n") || out.hasSuffix("\n---"),
                      "HR не экспортирован: \(out)")
    }

    func testNestedListImport() throws {
        let md = "- верх\n  - вложенный\n  - второй\n- снова верх"
        let doc = try MarkdownIO.importMarkdown(string: md)
        let ps = paragraphs(doc).filter { $0.attributes.listInfo != nil }
        XCTAssertEqual(ps.count, 4)
        XCTAssertEqual(ps[0].attributes.listInfo?.level, 0)
        XCTAssertEqual(ps[1].attributes.listInfo?.level, 1)
        XCTAssertEqual(ps[2].attributes.listInfo?.level, 1)
        XCTAssertEqual(ps[3].attributes.listInfo?.level, 0)
    }

    func testNestedListExport() {
        let mk: (Int) -> Paragraph = { level in
            var attrs = ParagraphAttributes()
            attrs.listInfo = ListInfo(listType: .bulleted, level: level,
                                      continuation: .continue,
                                      formatStyle: .bullet(character: "•"))
            return Paragraph(runs: [Run(text: "item\(level)", attributes: .init())],
                             attributes: attrs)
        }
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(mk(0)), .paragraph(mk(1)),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("- item0"), "уровень 0: \(out)")
        XCTAssertTrue(out.contains("  - item1"), "уровень 1 должен иметь отступ: \(out)")
    }

    func testStrikethroughImportExport() throws {
        let doc = try MarkdownIO.importMarkdown(string: "~~удалено~~")
        let strike = paragraphs(doc).flatMap { $0.runs }.first { $0.text.contains("удалено") }
        XCTAssertTrue(strike?.attributes.strikethrough ?? false)
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("~~удалено~~"), "~~ не экспортировано: \(out)")
    }

    func testLinkImportExport() throws {
        let doc = try MarkdownIO.importMarkdown(string: "[сайт](https://example.com)")
        let link = paragraphs(doc).flatMap { $0.runs }.first { $0.text.contains("сайт") }
        XCTAssertEqual(link?.hyperlink, "https://example.com")
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("[сайт](https://example.com)"), "ссылка: \(out)")
    }

    func testSpecialCharsEscaped() {
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "звёздочка * и _подчёрк_", attributes: .init())])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("\\*"), "* должен экранироваться: \(out)")
        XCTAssertTrue(out.contains("\\_"), "_ должен экранироваться: \(out)")
    }

    func testLineLeadingMarkerEscaped() {
        // Абзац, начинающийся с «#»/«-», не должен стать заголовком/списком
        // при повторном открытии.
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "# не заголовок", attributes: .init())])),
            .paragraph(Paragraph(runs: [Run(text: "- не список", attributes: .init())])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("\\# не заголовок"), out)
        XCTAssertTrue(out.contains("\\- не список"), out)
        // Ре-импорт: по-прежнему обычные абзацы, не heading/list.
        if let back = try? MarkdownIO.importMarkdown(string: out) {
            let ps = paragraphs(back)
            XCTAssertNil(ps[0].attributes.styleId)
            XCTAssertNil(ps[1].attributes.listInfo)
        }
    }

    func testParagraphsSeparatedByBlankLine() {
        // GitHub сливает соседние строки в один абзац — экспорт обязан
        // разделять абзацы пустой строкой.
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "первый", attributes: .init())])),
            .paragraph(Paragraph(runs: [Run(text: "второй", attributes: .init())])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("первый\n\nвторой"), "абзацы должны разделяться: \(out)")
        // Round-trip: два абзаца остаются двумя.
        if let back = try? MarkdownIO.importMarkdown(string: out) {
            XCTAssertEqual(paragraphs(back).count, 2)
        }
    }

    func testListItemsNotSeparatedByBlankLines() {
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "раз", attributes: .init())],
                                 attributes: {
                var a = ParagraphAttributes()
                a.listInfo = ListInfo(listType: .bulleted, level: 0,
                                      continuation: .continue, formatStyle: .bullet(character: "•"))
                return a
            }())),
            .paragraph(Paragraph(runs: [Run(text: "два", attributes: .init())],
                                 attributes: {
                var a = ParagraphAttributes()
                a.listInfo = ListInfo(listType: .bulleted, level: 0,
                                      continuation: .continue, formatStyle: .bullet(character: "•"))
                return a
            }())),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("- раз\n- два"), "элементы списка не должны разделяться: \(out)")
    }

    func testInlineCodeNotEscaped() {
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [Run(text: "a*b_c", attributes: CharacterAttributes(fontName: "Menlo", fontSize: 11))])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("`a*b_c`"), "inline-код не должен экранироваться: \(out)")
    }

    // v1.4.3: pretty-print таблиц — колонки выравниваются пробелами.
    private func tableDoc() -> DocumentModel {
        func cell(_ text: String) -> TableCell {
            TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: text, attributes: .init())]))])
        }
        return DocumentModel(sections: [DocumentSection(blocks: [
            .table(TableBlock(rows: [
                TableRow(cells: [cell("Имя"), cell("Возраст")]),
                TableRow(cells: [cell("Я"), cell("100")]),
            ])),
        ])])
    }

    func testTablePlainExport() {
        let out = MarkdownIO.exportMarkdown(tableDoc(), prettyTables: false)
        XCTAssertTrue(out.contains("| Имя | Возраст |"), out)
        XCTAssertTrue(out.contains("| --- | --- |"), out)
    }

    func testTablePrettyExport() {
        let out = MarkdownIO.exportMarkdown(tableDoc(), prettyTables: true)
        // Ширина колонки — по самой длинной ячейке (колонка 1: «Имя»=3; колонка 2: «Возраст»=7).
        XCTAssertTrue(out.contains("| Имя | Возраст |"), out)
        XCTAssertTrue(out.contains("| Я   | 100     |"), out)
        // Разделитель — по ширине колонки (минимум 3).
        XCTAssertTrue(out.contains("| --- | ------- |"), out)
    }

    func testTablePrettyRoundTrip() throws {
        // Pretty-вывод — валидный MD: таблица переживает round-trip.
        let out = MarkdownIO.exportMarkdown(tableDoc(), prettyTables: true)
        let back = try MarkdownIO.importMarkdown(string: out)
        let hasTable = back.sections.flatMap { $0.blocks }.contains {
            if case .table = $0 { return true } else { return false }
        }
        XCTAssertTrue(hasTable, "таблица потеряна при round-trip: \(out)")
    }

    func testHighlightAndSubSupExport() {
        var attrs = CharacterAttributes()
        attrs.highlightColor = CodableColor(red: 1, green: 1, blue: 0)
        var sup = CharacterAttributes()
        sup.superscript = true
        let doc = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "маркер", attributes: attrs),
                Run(text: " ", attributes: .init()),
                Run(text: "2", attributes: sup),
            ])),
        ])])
        let out = MarkdownIO.exportMarkdown(doc)
        XCTAssertTrue(out.contains("==маркер=="), out)
        XCTAssertTrue(out.contains("<sup>2</sup>"), out)
    }

    // MARK: - v1.6.2: YAML front-matter и wiki-ссылки

    /// YAML front-matter: снимается при импорте, возвращается при экспорте
    /// (passthrough, не попадает в текст документа).
    func testYamlFrontMatterRoundTrip() throws {
        let md = """
        ---
        title: Мой документ
        tags: [docx, test]
        ---
        # Привет
        """
        let model = try MarkdownIO.importMarkdown(string: md)
        XCTAssertEqual(model.yamlFrontMatter, "title: Мой документ\ntags: [docx, test]")
        // Текст front-matter не должен попасть в абзацы.
        let texts = model.sections.flatMap { $0.blocks }.compactMap { b -> String? in
            if case .paragraph(let p) = b { return p.runs.map(\.text).joined() }
            return nil
        }.joined()
        XCTAssertFalse(texts.contains("title:"), texts)
        // Экспорт возвращает блок первым.
        let out = MarkdownIO.exportMarkdown(model)
        XCTAssertTrue(out.hasPrefix("---\ntitle: Мой документ\ntags: [docx, test]\n---"), out)
    }

    /// Wiki-ссылки Obsidian: [[Страница]] и [[Страница|Текст]] → hyperlink
    /// "wiki:…" в модели, обратно — синтаксис [[…]].
    func testWikiLinksRoundTrip() throws {
        let md = "смотри [[Главная]] и [[Главная|домой]]\n"
        let model = try MarkdownIO.importMarkdown(string: md)
        let runs = model.sections.flatMap { $0.blocks }.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs }
            return []
        }
        let links = runs.filter { $0.hyperlink?.hasPrefix(MarkdownIO.wikiLinkPrefix) == true }
        XCTAssertEqual(links.count, 2, "wiki-ссылки не распознаны: \(runs)")
        XCTAssertEqual(links[0].hyperlink, "wiki:Главная")
        XCTAssertEqual(links[0].text, "Главная")
        XCTAssertEqual(links[1].text, "домой")
        // Экспорт: полная форма для label≠target, короткая для совпадающих.
        let out = MarkdownIO.exportMarkdown(model)
        XCTAssertTrue(out.contains("[[Главная]]"), out)
        XCTAssertTrue(out.contains("[[Главная|домой]]"), out)
    }

    /// Wiki-ссылка внутри code fence НЕ переписывается.
    func testWikiLinkInCodeFenceUntouched() throws {
        let md = "```\n[[не-ссылка]]\n```\n"
        let model = try MarkdownIO.importMarkdown(string: md)
        let texts = model.sections.flatMap { $0.blocks }.compactMap { b -> String? in
            if case .paragraph(let p) = b { return p.runs.map(\.text).joined() }
            return nil
        }.joined()
        XCTAssertTrue(texts.contains("[[не-ссылка]]"), texts)
    }
}
