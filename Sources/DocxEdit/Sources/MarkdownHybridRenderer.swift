//
//  MarkdownHybridRenderer.swift
//  DocxEdit
//
//  v1.9.0: гибридный (Typora-подобный) рендер Markdown. Источник истины — сырой
//  текст; рендер только выставляет атрибуты. Вне блока с курсором разметка
//  (#, **, `, [](url) …) скрывается, конструкции показываются стилями; в блоке
//  с курсором разметка видна (приглушённо) и редактируется как текст.
//

import AppKit

enum MarkdownHybridRenderer {

    static let hiddenAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ]
    static let markerColor = NSColor.tertiaryLabelColor
    /// Символ, которым рисуется глиф этого знака (подмена в NSLayoutManagerDelegate).
    static let glyphKey = NSAttributedString.Key("docxEditMarkdownGlyph")
    /// URL-схема клика по чекбоксу задачи (`- [ ]`).
    static let taskScheme = "docxedit-task"
    /// NSImage, которое текстовый вид рисует поверх скрытой строки `![…](…)`.
    static let imageKey = NSAttributedString.Key("docxEditMarkdownImage")
    private static let imageCache = NSCache<NSURL, NSImage>()
    /// Горизонтальная линия: текстовый вид рисует черту поверх скрытой строки `---`.
    static let ruleKey = NSAttributedString.Key("docxEditMarkdownRule")
    /// MarkdownTable, которую текстовый вид рисует сеткой поверх скрытых строк таблицы.
    static let tableKey = NSAttributedString.Key("docxEditMarkdownTable")

    final class MarkdownTable: NSObject {
        let rows: [[String]]                  // [0] — шапка
        let alignments: [NSTextAlignment]
        let font: NSFont
        let boldFont: NSFont
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]             // текст ячеек переносится по словам, строка — по самой высокой ячейке
        static let padding: CGFloat = 8

        init(rows: [[String]], alignments: [NSTextAlignment], font: NSFont, maxWidth: CGFloat) {
            self.rows = rows; self.alignments = alignments; self.font = font
            let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            boldFont = bold
            let pad = Self.padding
            let columns = rows.map(\.count).max() ?? 0
            let natural = (0..<columns).map { c in
                rows.enumerated().map { r, row in
                    c < row.count ? (row[c] as NSString).size(withAttributes: [.font: r == 0 ? bold : font]).width : 0
                }.max()! + 2 * pad
            }
            // Не помещается — колонки уже «справедливой доли» остаются как есть, остаток делят широкие.
            var widths = natural
            if natural.reduce(0, +) > maxWidth {
                var wide = Set(0..<columns)
                while true {
                    let rest = maxWidth - natural.indices.filter { !wide.contains($0) }.map { natural[$0] }.reduce(0, +)
                    let share = rest / CGFloat(max(wide.count, 1))
                    let narrow = wide.filter { natural[$0] <= share }
                    if narrow.isEmpty {
                        let sum = wide.map { natural[$0] }.reduce(0, +)
                        for c in wide { widths[c] = rest * natural[c] / sum }
                        break
                    }
                    wide.subtract(narrow)
                }
            }
            columnWidths = widths
            let minHeight = ceil(font.ascender - font.descender + font.leading)
            rowHeights = rows.enumerated().map { r, row in
                let h = row.prefix(columns).enumerated().map { c, text in
                    (text as NSString).boundingRect(
                        with: NSSize(width: max(1, widths[c] - 2 * pad), height: .greatestFiniteMagnitude),
                        options: .usesLineFragmentOrigin, attributes: [.font: r == 0 ? bold : font]).height
                }.max() ?? 0
                return max(minHeight, ceil(h)) + 10
            }
        }
    }

    static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
              .replacingOccurrences(of: "**", with: "")
              .replacingOccurrences(of: "`", with: "")
        }
    }

    /// Только локальные файлы (офлайн по умолчанию, ADR-008); путь — относительно документа.
    static func loadImage(_ path: String, baseURL: URL?) -> NSImage? {
        let decoded = path.removingPercentEncoding ?? path
        let url: URL
        if decoded.hasPrefix("/") { url = URL(fileURLWithPath: decoded) }
        else if let u = URL(string: path), u.scheme != nil { guard u.isFileURL else { return nil }; url = u }
        else if let baseURL { url = baseURL.appendingPathComponent(decoded) }
        else { return nil }
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let img = NSImage(contentsOf: url), img.size.width > 0 else { return nil }
        imageCache.setObject(img, forKey: url as NSURL)
        return img
    }
    private static let headingScale: [CGFloat] = [2.0, 1.6, 1.35, 1.15, 1.0, 0.9]

    /// Блок, в котором разметка остаётся видимой: абзац(ы) под выделением.
    static func activeRange(in text: NSString, selection: NSRange) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = min(selection.location, text.length)
        // Курсор на пустой последней строке (после «\n») — не часть предыдущего абзаца.
        if selection.length == 0, loc == text.length, text.character(at: loc - 1) == 10 {
            return NSRange(location: loc, length: 0)
        }
        return text.paragraphRange(for: NSRange(location: loc, length: min(selection.length, text.length - loc)))
    }

    static func render(_ storage: NSTextStorage, baseFont: NSFont, active: NSRange,
                       baseURL: URL? = nil, maxImageWidth: CGFloat = 600) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        let codeBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)

        func isActive(_ r: NSRange) -> Bool {
            if NSIntersectionRange(r, active).length > 0 { return true }
            guard active.length == 0 else { return false }
            let end = NSMaxRange(r)
            let endsWithNewline = end > 0 && end <= text.length && text.character(at: end - 1) == 10
            return active.location >= r.location && (active.location < end || (active.location == end && !endsWithNewline))
        }
        func marker(_ r: NSRange, visible: Bool) {
            guard r.location != NSNotFound, r.length > 0 else { return }
            if visible {
                storage.addAttribute(.foregroundColor, value: markerColor, range: r)
            } else {
                storage.addAttributes(hiddenAttributes, range: r)
            }
        }

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: full)

        // Блоки кода — первыми: внутри них inline-разметка не действует.
        var codeRanges: [NSRange] = []
        matches(#"(?ms)^(```[^\n]*\n)(.*?)(^```[ \t]*$)"#, text) { m in
            codeRanges.append(m.range)
            let visible = isActive(m.range)
            storage.addAttributes([.font: mono, .backgroundColor: codeBg], range: m.range)
            marker(m.range(at: 1), visible: visible)
            marker(m.range(at: 3), visible: visible)
        }
        func inCode(_ r: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }

        // Заголовки ATX.
        matches(#"(?m)^(#{1,6})([ \t]+)(.*)$"#, text) { m in
            guard !inCode(m.range) else { return }
            let level = m.range(at: 1).length
            let size = baseFont.pointSize * headingScale[level - 1]
            let font = NSFontManager.shared.convert(NSFont(descriptor: baseFont.fontDescriptor, size: size) ?? baseFont,
                                                    toHaveTrait: .boldFontMask)
            let prefix = NSUnionRange(m.range(at: 1), m.range(at: 2))
            storage.addAttribute(.font, value: font, range: m.range(at: 3))
            let visible = isActive(m.range)
            if visible { storage.addAttribute(.font, value: font, range: prefix) }
            marker(prefix, visible: visible)
        }

        // Цитаты.
        matches(#"(?m)^(>[ \t]?)(.*)$"#, text) { m in
            guard !inCode(m.range) else { return }
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = 16
            ps.headIndent = 16
            storage.addAttributes([.paragraphStyle: ps, .foregroundColor: NSColor.secondaryLabelColor],
                                  range: m.range)
            marker(m.range(at: 1), visible: isActive(m.range))
        }

        // Списки: маркер → «•», задачи → ☐/☑, висячий отступ для переносов.
        func hangingIndent(_ visiblePrefix: String, _ r: NSRange) {
            let ps = NSMutableParagraphStyle()
            ps.headIndent = (visiblePrefix as NSString).size(withAttributes: [.font: baseFont]).width
            storage.addAttribute(.paragraphStyle, value: ps, range: r)
        }
        matches(#"(?m)^([ \t]*)([-*+])([ \t]+)(?:(\[)([ xX])(\])([ \t]+))?(.*)$"#, text) { m in
            guard !inCode(m.range) else { return }
            let indent = text.substring(with: m.range(at: 1))
            if m.range(at: 5).location != NSNotFound {
                let done = text.substring(with: m.range(at: 5)) != " "
                storage.addAttributes(hiddenAttributes, range: NSUnionRange(m.range(at: 2), m.range(at: 4)))
                storage.addAttributes(hiddenAttributes, range: m.range(at: 6))
                let box = NSFont(name: "Apple Symbols", size: baseFont.pointSize * 1.2) ?? baseFont
                storage.addAttributes([.font: box, .foregroundColor: NSColor.secondaryLabelColor,
                                       glyphKey: done ? "☑" : "☐",
                                       .link: URL(string: "\(taskScheme)://toggle")!],
                                      range: m.range(at: 5))
                if done {
                    storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                           .foregroundColor: NSColor.secondaryLabelColor], range: m.range(at: 8))
                }
                hangingIndent(indent + "☐ ", m.range)
            } else {
                storage.addAttributes([glyphKey: "•", .foregroundColor: NSColor.secondaryLabelColor],
                                      range: m.range(at: 2))
                hangingIndent(indent + "• ", m.range)
            }
        }
        matches(#"(?m)^([ \t]*)(\d+[.)])([ \t]+)(.*)$"#, text) { m in
            guard !inCode(m.range) else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
            hangingIndent(text.substring(with: NSRange(location: m.range.location,
                                                       length: m.range(at: 4).location - m.range.location)), m.range)
        }

        // Картинка отдельной строкой: строка скрыта, высота зарезервирована под изображение.
        matches(#"(?m)^[ \t]*!\[[^\]\n]*\]\(([^)\s]+)(?:[ \t]+"[^"\n]*")?\)[ \t]*$"#, text) { m in
            guard !inCode(m.range), !isActive(m.range),
                  let img = loadImage(text.substring(with: m.range(at: 1)), baseURL: baseURL) else { return }
            let scale = min(1, maxImageWidth / img.size.width)
            let ps = NSMutableParagraphStyle()
            ps.minimumLineHeight = img.size.height * scale
            ps.maximumLineHeight = img.size.height * scale
            storage.addAttributes(hiddenAttributes, range: m.range)
            storage.addAttributes([imageKey: img, .paragraphStyle: ps], range: m.range)
            codeRanges.append(m.range)   // inline-разметка (ссылка) внутри скрытой строки не нужна
        }

        // Таблицы GFM: строки скрыты, высота зарезервирована, сетку рисует текстовый вид.
        matches(#"(?m)^(\|[^\n]*\|)[ \t]*\n(\|[ \t:|-]*-[ \t:|-]*\|)[ \t]*(?:\n((?:\|[^\n]*\|[ \t]*(?:\n|$))*))?"#, text) { m in
            guard !inCode(m.range) else { return }
            if isActive(m.range) {   // редактирование: моноширинный, чтобы колонки `|` выравнивались
                storage.addAttribute(.font, value: mono, range: m.range)
                codeRanges.append(m.range)
                return
            }
            let sep = tableCells(text.substring(with: m.range(at: 2)))
            let alignments: [NSTextAlignment] = sep.map { c in
                let l = c.hasPrefix(":"), r = c.hasSuffix(":")
                return l && r ? .center : (r ? .right : .left)
            }
            var rows = [tableCells(text.substring(with: m.range(at: 1)))]
            if m.range(at: 3).location != NSNotFound {
                rows += text.substring(with: m.range(at: 3)).split(separator: "\n").map { tableCells(String($0)) }
            }
            let table = MarkdownTable(rows: rows, alignments: alignments, font: baseFont, maxWidth: maxImageWidth)
            var row = 0
            storage.addAttributes(hiddenAttributes, range: m.range)
            storage.addAttribute(tableKey, value: table, range: m.range)
            text.enumerateSubstrings(in: m.range, options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
                let ps = NSMutableParagraphStyle()
                let isSeparator = enclosing.location == m.range(at: 2).location
                let height = isSeparator || row >= table.rowHeights.count ? 0.01 : table.rowHeights[row]
                if !isSeparator { row += 1 }
                ps.minimumLineHeight = height
                ps.maximumLineHeight = height
                storage.addAttribute(.paragraphStyle, value: ps, range: enclosing)
            }
            codeRanges.append(m.range)
        }

        // Горизонтальная линия.
        matches(#"(?m)^[ \t]*(---+|\*\*\*+|___+)[ \t]*$"#, text) { m in
            guard !inCode(m.range) else { return }
            guard !isActive(m.range) else {
                storage.addAttribute(.foregroundColor, value: markerColor, range: m.range)
                return
            }
            let ps = NSMutableParagraphStyle()
            ps.minimumLineHeight = baseFont.pointSize * 1.5
            ps.maximumLineHeight = baseFont.pointSize * 1.5
            storage.addAttributes(hiddenAttributes, range: m.range)
            storage.addAttributes([ruleKey: true, .paragraphStyle: ps], range: m.range)
        }

        // Inline-конструкции: (открывающий маркер)(содержимое)(закрывающий маркер).
        func inline(_ pattern: String, style: (NSRange) -> Void) {
            matches(pattern, text) { m in
                guard !inCode(m.range) else { return }
                style(m.range(at: 2))
                let visible = isActive(text.paragraphRange(for: m.range))
                marker(m.range(at: 1), visible: visible)
                marker(m.range(at: 3), visible: visible)
            }
        }
        inline(#"(`)([^`\n]+)(`)"#) { r in
            storage.addAttributes([.font: mono, .backgroundColor: codeBg, .foregroundColor: NSColor.systemPink], range: r)
        }
        inline(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#) { r in addTrait(.boldFontMask, storage, r) }
        inline(#"(?<![*\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])(\1)(?![*\w])"#) { r in addTrait(.italicFontMask, storage, r) }
        inline(#"(~~)(.+?)(~~)"#) { r in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        inline(#"(\[)([^\]\n]+)(\]\([^)\n]+\))"#) { r in
            storage.addAttributes([.foregroundColor: NSColor.linkColor,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: r)
        }

        storage.endEditing()
    }

    private static func matches(_ pattern: String, _ text: NSString, _ body: (NSTextCheckingResult) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        for m in re.matches(in: text as String, range: NSRange(location: 0, length: text.length)) { body(m) }
    }

    /// Добавляет начертание к уже выставленным шрифтам (заголовок + **жирный** и т.п.).
    private static func addTrait(_ trait: NSFontTraitMask, _ storage: NSTextStorage, _ range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, r, _ in
            guard let f = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: trait), range: r)
        }
    }
}
