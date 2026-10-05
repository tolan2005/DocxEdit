//
//  MarkdownEditing.swift
//  DocxEdit
//
//  v1.10.3: команды ленты в гибридном MD-режиме — правка исходного Markdown
//  (вставка/снятие разметки) вместо атрибутов визуального редактора.
//  Все правки — через insertText(_:replacementRange:), поэтому попадают в undo.
//

import AppKit

enum MarkdownEditing {
    /// Текстовый вид исходника в ключевом окне (первый респондер).
    static var focusedTextView: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    /// Обернуть выделение маркером (`**`, `*`, `~~`, `` ` ``); повторно — снять.
    static func wrap(_ tv: NSTextView, _ marker: String) {
        let sel = tv.selectedRange()
        let text = (tv.string as NSString).substring(with: sel)
        let m = (marker as NSString).length
        if text.hasPrefix(marker), text.hasSuffix(marker), (text as NSString).length > 2 * m {
            let inner = String(text.dropFirst(marker.count).dropLast(marker.count))
            tv.insertText(inner, replacementRange: sel)
            tv.setSelectedRange(NSRange(location: sel.location, length: (inner as NSString).length))
            return
        }
        tv.insertText(marker + text + marker, replacementRange: sel)
        tv.setSelectedRange(NSRange(location: sel.location + m, length: sel.length))
    }

    /// Списочный префикс строк выделения: если у всех строк он уже есть — снять,
    /// иначе поставить (`- ` или `1. `, `2. `…). Старый маркер списка заменяется.
    static func toggleList(_ tv: NSTextView, numbered: Bool) {
        let pattern = numbered ? #"^(\s*)\d+[.)] "# : #"^(\s*)[-*+] "#
        let any = #"^(\s*)(?:[-*+]|\d+[.)]) "#
        editLines(tv) { lines in
            let all = lines.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
            return lines.enumerated().map { i, line in
                let stripped = line.replacingOccurrences(of: any, with: "$1", options: .regularExpression)
                if all { return stripped }
                let indent = String(stripped.prefix { $0 == " " || $0 == "\t" })
                return indent + (numbered ? "\(i + 1). " : "- ") + stripped.dropFirst(indent.count)
            }
        }
    }

    /// Стиль абзаца из меню ленты (id `StandardParagraphStyle`) → разметка строк выделения.
    static func applyParagraphStyle(_ tv: NSTextView, id: String) {
        switch id {
        case "Quote":
            editLines(tv) { lines in
                let all = lines.allSatisfy { $0.hasPrefix(">") }
                return lines.map { all ? $0.replacingOccurrences(of: #"^> ?"#, with: "", options: .regularExpression) : "> " + $0 }
            }
        case "CodeBlock":
            editLines(tv) { ["```"] + $0 + ["```"] }
        case "HorizontalRule":
            insertBlock(tv, "---\n")
        default:
            // Normal → обычный абзац (снимаются `#` и `> `), HeadingN → `#`×N.
            let level = id.hasPrefix("Heading") ? Int(id.dropFirst("Heading".count)) ?? 0 : 0
            if level == 0 {
                editLines(tv) { $0.map { $0.replacingOccurrences(of: #"^> ?"#, with: "", options: .regularExpression) } }
            }
            setHeading(tv, level: level)
        }
    }

    /// Заголовок уровня 1…6 для строк выделения; 0 — обычный абзац (снять `#`).
    static func setHeading(_ tv: NSTextView, level: Int) {
        editLines(tv) { lines in
            lines.map { line in
                let body = line.replacingOccurrences(of: #"^#{1,6} +"#, with: "", options: .regularExpression)
                return level == 0 ? body : String(repeating: "#", count: level) + " " + body
            }
        }
    }

    /// Отступ строк выделения на 2 пробела (вложенный список); `increase == false` — убрать.
    static func indent(_ tv: NSTextView, increase: Bool) {
        editLines(tv) { lines in
            lines.map { line in
                if increase { return "  " + line }
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                return String(line.dropFirst(min(2, line.prefix { $0 == " " }.count)))
            }
        }
    }

    /// Ссылка: выделение становится текстом, адрес `https://` выделен для ввода.
    static func insertLink(_ tv: NSTextView) {
        let sel = tv.selectedRange()
        let text = sel.length > 0 ? (tv.string as NSString).substring(with: sel) : "текст"
        let url = "https://"
        tv.insertText("[\(text)](\(url))", replacementRange: sel)
        let at = sel.location + ("[\(text)](" as NSString).length
        tv.setSelectedRange(NSRange(location: at, length: (url as NSString).length))
    }

    /// Шаблон таблицы GFM 3×2 с новой строки.
    static func insertTable(_ tv: NSTextView) {
        let table = "| Столбец 1 | Столбец 2 | Столбец 3 |\n|---|---|---|\n|  |  |  |\n|  |  |  |\n"
        insertBlock(tv, table)
    }

    /// Картинка из файла: путь относительно папки документа, если файл внутри неё.
    static func insertImage(_ tv: NSTextView, baseURL: URL?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var path = url.path
        if let base = baseURL?.standardizedFileURL.path, path.hasPrefix(base + "/") {
            path = String(path.dropFirst(base.count + 1))
        }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        insertBlock(tv, "![\(url.deletingPathExtension().lastPathComponent)](\(encoded))\n")
    }

    // MARK: - Внутреннее

    /// Вставить блок с начала строки (если курсор не в начале — перенос перед блоком).
    private static func insertBlock(_ tv: NSTextView, _ block: String) {
        let sel = tv.selectedRange()
        let ns = tv.string as NSString
        let atLineStart = sel.location == 0 || ns.character(at: sel.location - 1) == 0x0A
        tv.insertText((atLineStart ? "" : "\n") + block, replacementRange: sel)
    }

    /// Заменить строки, затронутые выделением, результатом `transform` (один шаг undo).
    private static func editLines(_ tv: NSTextView, _ transform: ([String]) -> [String]) {
        let ns = tv.string as NSString
        var range = ns.lineRange(for: tv.selectedRange())
        let text = ns.substring(with: range)
        let trailingNewline = text.hasSuffix("\n")
        if trailingNewline { range.length -= 1 }
        let lines = ns.substring(with: range).components(separatedBy: "\n")
        let result = transform(lines).joined(separator: "\n")
        tv.insertText(result, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
    }
}
