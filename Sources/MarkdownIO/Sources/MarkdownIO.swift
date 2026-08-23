//
//  MarkdownIO.swift
//  MarkdownIO
//
//  Импорт/экспорт Markdown для DocxEdit.
//  v1.4.2 (ADR-049): blockquote, fenced code blocks, тематический разрыв (HR),
//  вложенные списки, зачёркивание, гиперссылки, экранирование спецсимволов,
//  пустые строки-разделители блоков (корректный рендер на GitHub).
//

import Foundation
import Markdown
import DocxCore

public enum MarkdownIO {

    // MARK: - Импорт

    /// Префикс wiki-ссылки Obsidian в `Run.hyperlink`: "wiki:Target"
    /// (при экспорте рендерится обратно как `[[Target]]` / `[[Target|label]]`).
    public static let wikiLinkPrefix = "wiki:"

    public static func importMarkdown(string: String) throws -> DocumentModel {
        // v1.6.2: YAML front-matter (--- \n key: value… \n ---) в начале файла —
        // снимаем перед парсингом, сохраняем сырым в модель (passthrough
        // при экспорте; редактирования в UI нет).
        var yaml: String? = nil
        var body = string
        if string.hasPrefix("---\n") || string.hasPrefix("---\r\n") {
            let nl = string.hasPrefix("---\r\n") ? "\r\n" : "\n"
            let rest = String(string.dropFirst(3 + nl.count))
            // Закрывающая строка --- на своей строке.
            if let closeRange = rest.range(of: "\n---\(nl)") ?? rest.range(of: "\n---\n") {
                yaml = String(rest[..<closeRange.lowerBound])
                body = String(rest[closeRange.upperBound...])
            }
        }
        // v1.6.2: wiki-ссылки Obsidian [[Target]] / [[Target|Label]] → markdown
        // [Label](wiki:Target). swift-markdown их не знает (останутся текстом).
        // Пропускаем строки внутри fenced code-блоков.
        body = rewriteWikiLinks(body)

        let document = Document(parsing: body, options: .init())
        var blocks: [Block] = []

        for child in document.children {
            importBlock(child, into: &blocks)
        }

        if blocks.isEmpty {
            blocks.append(.paragraph(.empty))
        }
        var model = DocumentModel(sections: [DocumentSection(blocks: blocks)])
        model.yamlFrontMatter = yaml
        return model
    }

    /// [[Target]] / [[Target|Label]] → [Label](wiki:Target), вне code fences.
    private static func rewriteWikiLinks(_ s: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"\[\[([^\]\|]+)(?:\|([^\]]+))?\]"#) else { return s }
        var out: [String] = []
        var inFence = false
        for line in s.components(separatedBy: "\n") {
            if line.hasPrefix("```") { inFence.toggle(); out.append(line); continue }
            guard !inFence else { out.append(line); continue }
            let ns = line as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let target = ns.substring(with: m.range(at: 1))
                let label = m.range(at: 2).location != NSNotFound
                    ? ns.substring(with: m.range(at: 2)) : target
                result += "[\(label)](\(wikiLinkPrefix)\(target))"
                last = m.range.upperBound
            }
            result += ns.substring(from: last)
            out.append(result)
        }
        return out.joined(separator: "\n")
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

    /// Разбирает один блочный элемент верхнего уровня (или вложенный в список/цитату).
    private static func importBlock(_ child: Markup, into blocks: inout [Block]) {
        if let p = paragraph(from: child) {
            blocks.append(.paragraph(p))
        } else if let list = child as? Markdown.UnorderedList {
            importList(list, listType: .bulleted, level: 0, into: &blocks)
        } else if let list = child as? Markdown.OrderedList {
            importList(list, listType: .numbered, level: 0, into: &blocks)
        } else if let quote = child as? Markdown.BlockQuote {
            for inner in quote.children {
                if var p = paragraph(from: inner) {
                    p.attributes.styleId = "Quote"
                    // Визуальный отступ цитаты — на уровне абзаца, раны не
                    // трогаем (иначе экспорт обернул бы их в *...*).
                    p.attributes.leftIndent = 36
                    blocks.append(.paragraph(p))
                } else {
                    // Вложенные списки/код внутри цитаты — как обычные блоки.
                    importBlock(inner, into: &blocks)
                }
            }
        } else if let code = child as? Markdown.CodeBlock {
            // v1.4.2: fenced code — каждая строка отдельным абзацом стиля
            // CodeBlock (экспорт сгруппирует обратно в один fence).
            // Хвостовые пустые строки (финальный \n в code.code) отбрасываем.
            var lines = code.code.split(separator: "\n", omittingEmptySubsequences: false)
            while lines.last?.isEmpty == true { lines.removeLast() }
            if lines.isEmpty { lines = [""] }
            for line in lines {
                var attrs = DocxCore.ParagraphAttributes()
                attrs.styleId = "CodeBlock"
                let run = Run(text: String(line), attributes: CharacterAttributes(
                    fontName: "Menlo",
                    fontSize: 11
                ))
                blocks.append(.paragraph(Paragraph(runs: [run], attributes: attrs)))
            }
        } else if child is Markdown.ThematicBreak {
            // v1.4.2: горизонтальная линия --- / *** / ___.
            var attrs = DocxCore.ParagraphAttributes()
            attrs.styleId = "HorizontalRule"
            blocks.append(.paragraph(Paragraph(runs: [], attributes: attrs)))
        } else if let table = child as? Markdown.Table {
            // v1.4.3: GFM-таблица → TableBlock (первая строка — заголовок).
            func importCell(_ cell: Markdown.Table.Cell) -> TableCell {
                var runs: [DocxCore.Run] = []
                collectRuns(cell.children, into: &runs)
                return TableCell(blocks: [.paragraph(Paragraph(runs: runs))])
            }
            var rows: [TableRow] = [
                TableRow(cells: table.head.cells.map { importCell($0) }, isHeader: true)
            ]
            rows.append(contentsOf: table.body.rows.map { row in
                TableRow(cells: row.cells.map { importCell($0) })
            })
            blocks.append(.table(TableBlock(rows: rows)))
        }
    }

    /// v1.4.2: рекурсивный разбор списка с уровнями вложенности.
    private static func importList(
        _ list: some Markup,
        listType: ListType,
        level: Int,
        into blocks: inout [Block]
    ) {
        let items: [Markdown.ListItem]
        if let ul = list as? Markdown.UnorderedList {
            items = Array(ul.listItems)
        } else if let ol = list as? Markdown.OrderedList {
            items = Array(ol.listItems)
        } else {
            return
        }
        for item in items {
            for child in item.children {
                if let p = paragraph(from: child) {
                    var itemP = p
                    itemP.attributes.listInfo = DocxCore.ListInfo(
                        listType: listType,
                        level: level,
                        continuation: .continue,
                        formatStyle: listType == .numbered ? .decimal : .bullet(character: "•")
                    )
                    blocks.append(.paragraph(itemP))
                } else if child is Markdown.UnorderedList {
                    importList(child, listType: .bulleted, level: level + 1, into: &blocks)
                } else if child is Markdown.OrderedList {
                    importList(child, listType: .numbered, level: level + 1, into: &blocks)
                } else {
                    importBlock(child, into: &blocks)
                }
            }
        }
    }

    // MARK: - Экспорт

    public static func exportMarkdown(_ document: DocumentModel, prettyTables: Bool = false) -> String {
        let blocks = document.sections.flatMap { $0.blocks }
        var out: [String] = []
        var i = 0
        while i < blocks.count {
            switch blocks[i] {
            case .paragraph(let p) where p.attributes.styleId == "CodeBlock":
                // v1.4.2: последовательные абзацы CodeBlock → один fence.
                var codeLines: [String] = []
                while i < blocks.count,
                      case .paragraph(let q) = blocks[i],
                      q.attributes.styleId == "CodeBlock" {
                    codeLines.append(q.runs.map(\.text).joined())
                    i += 1
                }
                out.append("```")
                out.append(contentsOf: codeLines)
                out.append("```")
            case .paragraph(let p) where p.attributes.styleId == "HorizontalRule":
                out.append("---")
                i += 1
            case .paragraph(let p) where p.attributes.listInfo != nil:
                // Элементы списка идут подряд без пустых строк между ними.
                while i < blocks.count,
                      case .paragraph(let q) = blocks[i],
                      q.attributes.listInfo != nil {
                    out.append(renderMarkdown(q))
                    i += 1
                }
            case .paragraph(let p):
                out.append(renderMarkdown(p))
                i += 1
            case .table(let t):
                out.append(renderTable(t, pretty: prettyTables))
                i += 1
            }
            // Пустая строка-разделитель между блоками — иначе GitHub сливает
            // соседние абзацы в один (soft wrap), а список «прилипает» к тексту.
            out.append("")
        }
        // Схлопываем >1 подряд идущих пустых строк в одну.
        var collapsed: [String] = []
        var blanks = 0
        for line in out {
            if line.isEmpty {
                blanks += 1
                if blanks <= 1 { collapsed.append("") }
            } else {
                blanks = 0
                collapsed.append(line)
            }
        }
        var result = collapsed.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        // v1.6.2: YAML front-matter — обратно в начало файла.
        if let yaml = document.yamlFrontMatter, !yaml.isEmpty {
            result = "---\n\(yaml)\n---\n\n" + result
        }
        return result
    }

    public static func exportMarkdown(_ document: DocumentModel, to url: URL) throws {
        try exportMarkdown(document, prettyTables: false, to: url)
    }

    public static func exportMarkdown(_ document: DocumentModel, prettyTables: Bool, to url: URL) throws {
        let s = exportMarkdown(document, prettyTables: prettyTables)
        do {
            try s.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers: импорт

    private static func paragraph(
        from markup: Markup
    ) -> DocxCore.Paragraph? {
        let isParagraph = markup is Markdown.Paragraph
        let isHeading = markup is Markdown.Heading
        guard isParagraph || isHeading else { return nil }

        var attrs = DocxCore.ParagraphAttributes()
        var runs: [DocxCore.Run] = []
        collectRuns(markup.children, into: &runs)

        if let heading = markup as? Markdown.Heading {
            attrs.styleId = "Heading\(heading.level)"
            attrs.alignment = .left
            // v1.4.2: визуальный размер заголовка «запекаем» в раны, чтобы
            // открытый .md сразу выглядел WYSIWYG (мост не каскадирует стили
            // при рендере — только applyParagraphStyle в редакторе).
            if let def = StandardParagraphStyle.find(id: "Heading\(heading.level)")?.def,
               let size = def.fontSize {
                runs = runs.map { r in
                    var nr = r
                    if nr.attributes.fontSize == nil { nr.attributes.fontSize = size }
                    return nr
                }
            }
        }
        return DocxCore.Paragraph(runs: runs, attributes: attrs)
    }

    private static func collectRuns(_ children: MarkupChildren, into runs: inout [DocxCore.Run]) {
        for child in children {
            if let text = child as? Markdown.Text {
                let plain = text.plainText
                if !plain.isEmpty {
                    runs.append(DocxCore.Run(text: plain, attributes: DocxCore.CharacterAttributes()))
                }
            } else if child is Markdown.SoftBreak || child is Markdown.LineBreak {
                // v1.4.2: перенос строки внутри абзаца (soft/hard break) —
                // сохраняем как \n, иначе строки слипались («цитатавторая»).
                runs.append(DocxCore.Run(text: "\n", attributes: DocxCore.CharacterAttributes()))
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
            } else if let strike = child as? Markdown.Strikethrough {
                // v1.4.2: GFM ~~зачёркнутый~~.
                var saved = [DocxCore.Run]()
                collectRuns(strike.children, into: &saved)
                for r in saved {
                    var sr = r
                    sr.attributes.strikethrough = true
                    runs.append(sr)
                }
            } else if let code = child as? Markdown.InlineCode {
                runs.append(DocxCore.Run(text: code.code, attributes: DocxCore.CharacterAttributes(
                    fontName: "Menlo", fontSize: 11
                )))
            } else if let link = child as? Markdown.Link {
                // v1.4.2: URL ссылки больше не теряется.
                var saved = [DocxCore.Run]()
                collectRuns(link.children, into: &saved)
                if saved.isEmpty, !link.plainText.isEmpty {
                    saved = [DocxCore.Run(text: link.plainText, attributes: DocxCore.CharacterAttributes())]
                }
                for r in saved {
                    var lr = r
                    lr.hyperlink = link.destination
                    runs.append(lr)
                }
            } else if let image = child as? Markdown.Image {
                // v1.4.2: внешние картинки (URL/путь) вставляем как текст-ссылку —
                // скачивание/встраивание бинарных данных не делаем (приватность, ADR-008).
                let alt = image.plainText.isEmpty ? "image" : image.plainText
                var r = DocxCore.Run(text: alt, attributes: DocxCore.CharacterAttributes())
                r.hyperlink = image.source
                runs.append(r)
            } else {
                collectRuns(child.children, into: &runs)
            }
        }
    }

    // MARK: - Helpers: экспорт

    /// Экранирование MD-спецсимволов в обычном тексте (v1.4.2).
    /// Внутри `code` и fenced-блоков НЕ применяется.
    private static func escapeMd(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\", "*", "_", "`", "[", "]":
                r.append("\\")
                r.append(ch)
            default:
                r.append(ch)
            }
        }
        return r
    }

    private static func renderMarkdown(_ p: DocxCore.Paragraph) -> String {
        var prefix = ""
        var isQuote = false
        if let id = p.attributes.styleId {
            if id.hasPrefix("Heading"), let lvl = Int(id.dropFirst("Heading".count)) {
                prefix = String(repeating: "#", count: max(1, min(lvl, 6))) + " "
            } else if id == "Quote" {
                isQuote = true
            }
        }
        if let li = p.attributes.listInfo {
            // v1.4.2: уровень вложенности — отступ 2 пробела на уровень.
            let indent = String(repeating: "  ", count: li.level)
            switch li.listType {
            case .numbered: prefix = indent + "1. "
            case .bulleted: prefix = indent + "- "
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
            body += leading + renderRun(run, inner: inner) + trailing
        }

        // v1.4.2: строка, начинающаяся со спец-маркера (#, >, -, +, «1.»),
        // при обычном абзаце превратится в заголовок/список/цитату при
        // ре-импорте — экранируем первый символ.
        if prefix.isEmpty, let first = body.first, "#>-+".contains(first) {
            body = "\\" + body
        } else if prefix.isEmpty, body.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            body = "\\" + body
        }

        if isQuote {
            // Цитата: каждая строка тела получает префикс "> ".
            let quoted = body.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
            return quoted
        }
        return prefix + body
    }

    /// Рендер одного рана с inline-маркерами (v1.4.2: ~~, ссылки, <u>, <sub>/<sup>, ==).
    private static func renderRun(_ run: DocxCore.Run, inner: String) -> String {
        let a = run.attributes
        let isMono = a.fontName == "Menlo" || a.styleId == "CodeChar"
        var marked = isMono ? "`\(inner)`" : escapeMd(inner)
        if !isMono {
            if a.bold && a.italic { marked = "***\(marked)***" }
            else if a.bold        { marked = "**\(marked)**" }
            else if a.italic      { marked = "*\(marked)*" }
            if a.strikethrough       { marked = "~~\(marked)~~" }
            if a.highlightColor != nil { marked = "==\(marked)==" }
            if a.underline != .none  { marked = "<u>\(marked)</u>" }
            if a.superscript         { marked = "<sup>\(marked)</sup>" }
            if a.`subscript`         { marked = "<sub>\(marked)</sub>" }
        }
        if let url = run.hyperlink, !url.isEmpty {
            // v1.6.2: wiki-ссылка Obsidian — обратно в [[Target]] / [[Target|label]].
            if url.hasPrefix(wikiLinkPrefix) {
                let target = String(url.dropFirst(wikiLinkPrefix.count))
                marked = (marked == target) ? "[[\(target)]]" : "[[\(target)|\(marked)]]"
            } else {
                let escapedUrl = url.replacingOccurrences(of: ")", with: "%29")
                marked = "[\(marked)](\(escapedUrl))"
            }
        }
        return marked
    }

    private static func renderTable(_ t: TableBlock, pretty: Bool = false) -> String {
        guard !t.rows.isEmpty else { return "" }

        func cellText(_ cell: TableCell) -> String {
            cell.blocks.compactMap { block -> String? in
                if case .paragraph(let p) = block {
                    return p.runs.map { renderRun($0, inner: $0.text) }.joined()
                }
                return nil
            }.joined(separator: " ").replacingOccurrences(of: "|", with: "\\|")
        }

        let rows = t.rows.map { $0.cells.map { cellText($0) } }
        guard let headerCells = rows.first else { return "" }

        // v1.4.3: pretty — колонки выравниваются пробелами по ширине контента.
        var widths = headerCells.map { ($0 as NSString).length }
        if pretty {
            for row in rows.dropFirst() {
                for (i, cell) in row.enumerated() where i < widths.count {
                    widths[i] = max(widths[i], (cell as NSString).length)
                }
            }
        }
        func pad(_ s: String, _ w: Int) -> String {
            pretty ? s + String(repeating: " ", count: max(0, w - (s as NSString).length)) : s
        }

        var lines: [String] = []
        // Первая строка — заголовок
        lines.append("| " + headerCells.enumerated().map { pad($0.element, widths[$0.offset]) }.joined(separator: " | ") + " |")
        lines.append("| " + widths.map { String(repeating: "-", count: max(3, pretty ? $0 : 3)) }.joined(separator: " | ") + " |")
        // Остальные строки — данные
        for row in rows.dropFirst() {
            lines.append("| " + row.enumerated().map { pad($0.element, $0.offset < widths.count ? widths[$0.offset] : 3) }.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
