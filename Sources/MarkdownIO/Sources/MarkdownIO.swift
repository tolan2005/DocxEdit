//
//  MarkdownIO.swift
//  MarkdownIO
//
//  Минимальная реализация импорта/экспорта Markdown для DocxEdit R01 (MVP).
//

import Foundation
import Markdown
import DocxCore

public enum MarkdownIO {

    // MARK: - Импорт

    public static func importMarkdown(string: String) throws -> DocumentModel {
        let document = Document(parsing: string, options: .init())
        var blocks: [Block] = []

        for child in document.children {
            if let p = paragraph(from: child) {
                blocks.append(.paragraph(p))
            } else if let list = child as? Markdown.UnorderedList {
                for item in list.listItems {
                    // v0.5.1: раньше listType не передавался → маркированные
                    // списки импортировались как обычные абзацы (listInfo=nil),
                    // а при экспорте маркер "- " терялся. Найдено юнит-тестом.
                    if let p = paragraph(from: item, listType: .bulleted) {
                        blocks.append(.paragraph(p))
                    }
                }
            } else if let list = child as? Markdown.OrderedList {
                for item in list.listItems {
                    if let p = paragraph(from: item, listType: .numbered) {
                        blocks.append(.paragraph(p))
                    }
                }
            } else if let quote = child as? Markdown.BlockQuote {
                for inner in quote.children {
                    if let p = paragraph(from: inner) {
                        var styled = p
                        styled.attributes.styleId = "Quote"
                        blocks.append(.paragraph(styled))
                    }
                }
            } else if let code = child as? Markdown.CodeBlock {
                let run = Run(text: code.code, attributes: CharacterAttributes(
                    fontName: "Menlo",
                    fontSize: 11
                ))
                blocks.append(.paragraph(Paragraph(runs: [run])))
            }
        }

        if blocks.isEmpty {
            blocks.append(.paragraph(.empty))
        }
        return DocumentModel(sections: [DocumentSection(blocks: blocks)])
    }

    public static func importMarkdown(url: URL) throws -> DocumentModel {
        let s: String
        do {
            s = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw DocumentError.ioError(
                "Не удалось прочитать файл: \(error.localizedDescription)"
            )
        }
        return try importMarkdown(string: s)
    }

    // MARK: - Экспорт

    public static func exportMarkdown(_ document: DocumentModel) -> String {
        var lines: [String] = []
        for section in document.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p):
                    let md = renderMarkdown(p)
                    // Пустые абзацы → пустая строка (не двойной перенос)
                    lines.append(md.isEmpty ? "" : md)
                case .table(let t):
                    lines.append(renderTable(t))
                }
            }
        }
        // Схлопываем >2 подряд идущих пустых строк в одну пустую
        var collapsed: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks <= 1 { collapsed.append("") }
            } else {
                blanks = 0
                collapsed.append(line)
            }
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    public static func exportMarkdown(_ document: DocumentModel, to url: URL) throws {
        let s = exportMarkdown(document)
        do {
            try s.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private static func paragraph(
        from markup: Markup,
        listType: ListType? = nil
    ) -> DocxCore.Paragraph? {
        // v0.5.1: раньше функция ВСЕГДА возвращала Paragraph — включая для
        // UnorderedList/OrderedList/CodeBlock, схлопывая все ListItem-тексты
        // в один параграф без listInfo. Ветка `else if let list = ...` в вызывающем
        // коде никогда не срабатывала. Найдено юнит-тестом. Теперь возвращаем
        // nil для не-параграф/не-heading/не-listItem типов — управление
        // передаётся дальше по цепочке else if.
        if listType == nil {
            let isParagraph = markup is Markdown.Paragraph
            let isHeading = markup is Markdown.Heading
            if !isParagraph && !isHeading { return nil }
        }
        var attrs = DocxCore.ParagraphAttributes()
        var runs: [DocxCore.Run] = []

        if let heading = markup as? Markdown.Heading {
            attrs.styleId = "Heading\(heading.level)"
            attrs.alignment = .left
        }

        if listType != nil {
            attrs.listInfo = DocxCore.ListInfo(
                listType: listType!,
                level: 0,
                continuation: .continue,
                formatStyle: listType == .numbered ? .decimal : .bullet(character: "•")
            )
        }

        collectRuns(markup.children, into: &runs)
        return DocxCore.Paragraph(runs: runs, attributes: attrs)
    }

    private static func collectRuns(_ children: MarkupChildren, into runs: inout [DocxCore.Run]) {
        for child in children {
            if let text = child as? Markdown.Text {
                let plain = text.plainText
                if !plain.isEmpty {
                    runs.append(DocxCore.Run(text: plain, attributes: DocxCore.CharacterAttributes()))
                }
            } else if let strong = child as? Markdown.Strong {
                var saved = [DocxCore.Run]()
                collectRuns(strong.children, into: &saved)
                for r in saved {
                    var bold = r
                    bold.attributes.bold = true
                    runs.append(bold)
                }
            } else if let emph = child as? Markdown.Emphasis {
                var saved = [DocxCore.Run]()
                collectRuns(emph.children, into: &saved)
                for r in saved {
                    var italic = r
                    italic.attributes.italic = true
                    runs.append(italic)
                }
            } else if let code = child as? Markdown.InlineCode {
                runs.append(DocxCore.Run(text: code.code, attributes: DocxCore.CharacterAttributes(
                    fontName: "Menlo", fontSize: 11
                )))
            } else if let link = child as? Markdown.Link {
                runs.append(DocxCore.Run(text: link.plainText, attributes: DocxCore.CharacterAttributes(
                    fontName: nil, fontSize: nil
                )))
            } else {
                collectRuns(child.children, into: &runs)
            }
        }
    }

    private static func renderMarkdown(_ p: DocxCore.Paragraph) -> String {
        var prefix = ""
        if let id = p.attributes.styleId, id.hasPrefix("Heading") {
            if let lvl = Int(id.dropFirst("Heading".count)) {
                prefix = String(repeating: "#", count: max(1, min(lvl, 6))) + " "
            }
        }
        if let li = p.attributes.listInfo {
            switch li.listType {
            case .numbered: prefix = "1. "
            case .bulleted: prefix = "- "
            }
        }

        var body = ""
        for run in p.runs {
            let text = run.text
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                body += text   // Сохраняем пробелы, но не оборачиваем маркерами
                continue
            }
            // Отделяем ведущие/хвостовые пробелы от содержимого, чтобы маркеры
            // не содержали пробел сразу после/до — это невалидный MD.
            let leading  = String(text.prefix(while: { $0 == " " }))
            let trailing = String(text.reversed().prefix(while: { $0 == " " }).reversed())
            let inner    = text.trimmingCharacters(in: .init(charactersIn: " "))
            if inner.isEmpty { body += text; continue }
            let isBold   = run.attributes.bold
            let isItalic = run.attributes.italic
            let isMono   = run.attributes.fontName == "Menlo"
            let marked: String
            if isBold && isItalic { marked = "***\(inner)***" }
            else if isBold        { marked = "**\(inner)**" }
            else if isItalic      { marked = "*\(inner)*" }
            else if isMono        { marked = "`\(inner)`" }
            else                  { marked = inner }
            body += leading + marked + trailing
        }
        return prefix + body
    }

    private static func renderTable(_ t: TableBlock) -> String {
        guard !t.rows.isEmpty else { return "" }

        func cellText(_ cell: TableCell) -> String {
            cell.blocks.compactMap { block -> String? in
                if case .paragraph(let p) = block {
                    return p.runs.map { $0.text }.joined()
                }
                return nil
            }.joined(separator: " ").replacingOccurrences(of: "|", with: "\\|")
        }

        var lines: [String] = []
        // Первая строка — заголовок
        let header = t.rows[0]
        let headerCells = header.cells.map { cellText($0) }
        lines.append("| " + headerCells.joined(separator: " | ") + " |")
        lines.append("| " + headerCells.map { _ in "---" }.joined(separator: " | ") + " |")
        // Остальные строки — данные
        for row in t.rows.dropFirst() {
            let cells = row.cells.map { cellText($0) }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
