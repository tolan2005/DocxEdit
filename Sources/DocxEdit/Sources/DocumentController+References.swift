//
//  DocumentController+References.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Оглавление и перекрёстные ссылки — v0.5.5+
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore

extension DocumentController {
    // MARK: - Оглавление (v0.5.5, R07)

    /// Собирает заголовки документа (styleId Heading1..6) и вставляет блок
    /// оглавления в позицию курсора. MVP: снимок текста заголовков, без живой
    /// пересборки — обновлять через `updateTableOfContents`.
    ///
    /// Формат каждой строки: "N.N.N  Название" с отступом по уровню (индент 20pt/level).
    /// Символы блока помечаются `.docxEditTocBlock = "toc"`.
    func insertTableOfContents() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let headings = collectHeadings()
        guard !headings.isEmpty else {
            NSSound.beep()
            return
        }
        let tocText = buildTocText(headings)
        let sel = tv.selectedRange()
        let range = (sel.location == NSNotFound || sel.location > storage.length)
            ? NSRange(location: storage.length, length: 0) : sel

        // Атрибуты — из позиции курсора + маркер блока.
        var attrs = tv.typingAttributes
        attrs[.docxEditTocBlock] = "toc"
        let piece = NSAttributedString(string: tocText, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: tocText) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: piece)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + piece.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// v0.5.5: перегенерирует существующий блок оглавления. Ищет диапазон с
    /// атрибутом `.docxEditTocBlock`, заменяет содержимое на свежий снимок.
    func updateTableOfContents() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        var tocRange: NSRange?
        storage.enumerateAttribute(.docxEditTocBlock, in: full, options: []) { val, r, stop in
            if val != nil { tocRange = r; stop.pointee = true }
        }
        guard let range = tocRange else { NSSound.beep(); return }
        let headings = collectHeadings()
        let tocText = buildTocText(headings)
        var attrs = storage.attributes(at: range.location, effectiveRange: nil)
        attrs[.docxEditTocBlock] = "toc"
        let piece = NSAttributedString(string: tocText, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: tocText) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: piece)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
    }

    /// Собирает (level, text) для абзацев со стилем Heading1..6.
    func collectHeadings() -> [(level: Int, text: String)] {
        guard let session = session else { return [] }
        var out: [(Int, String)] = []
        for section in session.bridge.model.sections {
            for block in section.blocks {
                guard case let .paragraph(p) = block,
                      let sid = p.attributes.styleId,
                      sid.hasPrefix("Heading"),
                      let level = Int(sid.dropFirst("Heading".count)),
                      (1...6).contains(level) else { continue }
                let text = p.runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append((level, text)) }
            }
        }
        return out
    }

    /// Форматирует заголовки в текст блока: "Оглавление\n1  H1\n  1.1  H2\n…".
    private func buildTocText(_ headings: [(level: Int, text: String)]) -> String {
        // Иерархическая нумерация: [1, 2, 1, …] в зависимости от уровня.
        var counters = [Int](repeating: 0, count: 6)
        var lines: [String] = ["Оглавление"]
        for (level, text) in headings {
            counters[level - 1] += 1
            for i in level..<6 { counters[i] = 0 }
            let numParts = counters.prefix(level).map(String.init)
            let indent = String(repeating: "  ", count: level - 1)
            lines.append("\(indent)\(numParts.joined(separator: ".")).  \(text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Перекрёстные ссылки (v0.5.6, R07)

    /// Вставляет перекрёстную ссылку на закладку. Текст — либо имя закладки,
    /// либо переданный. Атрибут `.docxEditCrossRef = bookmarkName` позволяет
    /// прыгать по Cmd+клику (обработчик — Coordinator).
    func insertCrossReference(bookmarkName: String, displayText: String?) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let text = displayText?.isEmpty == false ? displayText! : "→ \(bookmarkName)"
        let sel = tv.selectedRange()
        let range = (sel.location == NSNotFound || sel.location > storage.length)
            ? NSRange(location: storage.length, length: 0) : sel
        var attrs = tv.typingAttributes
        attrs[.docxEditCrossRef] = bookmarkName
        attrs[.foregroundColor] = NSColor.linkColor
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        let piece = NSAttributedString(string: text, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: piece)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + piece.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// v0.5.6: список закладок для диалога вставки cross-ref.
    func listBookmarkNames() -> [String] {
        Array(Set(listBookmarks().map(\.name))).sorted()
    }

    /// v0.5.6: прыжок по перекрёстной ссылке — вызывается по Cmd+клику на
    /// диапазоне с `.docxEditCrossRef`. Возвращает true если прыгнули.
    @discardableResult
    func goToCrossReference(at charIndex: Int) -> Bool {
        guard let storage = textView?.textStorage, charIndex < storage.length else { return false }
        let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
        guard let bookmarkName = attrs[.docxEditCrossRef] as? String else { return false }
        return goToBookmark(name: bookmarkName)
    }

    /// v0.1.57: если пользователь только что напечатал пробел/перевод строки/таб
    /// после URL или email, преобразовать это слово в гиперссылку — как в мейнстрим-редакторов
    /// и большинстве современных редакторов. Вызывается из `textDidChange`.
    /// Работает быстро: смотрит только СИМВОЛ ПЕРЕД курсором + СЛОВО ПЕРЕД ним;
    /// не обходит весь документ.
    func autoLinkifyIfNeeded() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let caret = tv.selectedRange().location
        guard caret > 0, caret <= storage.length else { return }
        let ns = storage.string as NSString
        // Триггер — только последний символ = пробел/перевод строки/таб.
        let trigger = ns.substring(with: NSRange(location: caret - 1, length: 1))
        guard trigger == " " || trigger == "\n" || trigger == "\t" else { return }
        // Ищем начало слова перед триггером (влево до пробела/начала абзаца).
        let wordEnd = caret - 1
        var wordStart = wordEnd
        while wordStart > 0 {
            let ch = ns.substring(with: NSRange(location: wordStart - 1, length: 1))
            if ch == " " || ch == "\n" || ch == "\t" { break }
            wordStart -= 1
        }
        guard wordEnd > wordStart else { return }
        let wordRange = NSRange(location: wordStart, length: wordEnd - wordStart)
        let word = ns.substring(with: wordRange)
        // Если это уже ссылка — не трогаем (не хотим двойной преобразовать).
        if storage.attribute(.link, at: wordStart, effectiveRange: nil) != nil { return }
        guard let url = detectURL(in: word) else { return }
        // Применяем .link + минимальный визуальный намёк (NSTextView сам покрасит
        // через linkTextAttributes, но attributed-string нужно пометить).
        // Не оборачиваем в shouldChangeText/didChangeText — вызов идёт уже из
        // textDidChange, поэтому просто мутируем storage; undo NSTextView запишет
        // ту же операцию как продолжение печати (пробел), пользователь всё равно
        // отменит вместе с введённым пробелом при Cmd+Z.
        storage.addAttribute(.link, value: url, range: wordRange)
    }

    /// Возвращает нормализованный URL, если строка похожа на веб-адрес или email.
    /// Правила консервативные — избегаем ложных срабатываний.
    private func detectURL(in raw: String) -> String? {
        // Отсекаем конечную пунктуацию (частая при вводе: «https://x.com,», «...com.»).
        let trimSet: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "\""]
        var s = raw
        while let last = s.last, trimSet.contains(last) { s.removeLast() }
        guard s.count >= 4 else { return nil }
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return s }
        if lower.hasPrefix("www.") && s.contains(".") { return "https://" + s }
        // Email: X@Y с точкой в домене.
        if let at = s.firstIndex(of: "@"),
           at != s.startIndex,
           s.index(after: at) < s.endIndex,
           s[s.index(after: at)...].contains(".") {
            return "mailto:" + s
        }
        return nil
    }

    /// Удаляет гиперссылку в текущем выделении (или в клике по существующей
    /// ссылке). Атомарная правка атрибутов под shouldChangeText.
    func removeHyperlink() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        // Если выделения нет — ищем эффективный диапазон текущей ссылки.
        var range = sel
        if range.length == 0, storage.length > 0 {
            let idx = min(sel.location, storage.length - 1)
            var eff = NSRange()
            if storage.attribute(.link, at: idx, effectiveRange: &eff) != nil {
                range = eff
            } else { return }
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.removeAttribute(.link, range: range)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

}
