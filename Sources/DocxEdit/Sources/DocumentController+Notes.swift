//
//  DocumentController+Notes.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Сноски, концевые сноски, навигатор, перемещение разделов — v0.5.3+
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore

extension DocumentController {
    // MARK: - Сноски (v0.5.3, R07)

    /// Вставляет сноску в позицию курсора. Создаёт новый Footnote(id, text)
    /// в модели документа и вставляет superscript-маркер (id) на позицию
    /// с custom-атрибутом `.docxEditFootnoteId`.
    /// id — очередное натуральное число, чтобы не пересечься с существующими.
    func insertFootnote(text: String) {
        guard let tv = textView, let storage = tv.textStorage,
              let session = session else { return }
        let sel = tv.selectedRange()
        let range = (sel.location == NSNotFound || sel.location > storage.length)
            ? NSRange(location: storage.length, length: 0) : sel

        // Уникальный id — max существующих + 1 (все id — строковые целые).
        let existing = session.bridge.model.footnotes.compactMap { Int($0.id) }
        let newId = String((existing.max() ?? 0) + 1)

        // Атрибуты маркера: 0.7× шрифт + superscript baselineOffset.
        var attrs = tv.typingAttributes
        if let f = attrs[.font] as? NSFont {
            attrs[.font] = NSFontManager.shared.convert(f, toSize: f.pointSize * 0.7)
            attrs[.baselineOffset] = f.pointSize * 0.35
        }
        attrs[.docxEditFootnoteId] = newId

        let marker = NSAttributedString(string: newId, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: newId) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: marker)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + marker.length, length: 0))

        // Добавляем содержимое сноски напрямую в модель через мутатор bridge.
        session.bridge.addFootnote(Footnote(id: newId, text: text))
        session.markDirty()
        notifyModelChange()
        // v0.5.4: живая нумерация — пересчитываем маркеры 1,2,3… в порядке появления.
        renumberFootnotes()
        refreshSelectionState()
    }

    // MARK: - Концевые сноски — создание (v1.6.2)

    /// Вставляет концевую сноску в позицию курсора (⌥⌘E занят экспортом PDF —
    /// только меню/лента). Маркер — superscript римскими (как у импортированных).
    func insertEndnote(text: String) {
        guard let tv = textView, let storage = tv.textStorage,
              let session = session else { return }
        let sel = tv.selectedRange()
        let range = (sel.location == NSNotFound || sel.location > storage.length)
            ? NSRange(location: storage.length, length: 0) : sel

        let existing = session.bridge.model.endnotes.compactMap { Int($0.id) }
        let newId = String((existing.max() ?? 0) + 1)

        var attrs = tv.typingAttributes
        if let f = attrs[.font] as? NSFont {
            attrs[.font] = NSFontManager.shared.convert(f, toSize: f.pointSize * 0.7)
            attrs[.baselineOffset] = f.pointSize * 0.35
        }
        attrs[.docxEditEndnoteId] = newId

        let markerText = romanNumeral(for: newId)
        let marker = NSAttributedString(string: markerText, attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: markerText) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: marker)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + marker.length, length: 0))

        session.bridge.addEndnote(Footnote(id: newId, text: text))
        session.markDirty()
        notifyModelChange()
        refreshSelectionState()
    }

    /// v0.5.4 (R07): пересчитывает текст маркеров сносок как 1, 2, 3… в
    /// порядке появления в тексте. Атрибут `.docxEditFootnoteId` остаётся
    /// прежним (это связь с записью Footnote в модели). Меняем только видимый
    /// текст рана и — синхронно — id записи Footnote, чтобы DOCX-writer писал
    /// нужный `<w:footnoteReference w:id="N"/>`.
    func renumberFootnotes() {
        guard let tv = textView, let storage = tv.textStorage,
              let session = session else { return }
        // Собираем существующие якоря в порядке появления.
        var anchors: [(range: NSRange, oldId: String)] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.docxEditFootnoteId, in: full, options: []) { val, range, _ in
            if let id = val as? String { anchors.append((range, id)) }
        }
        guard !anchors.isEmpty else { return }

        // Строим маппинг старый id → новый (1,2,3…) в порядке появления.
        var idMap: [String: String] = [:]
        for (idx, a) in anchors.enumerated() {
            idMap[a.oldId] = String(idx + 1)
        }

        // Обновляем текст маркеров + атрибут (если id изменился).
        storage.beginEditing()
        // Идём в обратном порядке, чтобы не сдвигать ещё не обработанные ranges.
        for (range, oldId) in anchors.reversed() {
            let newId = idMap[oldId]!
            let attrs = storage.attributes(at: range.location, effectiveRange: nil)
            var newAttrs = attrs
            newAttrs[.docxEditFootnoteId] = newId
            let replacement = NSAttributedString(string: newId, attributes: newAttrs)
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()

        // Обновляем id сносок в модели.
        var newFootnotes: [Footnote] = []
        for f in session.bridge.model.footnotes {
            if let mapped = idMap[f.id] {
                newFootnotes.append(Footnote(id: mapped, text: f.text))
            }
            // Осиротевшие (нет в idMap — якорь удалён) сюда не попадают —
            // model.footnotes чистится от них при renumber.
        }
        // Заменяем список целиком через мутатор.
        session.bridge.replaceFootnotes(newFootnotes)
        session.markDirty()
    }

    /// v0.5.4: удаляет якорь сноски + запись из модели. Ищем ран(ы) с этим
    /// footnoteId в тексте, стираем; чистим из bridge.
    func removeFootnote(id: String) {
        guard let tv = textView, let storage = tv.textStorage,
              let session = session else { return }
        let full = NSRange(location: 0, length: storage.length)
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.docxEditFootnoteId, in: full, options: []) { val, range, _ in
            if (val as? String) == id { ranges.append(range) }
        }
        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        // Обратный порядок — не двигаем ещё не обработанные диапазоны.
        for r in ranges.reversed() {
            storage.deleteCharacters(in: r)
        }
        storage.endEditing()
        tv.didChangeText()
        session.bridge.removeFootnote(id: id)
        session.markDirty()
        notifyModelChange()
        renumberFootnotes()
    }

    /// v0.5.4: обновление текста существующей сноски (панель редактирования).
    func updateFootnoteText(id: String, text: String) {
        guard let session = session else { return }
        session.bridge.updateFootnoteText(id: id, text: text)
        session.markDirty()
    }

    /// v0.5.4: список сносок для панели.
    func listFootnotes() -> [Footnote] {
        session?.bridge.model.footnotes ?? []
    }

    // MARK: - Концевые сноски (v1.5.15)

    func listEndnotes() -> [Footnote] {
        session?.bridge.model.endnotes ?? []
    }

    func updateEndnoteText(id: String, text: String) {
        guard let session = session else { return }
        session.bridge.updateEndnoteText(id: id, text: text)
        session.markDirty()
    }

    // MARK: - Панель навигации (v1.5.11)

    struct NavigatorHeading {
        let level: Int
        let text: String
        let location: Int   // позиция первого символа абзаца в textStorage
    }

    /// Заголовки (styleId Heading1..6) прямо из живого textStorage — позиции
    /// валидны для прыжка (не зависят от пересборки модели). Панель пересчитывает
    /// по `textRevision` (инкремент в userDidEdit).
    func navigatorHeadings() -> [NavigatorHeading] {
        guard let tv = textView, let storage = tv.textStorage else { return [] }
        let ns = storage.string as NSString
        var out: [NavigatorHeading] = []
        var pos = 0
        let len = ns.length
        while pos < len {
            let pr = ns.paragraphRange(for: NSRange(location: pos, length: 0))
            if let sid = storage.attribute(.docxEditStyleId, at: pr.location, effectiveRange: nil) as? String,
               sid.hasPrefix("Heading"),
               let level = Int(sid.dropFirst("Heading".count)),
               (1...6).contains(level) {
                let text = ns.substring(with: pr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(NavigatorHeading(level: level, text: text, location: pr.location))
                }
            }
            pos = NSMaxRange(pr)
        }
        return out
    }

    /// Прыжок к заголовку: курсор в начало абзаца + прокрутка.
    func goToHeading(location: Int) {
        guard let tv = textView, let storage = tv.textStorage,
              location >= 0, location <= storage.length else { return }
        tv.setSelectedRange(NSRange(location: location, length: 0))
        tv.scrollRangeToVisible(NSRange(location: location, length: 0))
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: - Повысить/понизить заголовок из навигатора (v1.6.4)

    /// Меняет стиль абзаца на позиции `location` на Heading level±1.
    /// Паттерн атомарного applyParagraphStyle (ADR-027) на один абзац.
    private func changeHeadingLevel(location: Int, currentLevel: Int, newLevel: Int) {
        guard newLevel >= 1, newLevel <= 6, newLevel != currentLevel else { return }
        guard let tv = textView, let storage = tv.textStorage,
              location < storage.length else { return }
        let ns = storage.string as NSString
        let paraRange = ns.paragraphRange(for: NSRange(location: location, length: 0))
        // Временно выделяем абзац и переиспользуем атомарный путь applyParagraphStyle.
        let savedSelection = tv.selectedRange()
        tv.setSelectedRange(paraRange)
        applyParagraphStyle(id: "Heading\(newLevel)")
        tv.setSelectedRange(savedSelection)
    }

    /// Повысить заголовок (Heading 2 → Heading 1).
    func promoteHeading(location: Int, currentLevel: Int) {
        changeHeadingLevel(location: location, currentLevel: currentLevel,
                           newLevel: currentLevel - 1)
    }

    /// Понизить заголовок (Heading 1 → Heading 2).
    func demoteHeading(location: Int, currentLevel: Int) {
        changeHeadingLevel(location: location, currentLevel: currentLevel,
                           newLevel: currentLevel + 1)
    }

    // MARK: - Перемещение разделов (v1.6.5)

    /// Диапазон раздела: от заголовка `heading` до следующего заголовка
    /// того же или более высокого уровня (Word-семантика перемещения раздела).
    func sectionRange(of heading: NavigatorHeading, in storage: NSTextStorage) -> NSRange {
        let ns = storage.string as NSString
        let start = ns.paragraphRange(for: NSRange(location: heading.location, length: 0)).location
        var pos = NSMaxRange(ns.paragraphRange(for: NSRange(location: heading.location, length: 0)))
        let len = ns.length
        while pos < len {
            let pr = ns.paragraphRange(for: NSRange(location: pos, length: 0))
            if let sid = storage.attribute(.docxEditStyleId, at: pr.location, effectiveRange: nil) as? String,
               sid.hasPrefix("Heading"),
               let lvl = Int(sid.dropFirst("Heading".count)), lvl <= heading.level {
                return NSRange(location: start, length: pr.location - start)
            }
            pos = NSMaxRange(pr)
        }
        return NSRange(location: start, length: len - start)
    }

    /// Перемещает раздел (заголовок + содержимое до следующего заголовка
    /// того же/высшего уровня) в позицию заголовка с индексом `to`.
    /// Один атомарный undo-шаг (delete + insert под общим shouldChangeText).
    func moveSection(from: Int, to: Int) {
        guard from != to, let tv = textView, let storage = tv.textStorage else { return }
        let headings = navigatorHeadings()
        guard headings.indices.contains(from), headings.indices.contains(to) else { return }
        let srcHeading = headings[from]
        let srcRange = sectionRange(of: srcHeading, in: storage)
        guard srcRange.length > 0 else { return }

        // Точка вставки: для перемещения вверх — начало абзаца-заголовка
        // назначения; вниз — конец его раздела.
        let destHeading = headings[to]
        let destRange = sectionRange(of: destHeading, in: storage)
        let insertLocation = (to < from) ? destRange.location : NSMaxRange(destRange)

        let sectionText = storage.attributedSubstring(from: srcRange)
        // После удаления источника точка вставки сдвигается, если была ниже.
        let adjustedLocation = insertLocation > srcRange.location
            ? insertLocation - srcRange.length : insertLocation

        let union = NSUnionRange(srcRange, NSRange(location: adjustedLocation, length: 0))
        guard tv.shouldChangeText(in: union, replacementString: nil) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: srcRange, with: "")
        storage.insert(sectionText, at: adjustedLocation)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        // Курсор — в начало перемещённого раздела.
        tv.setSelectedRange(NSRange(location: adjustedLocation, length: 0))
        tv.scrollRangeToVisible(NSRange(location: adjustedLocation, length: 0))
    }

}
