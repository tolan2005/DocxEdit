//
//  MarkdownEditing.swift
//  DocxEdit
//
//  v1.10.3: команды ленты в гибридном MD-режиме — правка исходного Markdown
//  (вставка/снятие разметки) вместо атрибутов визуального редактора.
//  Все правки — через insertText(_:replacementRange:), поэтому попадают в undo.
//

import AppKit
import DocxCore

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

    /// Вставка адреса поверх выделения — `[выделение](адрес)`. `false` — нет выделения или не адрес.
    static func linkSelection(_ tv: NSTextView, url: String) -> Bool {
        let sel = tv.selectedRange()
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sel.length > 0, !url.contains(where: \.isWhitespace),
              url.range(of: #"^(https?|mailto):"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return false }
        let text = (tv.string as NSString).substring(with: sel)
        guard !text.contains("\n") else { return false }
        tv.insertText("[\(text)](\(url))", replacementRange: sel)
        return true
    }

    /// Шаблон таблицы GFM 3×2 с новой строки.
    static func insertTable(_ tv: NSTextView) {
        let table = "| Столбец 1 | Столбец 2 | Столбец 3 |\n|---|---|---|\n|  |  |  |\n|  |  |  |\n"
        insertBlock(tv, table)
    }

    /// Картинка из файла (окно выбора).
    static func insertImage(_ tv: NSTextView, baseURL: URL?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        insertImageFile(tv, url, baseURL: baseURL)
    }

    /// Ссылка `![](…)` на файл картинки: внутри папки документа — относительный путь,
    /// снаружи — копия в `images/`. Без папки (документ не сохранён) — абсолютный путь.
    @discardableResult
    static func insertImageFile(_ tv: NSTextView, _ url: URL, baseURL: URL?) -> Bool {
        var path = url.path
        if let base = baseURL?.standardizedFileURL {
            if path.hasPrefix(base.path + "/") {
                path = String(path.dropFirst(base.path.count + 1))
            } else {
                guard let copy = try? uniqueImageURL(in: base, ext: url.pathExtension),
                      (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return false }
                path = "images/" + copy.lastPathComponent
            }
        }
        insertImageLink(tv, path, name: url.deletingPathExtension().lastPathComponent)
        return true
    }

    /// Картинка из буфера обмена → `images/image-….png` рядом с документом.
    @discardableResult
    static func insertImageData(_ tv: NSTextView, _ image: NSImage, baseURL: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let url = try? uniqueImageURL(in: baseURL, ext: "png"),
              (try? png.write(to: url)) != nil else { return false }
        insertImageLink(tv, "images/" + url.lastPathComponent, name: "")
        return true
    }

    private static func insertImageLink(_ tv: NSTextView, _ path: String, name: String) {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        insertBlock(tv, "![\(name)](\(encoded))\n")
    }

    /// Свободное имя в `<base>/images/` (папка создаётся).
    private static func uniqueImageURL(in base: URL, ext: String) throws -> URL {
        let dir = base.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "image-" + f.string(from: Date())
        var url = dir.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem)-\(n)").appendingPathExtension(ext); n += 1
        }
        return url
    }

    /// Маркер пункта списка: отступ, `-*+` или `N.`/`N)`, необязательная задача `[ ]`/`[x]`.
    private static let listMarker = try! NSRegularExpression(
        pattern: #"^(\s*)([-*+]|(\d+)([.)]))( \[[ xX]\])?\s+"#)

    /// Enter в пункте списка — продолжить маркер (номер +1, задача — пустой `[ ]`);
    /// Enter на пустом пункте — убрать маркер (выход из списка). `false` — не список.
    static func continueList(_ tv: NSTextView) -> Bool {
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        let ns = tv.string as NSString
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let line = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
        let l = line as NSString
        guard let m = listMarker.firstMatch(in: line, range: NSRange(location: 0, length: l.length))
        else { return false }
        if m.range.length == l.length {
            tv.insertText("", replacementRange: NSRange(location: lineStart, length: m.range.length))
            return true
        }
        var bullet = l.substring(with: m.range(at: 2))
        if m.range(at: 3).location != NSNotFound, let n = Int(l.substring(with: m.range(at: 3))) {
            bullet = "\(n + 1)" + l.substring(with: m.range(at: 4))
        }
        let task = m.range(at: 5).location != NSNotFound ? " [ ]" : ""
        tv.insertText("\n" + l.substring(with: m.range(at: 1)) + bullet + task + " ", replacementRange: sel)
        return true
    }

    /// Tab/Shift+Tab в пункте списка — вложить/вынуть на 2 пробела. `false` — не список.
    static func indentListLine(_ tv: NSTextView, increase: Bool) -> Bool {
        let ns = tv.string as NSString
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: tv.selectedRange().location, length: 0)))
        guard listMarker.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        else { return false }
        let sel = tv.selectedRange()
        let before = (tv.string as NSString).length
        indent(tv, increase: increase)
        let delta = (tv.string as NSString).length - before
        tv.setSelectedRange(NSRange(location: max(0, sel.location + delta), length: sel.length))
        return true
    }

    /// Разметка под курсором — для подсветки кнопок ленты в гибриде (только текущая строка).
    struct CaretState: Equatable {
        var bold = false, italic = false, strike = false
        var list: ListType?
        var styleId = "Normal"
    }

    private static let boldSpan = try! NSRegularExpression(pattern: #"\*\*.+?\*\*"#)
    private static let italicSpan = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*).+?(?<!\*)\*(?!\*)"#)
    private static let strikeSpan = try! NSRegularExpression(pattern: #"~~.+?~~"#)

    static func caretState(_ text: NSString, at location: Int) -> CaretState {
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let line = text.substring(with: lineRange)
        let l = line as NSString, pos = location - lineRange.location
        func inside(_ re: NSRegularExpression) -> Bool {
            re.matches(in: line, range: NSRange(location: 0, length: l.length))
                .contains { $0.range.location < pos && pos < NSMaxRange($0.range) }
        }
        var st = CaretState(bold: inside(boldSpan), italic: inside(italicSpan), strike: inside(strikeSpan))
        if line.range(of: #"^\s*\d+[.)] "#, options: .regularExpression) != nil { st.list = .numbered }
        else if line.range(of: #"^\s*[-*+] "#, options: .regularExpression) != nil { st.list = .bulleted }
        if let h = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
            st.styleId = "Heading\(line.distance(from: h.lowerBound, to: h.upperBound) - 1)"
        } else if line.hasPrefix(">") { st.styleId = "Quote" }
        else if line.hasPrefix("```") { st.styleId = "CodeBlock" }
        return st
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
