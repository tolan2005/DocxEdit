//
//  DocumentController+Search.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Undo/Redo, правописание, расширенный поиск/замена, подсветка вхождений
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore

extension DocumentController {
    // MARK: - Undo/Redo и поиск (для тулбара и меню)

    func undo() { textView?.undoManager?.undo(); refreshSelectionState() }
    func redo() { textView?.undoManager?.redo(); refreshSelectionState() }

    /// Вставка строки из буфера обмена с сохранением стиля текущего абзаца:
    /// содержимое приводится к plain-тексту и вставляется через стандартный ввод
    /// NSTextView, из-за чего наследует `typingAttributes` (шрифт/размер/цвет/
    /// paragraphStyle позиции курсора). Разрывы строк из буфера сохраняются.
    func pasteAsPlainText() {
        guard let textView else { return }
        let pb = NSPasteboard.general
        // Приоритет — plain string; большинство приложений кладут её рядом
        // с богатыми форматами. Иначе — извлекаем строку из RTF/HTML.
        let text: String? = pb.string(forType: .string)
            ?? (pb.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string })
            ?? (pb.data(forType: .html).flatMap { NSAttributedString(html: $0, documentAttributes: nil)?.string })
        guard let text, !text.isEmpty else { return }
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.insertText(text, replacementRange: range)
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Вставка произвольного текста в позицию курсора (или замена выделения).
    /// Наследует typingAttributes, регистрирует undo. Используется диалогом «Символ»
    /// и вставкой даты/времени (v0.1.58). Реализация через прямой storage.replace,
    /// а не textView.insertText — последний идёт через input-processing очередь
    /// NSTextView и теряет символы, если textView не first responder (что и есть
    /// случай при вызове из отдельного окна SwiftUI-диалога): особенно теряются
    /// пробельные (NBSP, hair space) и математические (√), которые input system
    /// пытается интерпретировать как key events. Фикс v0.1.59.
    func insertTextAtCaret(_ text: String) {
        guard let textView, let storage = textView.textStorage, !text.isEmpty else { return }
        var range = textView.selectedRange()
        if range.location == NSNotFound || range.location > storage.length {
            range = NSRange(location: storage.length, length: 0)
        }
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        let attrs = textView.typingAttributes
        let piece = NSAttributedString(string: text, attributes: attrs)
        storage.replaceCharacters(in: range, with: piece)
        let newLoc = range.location + (text as NSString).length
        textView.setSelectedRange(NSRange(location: newLoc, length: 0))
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Вставка текущей даты/времени в позицию курсора. Форматирование —
    /// системная локаль пользователя (dateStyle/timeStyle комбинируются).
    func insertDateTime(includeDate: Bool, includeTime: Bool) {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = includeDate ? .long : .none
        df.timeStyle = includeTime ? .short : .none
        insertTextAtCaret(df.string(from: Date()))
    }

    /// Применяет стандартный стиль абзаца ко всем абзацам выделения. Меняет:
    /// (1) визуальные атрибуты — размер шрифта, начертание (bold/italic) на всех
    /// символах, интервалы до/после в NSParagraphStyle; (2) `.docxEditStyleId` —
    /// сохраняется в модель и записывается в `<w:pStyle>` при экспорте DOCX.
    func applyParagraphStyle(id: String) {
        guard StandardParagraphStyle.find(id: id) != nil else { return }
        // Effective definition — override из документа, если есть, иначе стандартный.
        let effectiveDef = effectiveParagraphStyle(id: id)
        let style = StandardParagraphStyle(id: id, def: effectiveDef)
        guard let textView, let storage = textView.textStorage else { return }
        let paraRanges = selectedParagraphRanges()
        guard !paraRanges.isEmpty,
              let overallRange = paraRanges.reduce(nil as NSRange?, { acc, r in
                  acc.map { NSUnionRange($0, r) } ?? r
              }) else { return }

        // Строим новое содержимое всего затронутого диапазона и заменяем ЕДИНЫМ
        // replaceCharacters — тот же паттерн атомарного undo, что для списков (ADR-027).
        let newContent = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: overallRange))
        // Семейство шрифта: для Normal — из настроек «Шрифт по умолчанию»;
        // для Heading* — из «Шрифт заголовков» (fallback на default), чтобы
        // пользователь мог задать разные шрифты для основного текста и заголовков.
        let prefs = AppPreferences.shared
        let family: String = (id == "Normal")
            ? prefs.defaultFontName
            : (prefs.headingFontName ?? prefs.defaultFontName)
        for r in paraRanges where r.length > 0 {
            let local = NSRange(location: r.location - overallRange.location, length: r.length)
            applyStandardStyle(style, fontFamily: family, to: newContent, range: local)
        }

        guard textView.shouldChangeText(in: overallRange, replacementString: newContent.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: overallRange, with: newContent)
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
        currentStyleId = id
    }

    /// Применяет символьный стиль (Strong/Emphasis/CodeChar) к текущему выделению.
    /// `id == nil` — снятие стиля. Правит визуальные атрибуты (bold/italic/шрифт) и
    /// метку `.docxEditCharStyleId`; цвет, подчёркивание, зачёркивание сохраняются.
    func applyCharacterStyle(id: String?) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        // Effective — override из документа, если есть, иначе стандартный.
        let effectiveStyle: StandardCharacterStyle? = id.flatMap { sid in
            StandardCharacterStyle.find(id: sid).map { std in
                StandardCharacterStyle(id: sid, def: effectiveCharacterStyle(id: sid))
            }
        }
        guard range.length > 0 else {
            // Без выделения — обновляем только typingAttributes (следующий ввод — со стилем).
            var typing = textView.typingAttributes
            if let sid = id, let style = effectiveStyle {
                typing[.docxEditCharStyleId] = sid
                if let old = typing[.font] as? NSFont {
                    var f = old
                    let mgr = NSFontManager.shared
                    if let family = style.def.fontName { f = mgr.convert(f, toFamily: family) }
                    if let size   = style.def.fontSize { f = mgr.convert(f, toSize: size) }
                    var traits = f.fontDescriptor.symbolicTraits
                    if style.def.bold   { traits.insert(.bold) }
                    if style.def.italic { traits.insert(.italic) }
                    if let d = f.fontDescriptor.withSymbolicTraits(traits) as NSFontDescriptor? {
                        f = NSFont(descriptor: d, size: f.pointSize) ?? f
                    }
                    typing[.font] = f
                }
            } else {
                typing.removeValue(forKey: .docxEditCharStyleId)
            }
            textView.typingAttributes = typing
            currentCharStyleId = id
            return
        }

        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        if let style = effectiveStyle {
            applyStandardCharacterStyle(style, to: storage, range: range)
        } else {
            removeCharacterStyle(from: storage, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
        currentCharStyleId = id
    }

    // MARK: - Override стилей на уровне документа
    //
    // `DocumentModel.styles.paragraphStyles / .characterStyles` служат override
    // над `StandardParagraphStyle.all / StandardCharacterStyle.all`.
    // Effective: сначала override → fallback на стандарт. Изменения override
    // помечают документ dirty и сериализуются в DOCX styles.xml.

    func effectiveParagraphStyle(id: String) -> ParagraphStyleDef {
        if let override = session?.bridge.paragraphStyleOverrides[id] {
            return override
        }
        return StandardParagraphStyle.find(id: id)?.def
            ?? ParagraphStyleDef(name: id, basedOn: nil)
    }

    func overrideParagraphStyle(id: String, def: ParagraphStyleDef) {
        guard let session else { return }
        session.bridge.setParagraphStyleOverride(id: id, def: def)
        session.markDirty()
        reapplyParagraphStyleAcrossDocument(id: id)
    }

    func resetParagraphStyle(id: String) {
        guard let session else { return }
        session.bridge.setParagraphStyleOverride(id: id, def: nil)
        session.markDirty()
        reapplyParagraphStyleAcrossDocument(id: id)
    }

    /// Пере-применяет визуальные атрибуты стиля ко всем абзацам с этим styleId в
    /// документе — без изменения их paragraph-style (без сдвига текста), с одним
    /// шагом undo. Используется, когда пользователь меняет override в диалоге
    /// «Стили…» и ожидает мгновенного обновления всех Heading1-абзацев и т.п.
    private func reapplyParagraphStyleAcrossDocument(id: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let effectiveDef = effectiveParagraphStyle(id: id)
        let style = StandardParagraphStyle(id: id, def: effectiveDef)
        let prefs = AppPreferences.shared
        // Приоритет: явный fontName стиля (задан в диалоге «Стили…») → шрифт из
        // настроек (Обычный/Заголовки). Раньше override fontName игнорировался.
        let family: String = effectiveDef.fontName ?? ((id == "Normal")
            ? prefs.defaultFontName
            : (prefs.headingFontName ?? prefs.defaultFontName))

        // Собираем диапазоны абзацев с указанным styleId.
        var targetRanges: [NSRange] = []
        storage.enumerateAttribute(.docxEditStyleId, in: full, options: []) { val, range, _ in
            guard let sid = val as? String, sid == id else { return }
            targetRanges.append(range)
        }
        guard !targetRanges.isEmpty else { return }

        // applyStandardStyle правит только атрибуты через addAttribute →
        // shouldChangeText(replacementString: nil) валидно (attribute-only edit).
        // Раньше здесь был storage.replaceCharacters — конфликт с nil, из-за чего
        // NSTextView мог отклонить правку и стиль «не менялся» после первого apply.
        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        for r in targetRanges {
            applyStandardStyle(style, fontFamily: family, to: storage, range: r)
        }
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    private func reapplyCharacterStyleAcrossDocument(id: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let effectiveDef = effectiveCharacterStyle(id: id)
        let style = StandardCharacterStyle(id: id, def: effectiveDef)

        var targetRanges: [NSRange] = []
        storage.enumerateAttribute(.docxEditCharStyleId, in: full, options: []) { val, range, _ in
            guard let sid = val as? String, sid == id else { return }
            targetRanges.append(range)
        }
        guard !targetRanges.isEmpty else { return }

        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        for r in targetRanges {
            applyStandardCharacterStyle(style, to: storage, range: r)
        }
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    func effectiveCharacterStyle(id: String) -> CharacterStyleDef {
        if let override = session?.bridge.characterStyleOverrides[id] {
            return override
        }
        return StandardCharacterStyle.find(id: id)?.def
            ?? CharacterStyleDef(name: id)
    }

    func overrideCharacterStyle(id: String, def: CharacterStyleDef) {
        guard let session else { return }
        session.bridge.setCharacterStyleOverride(id: id, def: def)
        session.markDirty()
        reapplyCharacterStyleAcrossDocument(id: id)
    }

    func resetCharacterStyle(id: String) {
        guard let session else { return }
        session.bridge.setCharacterStyleOverride(id: id, def: nil)
        session.markDirty()
        reapplyCharacterStyleAcrossDocument(id: id)
    }

    /// Переключает отображение непечатаемых символов (пробелы точками, табы стрелками,
    /// концы абзаца знаком ¶). AppKit рендерит их автоматически, когда
    /// `NSLayoutManager.showsInvisibleCharacters == true` и `showsControlCharacters == true`.
    func toggleInvisibleCharacters() {
        showsInvisibleCharacters.toggle()
        guard let lm = textView?.layoutManager as? DocxLayoutManager else { return }
        lm.showsCustomInvisibles = showsInvisibleCharacters
        textView?.needsDisplay = true
    }

    // MARK: - Правописание и замены (v0.1.56)

    /// Синхронизирует @Published-поля с реальным состоянием NSTextView.
    /// Вызывается при появлении textView (setUp) и после каждого toggle.
    func syncReviewFlags() {
        guard let tv = textView else { return }
        continuousSpellCheck = tv.isContinuousSpellCheckingEnabled
        grammarCheck = tv.isGrammarCheckingEnabled
        smartQuotes = tv.isAutomaticQuoteSubstitutionEnabled
        smartDashes = tv.isAutomaticDashSubstitutionEnabled
        dataDetectors = tv.isAutomaticDataDetectionEnabled
    }

    func showSpellingChecker() {
        guard let tv = textView else { return }
        // Открывает системную панель «Правописание и грамматика» и позиционирует
        // курсор на первую ошибку (стандартное поведение NSTextView.showGuessPanel).
        tv.showGuessPanel(nil)
    }
    /// v0.3.2: применяет все слова из пользовательского словаря к NSSpellChecker.
    /// Вызывается один раз при `attach(session:)` — spell checker удерживает
    /// заученные слова в течение жизни процесса.
    func applyCustomDictionary() {
        let checker = NSSpellChecker.shared
        for w in AppPreferences.shared.customDictionary where !w.isEmpty {
            checker.learnWord(w)
        }
    }

    /// Добавляет слово в пользовательский словарь + учит spell checker.
    func addToCustomDictionary(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        var list = AppPreferences.shared.customDictionary
        guard !list.contains(w) else { return }
        list.append(w)
        AppPreferences.shared.customDictionary = list
        NSSpellChecker.shared.learnWord(w)
        // Форсируем перепроверку — новое слово должно перестать подчёркиваться.
        if let tv = textView {
            let was = tv.isContinuousSpellCheckingEnabled
            tv.isContinuousSpellCheckingEnabled = false
            tv.isContinuousSpellCheckingEnabled = was
        }
    }

    /// Удаляет слово из пользовательского словаря + отучает spell checker.
    func removeFromCustomDictionary(_ word: String) {
        var list = AppPreferences.shared.customDictionary
        list.removeAll { $0 == word }
        AppPreferences.shared.customDictionary = list
        NSSpellChecker.shared.unlearnWord(word)
        if let tv = textView {
            let was = tv.isContinuousSpellCheckingEnabled
            tv.isContinuousSpellCheckingEnabled = false
            tv.isContinuousSpellCheckingEnabled = was
        }
    }

    func toggleContinuousSpellCheck() {
        guard let tv = textView else { return }
        tv.isContinuousSpellCheckingEnabled.toggle()
        continuousSpellCheck = tv.isContinuousSpellCheckingEnabled
    }
    func toggleGrammarCheck() {
        guard let tv = textView else { return }
        tv.isGrammarCheckingEnabled.toggle()
        grammarCheck = tv.isGrammarCheckingEnabled
    }
    func toggleSmartQuotes() {
        guard let tv = textView else { return }
        tv.isAutomaticQuoteSubstitutionEnabled.toggle()
        smartQuotes = tv.isAutomaticQuoteSubstitutionEnabled
    }
    func toggleSmartDashes() {
        guard let tv = textView else { return }
        tv.isAutomaticDashSubstitutionEnabled.toggle()
        smartDashes = tv.isAutomaticDashSubstitutionEnabled
    }
    func toggleDataDetectors() {
        guard let tv = textView else { return }
        tv.isAutomaticDataDetectionEnabled.toggle()
        dataDetectors = tv.isAutomaticDataDetectionEnabled
    }

    func showFindBar()    { performFinder(.showFindInterface) }
    func showReplaceBar() { performFinder(.showReplaceInterface) }
    func showGoToDialog() { NotificationCenter.default.post(name: .docxEditShowGoTo, object: nil) }

    // MARK: - Расширенный поиск/замена (v0.1.96)

    struct SearchOptions {
        var useRegex: Bool
        var caseSensitive: Bool
        var wholeWord: Bool
    }

    /// Ищет следующее вхождение `pattern` после текущего выделения и выделяет его.
    /// Возвращает true, если нашли (курсор/выделение переставлены).
    @discardableResult
    func findNext(pattern: String, options: SearchOptions) -> Bool {
        currentPattern = pattern
        guard let tv = textView, let storage = tv.textStorage, !pattern.isEmpty else { return false }
        let full = NSRange(location: 0, length: storage.length)
        let start = min(tv.selectedRange().upperBound, storage.length)
        // Первый проход — от текущей позиции до конца; если ничего — с начала.
        for searchRange in [NSRange(location: start, length: storage.length - start), full] {
            if let match = firstMatch(in: storage.string, pattern: pattern, options: options, range: searchRange) {
                tv.setSelectedRange(match)
                tv.scrollRangeToVisible(match)
                updateFindCurrentIndex(pattern: pattern, options: options)
                return true
            }
        }
        return false
    }

    /// Заменяет ТЕКУЩЕЕ выделение (если оно совпадает с pattern) на replacement,
    /// затем переходит к следующему совпадению. Возвращает true при замене.
    @discardableResult
    func replaceCurrent(pattern: String, replacement: String, options: SearchOptions) -> Bool {
        currentPattern = pattern
        guard let tv = textView, let storage = tv.textStorage, !pattern.isEmpty else { return false }
        let sel = tv.selectedRange()
        if sel.length > 0 {
            // Совпадает ли текущее выделение с pattern? — сверяем через regex/plain.
            let selRange = NSRange(location: sel.location, length: sel.length)
            if let match = firstMatch(in: storage.string, pattern: pattern, options: options, range: selRange),
               match == selRange {
                guard tv.shouldChangeText(in: match, replacementString: replacement) else { return false }
                let replaced = expandReplacement(replacement, matchRange: match, in: storage.string, options: options)
                storage.replaceCharacters(in: match, with: replaced)
                tv.didChangeText()
                notifyModelChange()
                // Курсор — после вставки; ищем дальше.
                let newLoc = match.location + (replaced as NSString).length
                tv.setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
        return findNext(pattern: pattern, options: options)
    }

    /// Заменяет ВСЕ вхождения от начала документа. Возвращает число замен.
    @discardableResult
    func replaceAll(pattern: String, replacement: String, options: SearchOptions) -> Int {
        currentPattern = pattern
        guard let tv = textView, let storage = tv.textStorage, !pattern.isEmpty else { return 0 }
        let ranges = allMatches(in: storage.string, pattern: pattern, options: options,
                                range: NSRange(location: 0, length: storage.length))
        guard !ranges.isEmpty else { return 0 }
        // Union range — для undo.
        let union = ranges.reduce(ranges[0]) { NSUnionRange($0, $1) }
        guard tv.shouldChangeText(in: union, replacementString: nil) else { return 0 }
        storage.beginEditing()
        // Идём справа налево — позиции ранних диапазонов не смещаются.
        for m in ranges.reversed() {
            let repl = expandReplacement(replacement, matchRange: m, in: storage.string, options: options)
            storage.replaceCharacters(in: m, with: repl)
        }
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
        return ranges.count
    }

    /// v0.3.3: количество совпадений в документе — для отображения в диалоге
    /// поиска. Не двигает выделение.
    func countMatches(pattern: String, options: SearchOptions) -> Int {
        guard let storage = textView?.textStorage, !pattern.isEmpty else { return 0 }
        return allMatches(in: storage.string, pattern: pattern, options: options,
                          range: NSRange(location: 0, length: storage.length)).count
    }

    // MARK: - Подсветка всех вхождений (v1.5.18)


    /// Все диапазоны совпадений (порядок документа).
    func matchRanges(pattern: String, options: SearchOptions) -> [NSRange] {
        guard let storage = textView?.textStorage, !pattern.isEmpty else { return [] }
        return allMatches(in: storage.string, pattern: pattern, options: options,
                          range: NSRange(location: 0, length: storage.length))
    }

    /// Включает/обновляет подсветку всех вхождений (рисует DocxLayoutManager).
    func showFindHighlights(pattern: String, options: SearchOptions) {
        let ranges = matchRanges(pattern: pattern, options: options)
        (textView?.layoutManager as? DocxLayoutManager)?.findHighlights = ranges
        findHighlightsActive = !ranges.isEmpty
        textView?.needsDisplay = true
        updateFindCurrentIndex(pattern: pattern, options: options)
    }

    /// Снимает подсветку.
    func clearFindHighlights() {
        (textView?.layoutManager as? DocxLayoutManager)?.findHighlights = []
        findHighlightsActive = false
        findCurrentIndex = nil
        textView?.needsDisplay = true
    }

    /// Индекс текущего выделения в списке совпадений.
    private func updateFindCurrentIndex(pattern: String, options: SearchOptions) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        let ranges = matchRanges(pattern: pattern, options: options)
        findCurrentIndex = ranges.firstIndex(of: sel).map { $0 + 1 }
    }

    // Внутренние утилиты поиска.

    private func firstMatch(in text: String, pattern: String, options: SearchOptions, range: NSRange) -> NSRange? {
        if options.useRegex {
            guard let re = compileRegex(pattern, options: options) else { return nil }
            return re.firstMatch(in: text, options: [], range: range)?.range
        }
        var opts: String.CompareOptions = []
        if !options.caseSensitive { opts.insert(.caseInsensitive) }
        let ns = text as NSString
        var loc = range.location
        let end = range.location + range.length
        while loc < end {
            let sub = NSRange(location: loc, length: end - loc)
            let r = ns.range(of: pattern, options: opts, range: sub)
            if r.location == NSNotFound { return nil }
            if !options.wholeWord || isWholeWordMatch(r, in: ns) { return r }
            loc = r.location + 1
        }
        return nil
    }

    private func allMatches(in text: String, pattern: String, options: SearchOptions, range: NSRange) -> [NSRange] {
        if options.useRegex {
            guard let re = compileRegex(pattern, options: options) else { return [] }
            return re.matches(in: text, options: [], range: range).map(\.range)
        }
        var out: [NSRange] = []
        var loc = range.location
        while let m = firstMatch(in: text, pattern: pattern, options: options,
                                 range: NSRange(location: loc, length: range.upperBound - loc)) {
            out.append(m)
            loc = m.location + max(1, m.length)
            if loc >= range.upperBound { break }
        }
        return out
    }

    private func compileRegex(_ pattern: String, options: SearchOptions) -> NSRegularExpression? {
        var opts: NSRegularExpression.Options = []
        if !options.caseSensitive { opts.insert(.caseInsensitive) }
        let effectivePattern = options.wholeWord ? "\\b(?:\(pattern))\\b" : pattern
        return try? NSRegularExpression(pattern: effectivePattern, options: opts)
    }

    private func isWholeWordMatch(_ r: NSRange, in text: NSString) -> Bool {
        let isWord: (unichar) -> Bool = { c in
            (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c >= 0x80
        }
        if r.location > 0, isWord(text.character(at: r.location - 1)) { return false }
        let end = r.location + r.length
        if end < text.length, isWord(text.character(at: end)) { return false }
        return true
    }

    /// Подстановка групп ($1, $2, ...) для regex; для plain-режима возвращает как есть.
    private func expandReplacement(_ replacement: String, matchRange: NSRange, in text: String, options: SearchOptions) -> String {
        guard options.useRegex, let re = compileRegex(currentPattern, options: options) else { return replacement }
        // Прогоняем ту же регулярку по matchRange и получаем NSTextCheckingResult
        // — тогда `replacementString(for:in:offset:template:)` подставит группы.
        guard let match = re.firstMatch(in: text, options: [], range: matchRange) else { return replacement }
        return re.replacementString(for: match, in: text, offset: 0, template: replacement)
    }


    /// Вставляет таблицу N×M в позиции курсора. Строится `TableBlock` с пустыми
    /// ячейками, рендерится через `appendTable` (NSTextTable + NSTextTableBlock),
    /// сплайсится в storage одним атомарным `replaceCharacters` под
    /// `shouldChangeText` — один шаг undo (паттерн ADR-027). После таблицы
    /// добавляется пустой абзац без `textBlocks`, чтобы курсор мог встать ниже.
    func insertTable(rows: Int, cols: Int) {
        guard rows > 0, cols > 0 else { return }
        guard let tv = textView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()

        let emptyPara = Paragraph(runs: [Run(text: "", attributes: CharacterAttributes())], attributes: ParagraphAttributes())
        let modelRows: [DocxCore.TableRow] = (0..<rows).map { _ in
            DocxCore.TableRow(cells: (0..<cols).map { _ in TableCell(blocks: [.paragraph(emptyPara)]) })
        }
        let table = TableBlock(rows: modelRows)

        let ns = storage.string as NSString
        var prefixNL = false
        if sel.location > 0, sel.location <= storage.length {
            let prevIdx = sel.location - 1
            if prevIdx < ns.length {
                let prevChar = ns.substring(with: NSRange(location: prevIdx, length: 1))
                if prevChar != "\n" { prefixNL = true }
            }
        }

        let payload = NSMutableAttributedString()
        let typingAttrs = tv.typingAttributes
        let defaultFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        if prefixNL {
            payload.append(NSAttributedString(string: "\n", attributes: typingAttrs))
        }
        appendTable(table, to: payload, defaultFont: defaultFont,
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: pageUsableWidth)
        // Хвостовой пустой абзац без textBlocks — точка для курсора ниже таблицы.
        var trailingAttrs = typingAttrs
        trailingAttrs.removeValue(forKey: .paragraphStyle)
        payload.append(NSAttributedString(string: "\n", attributes: trailingAttrs))

        guard tv.shouldChangeText(in: sel, replacementString: payload.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: payload)
        storage.endEditing()
        tv.didChangeText()
        // Курсор — в первую ячейку.
        let firstCellLoc = sel.location + (prefixNL ? 1 : 0)
        tv.setSelectedRange(NSRange(location: firstCellLoc, length: 0))
        notifyModelChange()
    }

}
