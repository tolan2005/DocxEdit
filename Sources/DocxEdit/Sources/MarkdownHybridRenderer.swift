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
    private static let headingScale: [CGFloat] = [2.0, 1.6, 1.35, 1.15, 1.0, 0.9]

    /// Блок, в котором разметка остаётся видимой: абзац(ы) под выделением.
    static func activeRange(in text: NSString, selection: NSRange) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = min(selection.location, text.length)
        return text.paragraphRange(for: NSRange(location: loc, length: min(selection.length, text.length - loc)))
    }

    static func render(_ storage: NSTextStorage, baseFont: NSFont, active: NSRange) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        let codeBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)

        func isActive(_ r: NSRange) -> Bool {
            if NSIntersectionRange(r, active).length > 0 { return true }
            return active.length == 0 && active.location >= r.location && active.location <= NSMaxRange(r)
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

        // Горизонтальная линия.
        matches(#"(?m)^[ \t]*(---+|\*\*\*+|___+)[ \t]*$"#, text) { m in
            guard !inCode(m.range) else { return }
            storage.addAttribute(.foregroundColor, value: markerColor, range: m.range)
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
