//
//  DocumentController.swift
//  DocxEdit
//
//  ViewModel главного окна: мост между SwiftUI и NSTextView.
//  v0.1.7: strikethrough, page-view mode, zoom.
//

import SwiftUI
import AppKit
import DocxCore
import MarkdownIO
import UniformTypeIdentifiers
import NaturalLanguage

/// Семейство шрифта, использующееся в документе, с флагом отсутствия в системе.
struct FontUsage: Identifiable {
    let id: String
    var isMissing: Bool
}

@MainActor
final class DocumentController: ObservableObject {
    @Published var statusText: String = "Готов"
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    /// Пустая строка — смешанное выделение с разными шрифтами.
    @Published var fontName: String = "Times New Roman"
    /// 0 — смешанное выделение с разными размерами.
    @Published var fontSize: CGFloat = 12
    @Published var hasMixedFonts: Bool = false
    @Published var hasMixedSizes: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var isSuperscript: Bool = false
    @Published var isSubscript: Bool = false
    @Published var textAlignment: NSTextAlignment = .left
    /// Текущий межстрочный множитель выделения (1.0 = одинарный).
    @Published var lineSpacingMultiple: CGFloat = 1.0
    @Published var textColor: NSColor = .labelColor
    @Published var highlightColor: NSColor? = nil
    // По умолчанию — «Вид страницы» (лист как при печати), как в мейнстрим-редакторов.
    @Published var isPageView: Bool = true
    @Published var zoomLevel: Double = 1.0
    /// Тип списка в текущем абзаце/выделении (nil — обычный абзац).
    @Published var currentListType: ListType? = nil
    /// Вариант многоуровневого списка текущего абзаца (id пресета галереи, nil — не распознан).
    @Published var currentListVariantId: String? = nil
    /// Id стиля текущего абзаца/выделения (по умолчанию — "Normal").
    @Published var currentStyleId: String = "Normal"
    @Published var currentCharStyleId: String? = nil
    /// Показывать непечатаемые символы (пробелы, табы, знаки конца абзаца).
    @Published var showsInvisibleCharacters: Bool = false
    /// Курсор находится внутри ячейки таблицы (для активации/деактивации операций строк/столбцов).
    @Published var isCaretInTable: Bool = false
    /// v0.1.85: текущая строка таблицы помечена как заголовок (`<w:tblHeader/>`).
    @Published var isCurrentRowHeader: Bool = false
    /// v0.1.87: минимальная высота текущей строки таблицы (pt); nil = авто.
    @Published var currentRowHeight: CGFloat? = nil
    /// Определённый язык абзаца/выделения (BCP-47: "en", "ru", …). nil = «не удалось определить».
    @Published var currentLanguageCode: String? = nil
    /// v0.3.1: автопереключение языка проверки орфографии по абзацу.
    /// Читается из AppPreferences; кэш последнего установленного языка чтобы
    /// не дёргать NSSpellChecker.setLanguage на каждое движение курсора.
    var lastAppliedSpellLanguage: String?
    @Published var showsRuler: Bool = false
    @Published var showsStylesSidebar: Bool = false
    /// v0.4.4 (R06): показывать боковую панель комментариев справа.
    @Published var showsCommentsSidebar: Bool = false
    /// v0.5.4 (R07): показывать боковую панель сносок справа.
    @Published var showsFootnotesSidebar: Bool = false

    /// v1.5.9: ширины боковых панелей (меняются драг-разделителем).
    @Published var stylesSidebarWidth: CGFloat = 240
    @Published var commentsSidebarWidth: CGFloat = 280
    @Published var footnotesSidebarWidth: CGFloat = 240
    static let sidebarWidthRange: ClosedRange<CGFloat> = 180...480

    /// v1.5.11: панель навигации по заголовкам (слева, как Navigation Pane в Word).
    @Published var showsNavigatorSidebar: Bool = false
    @Published var navigatorSidebarWidth: CGFloat = 220
    /// v1.6.5: позиция заголовка текущего раздела (для подсветки в навигаторе).
    @Published var currentHeadingLocation: Int? = nil
    /// Счётчик редакций текста — инкрементится в userDidEdit; панели,
    /// пересчитывающие содержимое (навигатор), подписываются на него.
    @Published var textRevision: Int = 0

    func toggleNavigatorSidebar() { showsNavigatorSidebar.toggle() }

    func toggleCommentsSidebar() { showsCommentsSidebar.toggle() }
    func toggleFootnotesSidebar() { showsFootnotesSidebar.toggle() }
    /// v0.4.3 (R06): режим «Чтение» — только view-состояние (`isEditable=false`
    /// + скрытие ribbon, увеличенные поля через zoom). Модели не касается.
    @Published var isReadingMode: Bool = false

    func toggleRuler() {
        showsRuler.toggle()
        let sv = textView?.enclosingScrollView
        sv?.rulersVisible = showsRuler
        // v1.5.10: убираем accessory-вид линейки (Стили/выравнивание/интервалы/
        // списки — наследие TextEdit): он устарел и дублирует ribbon.
        if showsRuler { sv?.horizontalRulerView?.accessoryView = nil }
    }

    func toggleStylesSidebar() { showsStylesSidebar.toggle() }

    /// v0.4.3: вход/выход из режима чтения. NSTextView становится
    /// нередактируемым, зум подкидывается до 125% (шаг из существующей
    /// шкалы), ribbon скрывается в DocumentWindowView через биндинг
    /// `isReadingMode`. При выходе восстанавливается zoomLevel до входа
    /// и `isEditable = true`.
    private var zoomLevelBeforeReading: Double = 1.0
    func toggleReadingMode() {
        guard let tv = textView else { return }
        if !isReadingMode {
            zoomLevelBeforeReading = zoomLevel
            isReadingMode = true
            tv.isEditable = false
            setZoom(1.25)
        } else {
            isReadingMode = false
            tv.isEditable = true
            setZoom(zoomLevelBeforeReading)
        }
    }

    // MARK: - Правописание и замены (v0.1.56)
    // Отражают состояние NSTextView для binding в ribbon-вкладку «Обзор».
    @Published var continuousSpellCheck: Bool = true
    @Published var grammarCheck: Bool = false
    @Published var smartQuotes: Bool = false
    @Published var smartDashes: Bool = false
    @Published var dataDetectors: Bool = false

    weak var textView: NSTextView?
    var session: DocumentSession?

    /// Все семейства шрифтов, установленных в системе.
    let availableFonts: [String] = NSFontManager.shared
        .availableFontFamilies
        .sorted()

    /// Устанавливается из onAppear окна.
    // MARK: - R06 движки-компаньоны (DESIGN_R06.md §2)
    // Логика подсистем — В САМИХ движках; контроллер только держит ссылку и
    // пробрасывает textView/session в attach.
    let comments = CommentsEngine()
    let trackChanges = TrackChangesEngine()

    func attach(session: DocumentSession) {
        self.session = session
        refreshStatus()
        startAutorecover()
        applyCustomDictionary()
        // R06 движки — привязываем textView/session.
        comments.textView = textView
        comments.session = session
        trackChanges.textView = textView
        trackChanges.session = session
    }

    /// Применяет шрифт к выделенному диапазону (или к typingAttributes, если выделения нет).
    /// Меняет только семейство шрифта — размер и начертание каждого рана сохраняются
    /// (NSFontManager.convert(_:toFamily:) вместо построения одного общего NSFont на весь диапазон).
    func applyFont(name: String) {
        fontName = name
        hasMixedFonts = false
        AppPreferences.shared.noteUsedFont(name)
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let base = textView.typingAttributes[.font] as? NSFont ?? currentFont()
            updateTypingAttributes(font: NSFontManager.shared.convert(base, toFamily: name))
        } else {
            // shouldChangeText регистрирует правку в undo-менеджере NSTextView.
            // applyFontFamily сам делает begin/endEditing — повторный endEditing
            // ломал счётчик редактирования NSTextStorage (краш/флаки).
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            applyFontFamily(name, range: range)
            textView.didChangeText()
            notifyModelChange()
        }
    }

    /// Применяет размер к выделенному диапазону (или к typingAttributes, если выделения нет).
    /// Меняет только размер — семейство и начертание каждого рана сохраняются.
    func applyFontSize(points: CGFloat) {
        fontSize = points
        hasMixedSizes = false
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            let base = textView.typingAttributes[.font] as? NSFont ?? currentFont()
            updateTypingAttributes(font: NSFontManager.shared.convert(base, toSize: points))
        } else {
            // shouldChangeText регистрирует правку в undo-менеджере NSTextView.
            // applyPointSize сам делает begin/endEditing — повторный endEditing
            // ломал счётчик редактирования NSTextStorage (краш/флаки).
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            applyPointSize(points, range: range)
            textView.didChangeText()
            notifyModelChange()
        }
    }

    /// Применяет выравнивание абзаца к параграфам в выделении (или текущему абзацу).
    func applyAlignment(_ alignment: NSTextAlignment) {
        textAlignment = alignment
        mutateSelectedParagraphs { $0.alignment = alignment }
    }

    /// Шаг изменения отступа абзаца (0.5 дюйма, как табуляция в текстовых процессорах).
    private let indentStep: CGFloat = 36

    /// Межстрочный интервал (множитель) для абзацев выделения.
    func applyLineSpacing(_ multiple: CGFloat) {
        lineSpacingMultiple = multiple
        mutateSelectedParagraphs { ps in
            ps.lineHeightMultiple = multiple
            ps.minimumLineHeight = 0
            ps.maximumLineHeight = 0
        }
    }

    /// Применяет отступы абзацев (в pt) ко всем абзацам выделения.
    /// `special`: 0 = none, +X = firstLine (первая строка сдвинута правее на X),
    /// −X = hanging (первая строка сдвинута левее на X). Все параметры — в pt.
    func applyParagraphIndents(left: CGFloat, right: CGFloat, special: CGFloat) {
        mutateSelectedParagraphs { ps in
            let l = max(0, left)
            ps.headIndent = l
            ps.tailIndent = right == 0 ? 0 : -max(0, right)
            if special > 0 {
                ps.firstLineHeadIndent = l + special
            } else if special < 0 {
                ps.firstLineHeadIndent = max(0, l - abs(special))
            } else {
                ps.firstLineHeadIndent = l
            }
        }
    }

    /// Возвращает отступы (в pt) абзаца под курсором: (left, right, special).
    /// `special`: 0 = none, +X = firstLine, −X = hanging.
    func currentParagraphIndents() -> (left: CGFloat, right: CGFloat, special: CGFloat) {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else {
            return (0, 0, 0)
        }
        let loc = min(textView.selectedRange().location, storage.length - 1)
        let ps = storage.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
            ?? NSParagraphStyle.default
        let left = ps.headIndent
        let right = ps.tailIndent == 0 ? 0 : -ps.tailIndent
        let fl = ps.firstLineHeadIndent
        let special: CGFloat
        if fl < left { special = -(left - fl) }
        else if fl > left { special = fl - left }
        else { special = 0 }
        return (left, right, special)
    }

    /// Увеличить левый отступ абзацев выделения на один шаг. Для абзацев списка
    /// увеличивает уровень вложенности (0-8) со сменой маркера на формат уровня.
    func increaseIndent() { changeIndent(+1) }

    /// Уменьшить левый отступ абзацев выделения на один шаг (не ниже нуля).
    /// Для абзацев списка уменьшает уровень вложенности со сменой маркера.
    func decreaseIndent() { changeIndent(-1) }

    private func changeIndent(_ direction: Int) {
        guard let storage = textView?.textStorage else { return }
        // Если в выделении есть абзацы списка — меняем уровень вложенности с заменой
        // маркера и перенумерацией блока; иначе — чистая правка отступа стиля.
        if selectedParagraphRanges().contains(where: { listInfo(at: $0.location, in: storage) != nil }) {
            applyListEdit(.indent(direction))
        } else {
            mutateSelectedParagraphs { [indentStep] ps in
                let delta = CGFloat(direction) * indentStep
                ps.headIndent = max(0, ps.headIndent + delta)
                ps.firstLineHeadIndent = max(0, ps.firstLineHeadIndent + delta)
            }
        }
    }

    /// Переключает маркированный/нумерованный список для абзацев выделения (или текущего абзаца).
    /// Если ВСЕ затронутые абзацы уже являются списком того же типа — список снимается.
    /// Иначе — список включается (или тип меняется с буллитов на нумерацию и наоборот);
    /// уровень вложенности сохраняется, если абзац уже был в другом типе списка.
    func toggleList(_ type: ListType) { applyListEdit(.toggle(type)) }

    /// Применяет вариант многоуровневого списка (галерея «1. a. i.», «1. 1.1.», «• ○ ▪»…)
    /// ко всему непрерывному списку вокруг выделения (как принято в OOXML); если выделение
    /// вне списка — превращает абзацы выделения в список этого варианта.
    func applyListVariant(id: String) {
        guard let variant = MultilevelListVariant.presets.first(where: { $0.id == id }) else { return }
        applyListVariant(variant)
    }

    func applyListVariant(_ variant: MultilevelListVariant) {
        lastVariant[variant.listType] = variant
        applyListEdit(.variant(variant))
    }

    /// Правка списка: включение/выключение, смена варианта, смена уровня вложенности.
    private enum ListEdit {
        case toggle(ListType)
        case variant(MultilevelListVariant)
        case indent(Int)
    }

    /// Последний применённый вариант многоуровневого списка по типу — определяет
    /// формат маркера новых уровней при ⌘]/⌘[ и повторном включении списка.
    var lastVariant: [ListType: MultilevelListVariant] = [:]

    /// listInfo абзаца по позиции его начала (из NSParagraphStyle).
    private func listInfo(at loc: Int, in storage: NSTextStorage) -> ListInfo? {
        guard storage.length > 0 else { return nil }
        let safeLoc = min(loc, storage.length - 1)
        guard let ps = storage.attribute(.paragraphStyle, at: safeLoc, effectiveRange: nil) as? NSParagraphStyle
        else { return nil }
        return ParagraphAttributes.from(nsParagraphStyle: ps).listInfo
    }

    /// Вариант многоуровневого списка, которому соответствует абзац: сперва последний
    /// применённый вариант этого типа, затем пресеты галереи, затем дефолт типа.
    func detectVariant(for info: ListInfo) -> MultilevelListVariant {
        if let v = lastVariant[info.listType], v.format(at: info.level) == info.formatStyle { return v }
        if let v = MultilevelListVariant.presets.first(where: {
            $0.listType == info.listType && $0.format(at: info.level) == info.formatStyle
        }) { return v }
        return .default(for: info.listType)
    }

    /// Единый маршрут всех правок списка. Диапазон расширяется до всего непрерывного
    /// блока списка вокруг выделения (номера соседних элементов меняются при любой
    /// правке), содержимое перегенерируется с иерархической нумерацией и заменяется
    /// ЕДИНЫМ replaceCharacters: NSTextView не умеет надёжно собрать из нескольких
    /// несмежных правок один шаг undo (ADR-027) — атомарный replace даёт корректный Cmd+Z.
    private func applyListEdit(_ edit: ListEdit) {
        guard let textView, let storage = textView.textStorage else { return }
        let selectedRanges = selectedParagraphRanges()
        guard !selectedRanges.isEmpty else { return }
        let fullText = storage.string as NSString

        // Расширение до непрерывного блока списка (вверх и вниз от выделения).
        var start = selectedRanges.first!.location
        var end = NSMaxRange(selectedRanges.last!)
        while start > 0 {
            let prev = fullText.paragraphRange(for: NSRange(location: start - 1, length: 0))
            guard listInfo(at: prev.location, in: storage) != nil else { break }
            start = prev.location
        }
        while end < storage.length {
            let next = fullText.paragraphRange(for: NSRange(location: end, length: 0))
            guard next.length > 0, listInfo(at: next.location, in: storage) != nil else { break }
            end = NSMaxRange(next)
        }
        let overallRange = NSRange(location: start, length: end - start)

        var paraRanges: [NSRange] = []
        var loc = start
        while loc < end {
            let r = fullText.paragraphRange(for: NSRange(location: loc, length: 0))
            paraRanges.append(r)
            loc = NSMaxRange(r)
            if r.length == 0 { break }
        }
        if paraRanges.isEmpty { paraRanges = selectedRanges }
        let selectedLocs = Set(selectedRanges.map(\.location))

        var turnOff = false
        if case .toggle(let type) = edit {
            turnOff = selectedRanges.allSatisfy { listInfo(at: $0.location, in: storage)?.listType == type }
        }

        let newContent = NSMutableAttributedString()
        var counters = ListCounters()

        for range in paraRanges {
            let existing = listInfo(at: range.location, in: storage)
            let paraContent = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))

            // Существующий буквальный маркер отбрасываем — он будет перегенерирован.
            if let info = existing,
               let markerLen = listMarkerPrefixLength(in: paraContent.string, for: info.formatStyle) {
                paraContent.deleteCharacters(in: NSRange(location: 0, length: markerLen))
            }

            // Базовые атрибуты абзаца — сохраняем выравнивание/интервалы/отступы.
            let basePs: NSParagraphStyle = storage.length > 0
                ? (storage.attribute(.paragraphStyle, at: min(range.location, storage.length - 1), effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle())
                : NSParagraphStyle()
            var attrs = ParagraphAttributes.from(nsParagraphStyle: basePs)

            var newInfo: ListInfo? = existing
            if selectedLocs.contains(range.location) {
                switch edit {
                case .toggle(let type):
                    if turnOff {
                        newInfo = nil
                    } else {
                        let level = existing?.level ?? 0
                        let variant = lastVariant[type] ?? .default(for: type)
                        newInfo = ListInfo(listType: type, level: level, continuation: .continue,
                                           formatStyle: variant.format(at: level))
                    }
                case .variant(let variant):
                    let level = existing?.level ?? 0
                    newInfo = ListInfo(listType: variant.listType, level: level, continuation: .continue,
                                       formatStyle: variant.format(at: level))
                case .indent(let d):
                    if let info = existing {
                        let level = max(0, min(8, info.level + d))
                        let variant = detectVariant(for: info)
                        newInfo = ListInfo(listType: info.listType, level: level, continuation: .continue,
                                           formatStyle: variant.format(at: level))
                    } else {
                        // Не-списочный абзац в смешанном выделении — обычный отступ.
                        let delta = CGFloat(d) * indentStep
                        attrs.leftIndent = max(0, attrs.leftIndent + delta)
                        attrs.firstLineIndent = max(0, attrs.firstLineIndent + delta)
                    }
                }
            } else if case .variant(let variant) = edit, let info = existing {
                // Вариант применяется ко всему непрерывному списку (как принято в OOXML).
                newInfo = ListInfo(listType: variant.listType, level: info.level, continuation: .continue,
                                   formatStyle: variant.format(at: info.level))
            }

            attrs.listInfo = newInfo
            let ps = attrs.makeNSParagraphStyle()

            if let info = newInfo {
                let stack = counters.next(level: info.level, format: info.formatStyle, start: info.start)
                let markerText = listMarkerText(for: info.formatStyle, counters: stack)
                let markerFont = paraContent.length > 0
                    ? (paraContent.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? currentFont())
                    : currentFont()
                paraContent.insert(
                    NSAttributedString(string: markerText, attributes: [.font: markerFont, .paragraphStyle: ps]),
                    at: 0
                )
            } else {
                counters.breakSequence()
            }
            paraContent.addAttribute(.paragraphStyle, value: ps,
                                     range: NSRange(location: 0, length: paraContent.length))
            newContent.append(paraContent)
        }

        guard textView.shouldChangeText(in: overallRange, replacementString: newContent.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: overallRange, with: newContent)
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    // MARK: - Живая перенумерация списков (Return/Delete)

    /// Установлен из `doCommandBy` при Return/Delete, если курсор в списке; читается
    /// один раз в `textDidChange` после того, как правка уже применена.
    var pendingListRenumber = false
    private var isRenumberingList = false

    func consumePendingListRenumber() -> Bool {
        guard pendingListRenumber else { return false }
        pendingListRenumber = false
        return true
    }

    // MARK: - MD-режим: Return на пустой структуре (v1.4.3, ADR-049)

    /// Return на пустом элементе списка или пустой цитате в MD-режиме — выход
    /// из структуры (список/стиль снимается с ТЕКУЩЕГО абзаца), а не добавление
    /// нового пункта — как в Typora/Word. Возвращает true, если Return перехвачен.
    /// Продолжение списка/цитаты на непустом абзаце работает без перехвата:
    /// новый абзац наследует paragraphStyle/.docxEditStyleId через typingAttributes,
    /// список перенумеровывается через pendingListRenumber (v0.1.43).
    func handleReturnOnEmptyMarkdownStructure() -> Bool {
        guard session?.mode == .markdown,
              let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0, sel.location <= storage.length else { return false }
        let fullText = storage.string as NSString
        let pr = fullText.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let paraText = fullText.substring(with: pr).trimmingCharacters(in: .newlines)

        // Пустой элемент списка → снять список с текущего абзаца (один шаг undo
        // через applyListEdit; остаток блока перенумеруется, ADR-028).
        if let info = listInfo(at: pr.location, in: storage) {
            let mLen = listMarkerPrefixLength(in: paraText, for: info.formatStyle) ?? 0
            let content = String(paraText.dropFirst(mLen)).trimmingCharacters(in: .whitespaces)
            guard content.isEmpty else { return false }
            toggleList(info.listType)
            return true
        }

        // Пустая цитата → снять стиль и отступ с абзаца.
        if (storage.attribute(.docxEditStyleId, at: pr.location, effectiveRange: nil) as? String) == "Quote" {
            guard paraText.isEmpty else { return false }
            if textView.shouldChangeText(in: pr, replacementString: nil) {
                storage.beginEditing()
                storage.removeAttribute(.docxEditStyleId, range: pr)
                if let ps = storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle,
                   let mps = ps.mutableCopy() as? NSMutableParagraphStyle {
                    mps.headIndent = 0
                    mps.firstLineHeadIndent = 0
                    storage.addAttribute(.paragraphStyle, value: mps, range: pr)
                }
                storage.endEditing()
                textView.didChangeText()
            }
            notifyModelChange()
            refreshSelectionState()
            return true
        }
        return false
    }

    // MARK: - MD-режим: буфер обмена (v1.4.3, ADR-049)

    /// «Копировать как Markdown» — выделение конвертируется в MD-текст и
    /// кладётся в буфер обмена (поверх обычного текста, как в Typora).
    func copyAsMarkdown() {
        guard let textView, let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        guard sel.length > 0, NSMaxRange(sel) <= storage.length else { return }
        let sub = storage.attributedSubstring(from: sel)
        let model = DocumentModel.from(attributed: sub)
        let md = MarkdownIO.exportMarkdown(model, prettyTables: AppPreferences.shared.markdownPrettyTables)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    /// «Вставить из Markdown» — MD-текст буфера конвертируется в модель и
    /// вставляется в позицию курсора одним шагом undo.
    func pasteAsMarkdown() {
        guard let textView, let storage = textView.textStorage,
              let md = NSPasteboard.general.string(forType: .string), !md.isEmpty,
              let model = try? MarkdownIO.importMarkdown(string: md) else { return }
        let attr = model.toAttributedString(
            defaultFont: DocumentSession.currentDefaultAttributes()[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: 12),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first)
        let sel = textView.selectedRange()
        guard textView.shouldChangeText(in: sel, replacementString: attr.string) else { return }
        storage.replaceCharacters(in: sel, with: attr)
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Курсор (или его абзац) находится внутри блока списка?
    func caretInListBlock() -> Bool {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let caret = min(textView.selectedRange().location, storage.length)
        let para = (storage.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        return listInfo(at: para.location, in: storage) != nil
    }

    /// Перенумеровывает непрерывный блок списка вокруг курсора, сохраняя позицию
    /// курсора относительно содержимого абзаца. Вызывается после структурной правки
    /// (вставка/удаление абзаца) — числа нумерованных списков пересчитываются вживую.
    func renumberCurrentListBlock() {
        guard !isRenumberingList else { return }
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let caret = min(textView.selectedRange().location, storage.length)
        let fullText = storage.string as NSString
        let caretPara = fullText.paragraphRange(for: NSRange(location: caret, length: 0))
        guard listInfo(at: caretPara.location, in: storage) != nil else { return }

        // Расширяем до непрерывного блока списка.
        var start = caretPara.location
        var end = NSMaxRange(caretPara)
        while start > 0 {
            let prev = fullText.paragraphRange(for: NSRange(location: start - 1, length: 0))
            guard listInfo(at: prev.location, in: storage) != nil else { break }
            start = prev.location
        }
        while end < storage.length {
            let next = fullText.paragraphRange(for: NSRange(location: end, length: 0))
            guard next.length > 0, listInfo(at: next.location, in: storage) != nil else { break }
            end = NSMaxRange(next)
        }
        let overallRange = NSRange(location: start, length: end - start)

        var paraRanges: [NSRange] = []
        var loc = start
        while loc < end {
            let r = fullText.paragraphRange(for: NSRange(location: loc, length: 0))
            paraRanges.append(r); loc = NSMaxRange(r)
            if r.length == 0 { break }
        }
        guard !paraRanges.isEmpty else { return }

        // Позиция курсора: индекс абзаца + смещение внутри содержимого (после маркера).
        // На границе абзацев (caret == конец абзаца i == начало i+1) выбираем i+1 —
        // строку, на которой курсор визуально стоит. `caret < NSMaxRange` это даёт;
        // если курсор в самом конце блока — берём последний абзац (default).
        var caretParaIdx = paraRanges.count - 1
        for (i, r) in paraRanges.enumerated() where caret < NSMaxRange(r) {
            caretParaIdx = i
            break
        }
        let caretPR = paraRanges[caretParaIdx]
        let caretInfo = listInfo(at: caretPR.location, in: storage)
        let caretMLen = caretInfo.flatMap {
            listMarkerPrefixLength(in: storage.attributedSubstring(from: caretPR).string, for: $0.formatStyle)
        } ?? 0
        let caretContentOffset = max(0, (caret - caretPR.location) - caretMLen)

        let newContent = NSMutableAttributedString()
        var counters = ListCounters()
        var newMarkerLens: [Int] = []
        var newParaStarts: [Int] = []

        for r in paraRanges {
            let info = listInfo(at: r.location, in: storage)
            let paraContent = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: r))
            if let info, let markerLen = listMarkerPrefixLength(in: paraContent.string, for: info.formatStyle) {
                paraContent.deleteCharacters(in: NSRange(location: 0, length: markerLen))
            }
            newParaStarts.append(newContent.length)
            let ps = (storage.attribute(.paragraphStyle, at: min(r.location, storage.length - 1),
                                        effectiveRange: nil) as? NSParagraphStyle) ?? NSParagraphStyle()
            if let info {
                let stack = counters.next(level: info.level, format: info.formatStyle, start: info.start)
                let markerText = listMarkerText(for: info.formatStyle, counters: stack)
                let markerFont = paraContent.length > 0
                    ? (paraContent.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? currentFont())
                    : currentFont()
                paraContent.insert(NSAttributedString(string: markerText,
                                                      attributes: [.font: markerFont, .paragraphStyle: ps]), at: 0)
                newMarkerLens.append((markerText as NSString).length)
            } else {
                counters.breakSequence()
                newMarkerLens.append(0)
            }
            paraContent.addAttribute(.paragraphStyle, value: ps,
                                     range: NSRange(location: 0, length: paraContent.length))
            newContent.append(paraContent)
        }

        // Если текст блока не изменился (маркеры уже верны) — ничего не делаем.
        // Заодно защищает от рекурсии через didChangeText.
        if newContent.string == fullText.substring(with: overallRange) { return }

        isRenumberingList = true
        defer { isRenumberingList = false }
        guard textView.shouldChangeText(in: overallRange, replacementString: newContent.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: overallRange, with: newContent)
        storage.endEditing()
        textView.didChangeText()

        let idx = min(caretParaIdx, newParaStarts.count - 1)
        let newCaret = start + newParaStarts[idx] + newMarkerLens[idx] + caretContentOffset
        textView.setSelectedRange(NSRange(location: min(newCaret, storage.length), length: 0))
        refreshSelectionState()
    }

    /// Диапазоны абзацев, затронутых текущим выделением (или текущий абзац курсора).
    func selectedParagraphRanges() -> [NSRange] {
        guard let textView, let storage = textView.textStorage else { return [] }
        let sel = textView.selectedRange()
        let fullText = storage.string as NSString
        var paraRanges: [NSRange] = []
        if sel.length == 0 {
            paraRanges.append(fullText.paragraphRange(for: sel))
        } else {
            var loc = sel.location
            while loc < NSMaxRange(sel) {
                let r = fullText.paragraphRange(for: NSRange(location: loc, length: 0))
                paraRanges.append(r)
                loc = NSMaxRange(r)
                if r.length == 0 { break }
            }
        }
        return paraRanges
    }

    /// Применяет правку `NSMutableParagraphStyle` ко всем абзацам выделения
    /// (или к текущему абзацу). Регистрирует undo через shouldChangeText.
    private func mutateSelectedParagraphs(_ mutate: (NSMutableParagraphStyle) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let paraRanges = selectedParagraphRanges()
        // Диапазон, покрывающий все затронутые абзацы — для регистрации undo.
        guard let affected = paraRanges.reduce(nil as NSRange?, { acc, r in
            acc.map { NSUnionRange($0, r) } ?? r
        }) else { return }
        guard textView.shouldChangeText(in: affected, replacementString: nil) else { return }
        storage.beginEditing()
        for paraRange in paraRanges where paraRange.length > 0 {
            storage.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { val, subRange, _ in
                let ps = (val as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                mutate(ps)
                storage.addAttribute(.paragraphStyle, value: ps, range: subRange)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Применяет цвет текста к выделению (или к typingAttributes).
    func applyTextColor(_ color: NSColor) {
        textColor = color
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            attrs[.foregroundColor] = color
            textView.typingAttributes = attrs
        } else {
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            textView.textStorage?.beginEditing()
            textView.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
            textView.textStorage?.endEditing()
            textView.didChangeText()
            notifyModelChange()
        }
    }

    /// Применяет цвет подсветки текста (v0.1.82). `nil` — снимает подсветку.
    func applyHighlightColor(_ color: NSColor?) {
        highlightColor = color
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            if let c = color { attrs[.backgroundColor] = c }
            else { attrs.removeValue(forKey: .backgroundColor) }
            textView.typingAttributes = attrs
        } else {
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            textView.textStorage?.beginEditing()
            if let c = color {
                textView.textStorage?.addAttribute(.backgroundColor, value: c, range: range)
            } else {
                textView.textStorage?.removeAttribute(.backgroundColor, range: range)
            }
            textView.textStorage?.endEditing()
            textView.didChangeText()
            notifyModelChange()
        }
        refreshSelectionState()
    }

    /// Toggle B/I/U для выделенного диапазона. Если выделения нет — только typingAttributes.
    func toggleBold() { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }
    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            // Без выделения: меняем typingAttributes
            var attrs = textView.typingAttributes
            let hasUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
            if hasUnderline {
                attrs[.underlineStyle] = 0
                isUnderline = false
            } else {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                isUnderline = true
            }
            textView.typingAttributes = attrs
        } else {
            // С выделением: определяем текущее состояние по первому символу,
            // и применяем новое ко всему диапазону.
            let firstAttrs = textView.textStorage?.attributes(at: range.location, effectiveRange: nil) ?? [:]
            let currentlyUnderlined = ((firstAttrs[.underlineStyle] as? Int) ?? 0) != 0
            let newValue = currentlyUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            textView.textStorage?.beginEditing()
            textView.textStorage?.addAttribute(.underlineStyle, value: newValue, range: range)
            textView.textStorage?.endEditing()
            isUnderline = !currentlyUnderlined
            textView.didChangeText()
            notifyModelChange()
        }
    }

    func toggleStrikethrough() {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let has = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            attrs[.strikethroughStyle] = has ? 0 : NSUnderlineStyle.single.rawValue
            isStrikethrough = !has
            textView.typingAttributes = attrs
        } else {
            let storage = textView.textStorage!
            let first = storage.attributes(at: range.location, effectiveRange: nil)
            let has = ((first[.strikethroughStyle] as? Int) ?? 0) != 0
            let newVal = has ? 0 : NSUnderlineStyle.single.rawValue
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.beginEditing()
            storage.addAttribute(.strikethroughStyle, value: newVal, range: range)
            storage.endEditing()
            isStrikethrough = !has
            textView.didChangeText()
            notifyModelChange()
        }
    }

    /// Надстрочный (v0.1.77) — toggles baselineOffset+уменьшенный шрифт для выделения/typing.
    /// `mode` = `.super` для надстрочного, `.sub` для подстрочного.
    enum BaselineMode { case superscript, `subscript` }
    func toggleBaseline(_ mode: BaselineMode) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let isSuper = (mode == .superscript)

        func computeShift(fontSize: CGFloat) -> CGFloat {
            let base = fontSize / 0.7 // «логический» размер до уменьшения
            return isSuper ? base * 0.35 : -base * 0.2
        }

        if range.length == 0 {
            var attrs = textView.typingAttributes
            let curOffset = (attrs[.baselineOffset] as? CGFloat) ?? 0
            let already = isSuper ? (curOffset > 0.5) : (curOffset < -0.5)
            if already {
                attrs.removeValue(forKey: .baselineOffset)
                // Восстановить шрифт исходного размера (мы его уменьшали на 0.7).
                if let font = attrs[.font] as? NSFont {
                    attrs[.font] = NSFontManager.shared.convert(font, toSize: font.pointSize / 0.7)
                }
                isSuperscript = false; isSubscript = false
            } else {
                if let font = attrs[.font] as? NSFont {
                    let logical = curOffset != 0 ? font.pointSize : font.pointSize
                    attrs[.baselineOffset] = computeShift(fontSize: logical * 0.7)
                    attrs[.font] = NSFontManager.shared.convert(font, toSize: logical * 0.7)
                } else {
                    attrs[.baselineOffset] = isSuper ? 4 : -3
                }
                isSuperscript = isSuper; isSubscript = !isSuper
            }
            textView.typingAttributes = attrs
            return
        }

        let storage = textView.textStorage!
        let first = storage.attributes(at: range.location, effectiveRange: nil)
        let curOffset = (first[.baselineOffset] as? CGFloat) ?? 0
        let alreadyApplied = isSuper ? (curOffset > 0.5) : (curOffset < -0.5)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
            let font = (val as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            let curSubOff = (storage.attribute(.baselineOffset, at: subRange.location, effectiveRange: nil) as? CGFloat) ?? 0
            let isSmall = curSubOff != 0
            let logical = isSmall ? font.pointSize / 0.7 : font.pointSize
            if alreadyApplied {
                storage.removeAttribute(.baselineOffset, range: subRange)
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: logical), range: subRange)
            } else {
                let small = logical * 0.7
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: small), range: subRange)
                storage.addAttribute(.baselineOffset, value: (isSuper ? logical * 0.35 : -logical * 0.2), range: subRange)
            }
        }
        storage.endEditing()
        if alreadyApplied { isSuperscript = false; isSubscript = false }
        else { isSuperscript = isSuper; isSubscript = !isSuper }
        textView.didChangeText()
        notifyModelChange()
    }

    func toggleSuperscript() { toggleBaseline(.superscript) }
    func toggleSubscriptStyle() { toggleBaseline(.subscript) }

    // MARK: - Смена регистра (v0.1.78, R02)

    enum ChangeCaseMode { case upper, lower, title, sentence, toggleCase }

    /// Меняет регистр текста выделения (или текущего слова, если выделения нет).
    /// Сохраняет все атрибуты (шрифт/цвет/подчёркивание) — заменяет только видимые символы.
    /// Один атомарный `replaceCharacters` под shouldChangeText — один шаг undo.
    func applyChangeCase(_ mode: ChangeCaseMode) {
        guard let textView, let storage = textView.textStorage else { return }
        var range = textView.selectedRange()
        // Если выделения нет — берём текущее слово (границы = не-alphanumeric).
        if range.length == 0 {
            let ns = storage.string as NSString
            let alnum = CharacterSet.alphanumerics
            var start = range.location
            while start > 0 {
                let prev = ns.substring(with: NSRange(location: start - 1, length: 1))
                if prev.unicodeScalars.allSatisfy({ alnum.contains($0) }) { start -= 1 } else { break }
            }
            var end = range.location
            while end < ns.length {
                let cur = ns.substring(with: NSRange(location: end, length: 1))
                if cur.unicodeScalars.allSatisfy({ alnum.contains($0) }) { end += 1 } else { break }
            }
            range = NSRange(location: start, length: end - start)
            guard range.length > 0 else { return }
        }
        let original = storage.attributedSubstring(from: range)
        let converted = convertCase(original.string, mode: mode)
        guard converted != original.string else { return }
        // Копируем attributed с новыми символами и старыми атрибутами
        // (посимвольно, чтобы сохранить run-level форматирование).
        let m = NSMutableAttributedString(attributedString: original)
        m.replaceCharacters(in: NSRange(location: 0, length: m.length), with: converted)
        // Восстанавливаем атрибуты по границам original (m мог потерять при replaceCharacters).
        original.enumerateAttributes(in: NSRange(location: 0, length: original.length), options: []) { attrs, subRange, _ in
            // Границы могли сместиться при разной длине символов; здесь длина совпадает
            // (upper/lower не меняют count в Swift для латиницы/кириллицы, но для локали ß→SS может — редко).
            let clamped = NSRange(location: subRange.location, length: min(subRange.length, m.length - subRange.location))
            if clamped.length > 0 {
                m.setAttributes(attrs, range: clamped)
            }
        }
        guard textView.shouldChangeText(in: range, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: m)
        storage.endEditing()
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location, length: m.length))
        notifyModelChange()
        refreshSelectionState()
    }

    private func convertCase(_ s: String, mode: ChangeCaseMode) -> String {
        switch mode {
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .title:
            // Первая буква каждого «слова» — заглавная, остальные — строчные.
            return s.capitalized(with: Locale.current)
        case .sentence:
            // Первая буква + первые буквы после `.?!` — заглавные, остальные — строчные.
            let lower = s.lowercased()
            var result = ""
            var capitalizeNext = true
            for ch in lower {
                if ch.isLetter && capitalizeNext {
                    result.append(ch.uppercased())
                    capitalizeNext = false
                } else {
                    result.append(ch)
                    if ".!?".contains(ch) { capitalizeNext = true }
                }
            }
            return result
        case .toggleCase:
            var result = ""
            for ch in s {
                if ch.isUppercase { result.append(ch.lowercased()) }
                else if ch.isLowercase { result.append(ch.uppercased()) }
                else { result.append(ch) }
            }
            return result
        }
    }

    // MARK: - Формат по образцу (v0.1.79, R01)

    /// Захваченное форматирование (символьное) для «формата по образцу».
    /// Nil, если ничего не скопировано.
    @Published private(set) var hasCopiedFormatting: Bool = false
    private var copiedFormatting: [NSAttributedString.Key: Any]? = nil
    private var copiedParagraphStyle: NSParagraphStyle? = nil

    /// Ключи атрибутов, которые копирует «формат по образцу».
    /// Специально НЕ трогаем текст, ссылки, вложения — только визуальное форматирование.
    private static let formatKeys: [NSAttributedString.Key] = [
        .font, .foregroundColor, .backgroundColor,
        .underlineStyle, .underlineColor,
        .strikethroughStyle, .strikethroughColor,
        .baselineOffset, .kern, .ligature,
        .docxEditCharStyleId, .docxEditStyleId,
    ]

    /// Копирует форматирование текущей позиции (или первого символа выделения).
    func copyFormatting() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let source: [NSAttributedString.Key: Any]
        if range.length > 0 {
            source = storage.attributes(at: range.location, effectiveRange: nil)
        } else if storage.length > 0 {
            let loc = min(max(0, range.location - (range.location > 0 ? 1 : 0)), storage.length - 1)
            source = storage.attributes(at: loc, effectiveRange: nil)
        } else {
            source = textView.typingAttributes
        }
        var picked: [NSAttributedString.Key: Any] = [:]
        for key in Self.formatKeys {
            if let v = source[key] { picked[key] = v }
        }
        copiedFormatting = picked
        copiedParagraphStyle = source[.paragraphStyle] as? NSParagraphStyle
        hasCopiedFormatting = true
        statusText = "Формат скопирован"
    }

    /// Применяет скопированное форматирование к выделению
    /// (или к typingAttributes, если выделения нет).
    func pasteFormatting() {
        guard let textView, let storage = textView.textStorage,
              let attrs = copiedFormatting else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var ta = textView.typingAttributes
            for (k, v) in attrs { ta[k] = v }
            if let ps = copiedParagraphStyle { ta[.paragraphStyle] = ps }
            textView.typingAttributes = ta
            refreshSelectionState()
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        for (k, v) in attrs {
            storage.addAttribute(k, value: v, range: range)
        }
        if let ps = copiedParagraphStyle {
            // Применяем стиль абзаца ко всем затронутым абзацам целиком.
            let ns = storage.string as NSString
            let paraRange = ns.paragraphRange(for: range)
            storage.addAttribute(.paragraphStyle, value: ps, range: paraRange)
        }
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    func togglePageView() {
        // v1.4.1 (ADR-049): в MD-режиме вида страницы нет — не даём включить
        // (applyPageViewStyle тоже игнорирует isPageView при mode == .markdown).
        guard session?.mode != .markdown else { return }
        isPageView.toggle()
    }

    /// Заменяет параметры страницы текущего документа (v0.1.56). Вызывается
    /// при смене настроек в Preferences → Страница. Перерисовку макета
    /// (`applyPageViewStyle`) запускает Coordinator через toggling isPageView
    /// (тот же путь, что и обычное переключение вида).
    func setPageSettings(_ settings: PageSettings) {
        guard let session else { return }
        session.bridge.setPageSettings(settings)
        session.markDirty()
        // Кикаем перерасчёт раскладки страницы (ширина/поля/разрывы) — updateNSView
        // сам это делает при следующем цикле обновления благодаря @Published-полю
        // isPageView; чтобы гарантировать перерасчёт СЕЙЧАС, посылаем сигнал.
        NotificationCenter.default.post(name: .docxEditPageSettingsApplied, object: nil)
    }

    // MARK: - Колонтитулы

    func currentHeaderFooter() -> HeaderFooter { session?.bridge.headerFooter ?? .init() }

    // MARK: - Autorecover (v0.2.6, R04)

    private var autorecoverTimer: Timer?

    /// Директория с автосохранениями: ~/Library/Application Support/DocxEdit/autorecover
    static var autorecoverDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DocxEdit/autorecover", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Стартует таймер: каждые 30 секунд сохраняет копию открытого документа
    /// в директорию autorecover. Копия удаляется при явном сохранении пользователем.
    func startAutorecover(interval: TimeInterval = 30) {
        stopAutorecover()
        autorecoverTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Timer стреляет на главном runloop — но замыкание nonisolated,
            // поэтому явно утверждаем MainActor (Swift 6-ready).
            MainActor.assumeIsolated {
                self?.performAutorecoverSave()
            }
        }
    }

    func stopAutorecover() {
        autorecoverTimer?.invalidate()
        autorecoverTimer = nil
    }

    /// Помечает автосейв как ненужный (пользователь явно сохранил) — удаляет файл.
    func clearAutorecoverBackup() {
        guard let session else { return }
        let url = Self.autorecoverDirectory.appendingPathComponent(session.autorecoverFileName)
        try? FileManager.default.removeItem(at: url)
        // v1.6.5: MD source-копия (если была) — тоже.
        let mdURL = Self.autorecoverDirectory.appendingPathComponent(
            session.autorecoverFileName.replacingOccurrences(of: ".json", with: ".md"))
        try? FileManager.default.removeItem(at: mdURL)
    }

    private func performAutorecoverSave() {
        guard let session, session.isDirty else { return }
        let url = Self.autorecoverDirectory.appendingPathComponent(session.autorecoverFileName)
        do {
            let data = try JSONEncoder().encode(session.bridge.model)
            try data.write(to: url, options: .atomic)
        } catch {
            // Тихо: автосейв не должен ломать основной путь.
        }
        // v1.6.5: в MD source-режиме модель синкается best-effort — если
        // swift-markdown упал на недописанном синтаксисе, JSON-модель устарела.
        // Рядом пишем сырой текст: при восстановлении он приоритетнее.
        if session.isMarkdownSourceMode {
            let mdURL = Self.autorecoverDirectory.appendingPathComponent(
                session.autorecoverFileName.replacingOccurrences(of: ".json", with: ".md"))
            try? session.markdownSource.write(to: mdURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Закладки (v0.2.4, R04)

    /// Вставляет именованную закладку на текущее выделение (или на 0-длинный span у курсора).
    /// Проставляется custom-ключ `.docxEditBookmark`; DOCX round-trip через
    /// `<w:bookmarkStart w:name="…"/>` / `<w:bookmarkEnd/>`.
    func insertBookmark(name: String) {
        guard let tv = textView, let storage = tv.textStorage, !name.isEmpty else { return }
        var range = tv.selectedRange()
        if range.length == 0 {
            // 0-длина не поддерживает атрибуты в NSTextStorage — расширяем на 1 символ
            // вправо (или влево у конца документа).
            if range.location < storage.length { range.length = 1 }
            else if range.location > 0 { range.location -= 1; range.length = 1 }
            else { return }
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.docxEditBookmark, value: name, range: range)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
    }

    /// Возвращает список всех закладок в документе: (name, range).
    func listBookmarks() -> [(name: String, range: NSRange)] {
        guard let storage = textView?.textStorage else { return [] }
        var out: [(name: String, range: NSRange)] = []
        storage.enumerateAttribute(.docxEditBookmark,
                                    in: NSRange(location: 0, length: storage.length),
                                    options: []) { val, r, _ in
            if let name = val as? String { out.append((name, r)) }
        }
        return out
    }

    /// Переводит курсор на закладку с указанным именем.
    @discardableResult
    func goToBookmark(name: String) -> Bool {
        guard let tv = textView else { return false }
        for b in listBookmarks() where b.name == name {
            tv.setSelectedRange(b.range)
            tv.scrollRangeToVisible(b.range)
            return true
        }
        return false
    }

    /// Удаляет закладку по имени (снимает атрибут).
    func deleteBookmark(name: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let all = listBookmarks().filter { $0.name == name }
        guard !all.isEmpty else { return }
        let union = all.map(\.range).reduce(all[0].range) { NSUnionRange($0, $1) }
        guard tv.shouldChangeText(in: union, replacementString: nil) else { return }
        storage.beginEditing()
        for b in all {
            storage.removeAttribute(.docxEditBookmark, range: b.range)
        }
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
    }

    /// v0.2.1 (R04): обновляет метаданные документа. DOCX round-trip через
    /// docProps/core.xml (dc:title/dc:creator/dc:subject/cp:keywords/dc:language).
    func updateMetadata(title: String, author: String, subject: String,
                        keywords: [String], language: String) {
        guard let session else { return }
        session.bridge.setMetadata(title: title, author: author, subject: subject,
                                   keywords: keywords, language: language)
        session.markDirty()
    }

    func setHeaderFooter(_ hf: HeaderFooter) {
        guard let session else { return }
        session.bridge.setHeaderFooter(hf)
        session.markDirty()
        if let dt = textView as? DocxTextView {
            dt.headerText = hf.headerText
            dt.footerText = hf.footerText
            dt.headerAlign = hf.headerAlignment.nsAlignment
            dt.footerAlign = hf.footerAlignment.nsAlignment
            dt.needsDisplay = true
        }
    }

    /// Быстрое включение/выключение номера страницы (в нижнем колонтитуле по центру).
    func togglePageNumbers() {
        var hf = currentHeaderFooter()
        if hf.footerText.contains("{page}") {
            hf.footerText = ""
        } else {
            hf.footerText = "{page}"
            hf.footerAlignment = .center
        }
        setHeaderFooter(hf)
    }

    // MARK: - Замена шрифтов

    /// Уникальные семейства шрифтов, использующиеся в документе, с флагом отсутствия в системе.
    func fontsUsedInDocument() -> [FontUsage] {
        guard let storage = textView?.textStorage else { return [] }
        var names = Set<String>()
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length), options: []) { val, _, _ in
            if let f = val as? NSFont { names.insert(f.familyName ?? f.fontName) }
        }
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return names.sorted().map { FontUsage(id: $0, isMissing: !installed.contains($0)) }
    }

    /// Заменяет все вхождения шрифта `from` на `to` по всему документу
    /// (сохраняя размер/начертание/цвет/подчёркивание каждого рана).
    func replaceFont(from: String, to: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard textView.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: full, options: []) { val, subRange, _ in
            guard let font = val as? NSFont, (font.familyName ?? font.fontName) == from else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toFamily: to), range: subRange)
        }
        storage.endEditing()
        textView.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    // MARK: - Приватные

    /// Читает B/I-трейты текущего выделения/курсора. Чистая функция — не мутирует состояние.
    private func selectionBoldItalicTraits() -> NSFontDescriptor.SymbolicTraits {
        guard let textView else { return [] }
        let range = textView.selectedRange()
        let existing = (range.length > 0
            ? textView.textStorage?.attributes(at: range.location, effectiveRange: nil)
            : textView.typingAttributes) ?? [:]
        guard let existingFont = existing[.font] as? NSFont else { return [] }
        return existingFont.fontDescriptor.symbolicTraits.intersection([.bold, .italic])
    }

    private func currentFont() -> NSFont {
        let baseSize = fontSize
        var font = NSFont(name: fontName, size: baseSize) ?? NSFont.systemFont(ofSize: baseSize)
        var traits = font.fontDescriptor.symbolicTraits
        if isBold { traits.insert(.bold) }
        if isItalic { traits.insert(.italic) }
        // Сохраняем текущие traits B/I из выделения/курсора, чтобы при смене
        // шрифта внутри выделения B/I не сбрасывались.
        traits.formUnion(selectionBoldItalicTraits())
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) as NSFontDescriptor? {
            font = NSFont(descriptor: descriptor, size: baseSize) ?? font
        }
        return font
    }

    private func updateTypingAttributes(font: NSFont) {
        guard let textView else { return }
        var attrs = textView.typingAttributes
        attrs[.font] = font
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = NSColor.labelColor
        }
        textView.typingAttributes = attrs
    }

    /// Меняет семейство шрифта в диапазоне, сохраняя размер и начертание каждого под-рана —
    /// конвертирует каждый существующий NSFont по отдельности вместо замены на один общий.
    private func applyFontFamily(_ name: String, range: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let old = (value as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(old, toFamily: name), range: subRange)
        }
        storage.endEditing()
    }

    /// Меняет размер шрифта в диапазоне, сохраняя семейство и начертание каждого под-рана.
    private func applyPointSize(_ points: CGFloat, range: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let old = (value as? NSFont) ?? NSFont.systemFont(ofSize: points)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(old, toSize: points), range: subRange)
        }
        storage.endEditing()
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            // Без выделения — обновляем typingAttributes.
            let current = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
            let newFont = toggle(trait: trait, on: current)
            var attrs = textView.typingAttributes
            attrs[.font] = newFont
            textView.typingAttributes = attrs
            // Обновляем UI-флаги.
            let traits = newFont.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
        } else {
            // С выделением — определяем, какие символы имеют trait, и для всех делаем toggle.
            // Если все символы имеют trait — выключаем; иначе — включаем.
            var allHave = true
            textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    let hasTrait = font.fontDescriptor.symbolicTraits.contains(symbolicTraitFromMask(trait))
                    if !hasTrait { allHave = false }
                }
            }
            let shouldEnable = !allHave
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                let newFont = set(trait: trait, on: font, enabled: shouldEnable)
                var existing = textView.textStorage!.attributes(at: subRange.location, effectiveRange: nil)
                existing[.font] = newFont
                textView.textStorage?.setAttributes(existing, range: subRange)
            }
            textView.textStorage?.endEditing()
            // Обновляем только флаг изменённого trait, остальные не трогаем.
            if trait == .boldFontMask { isBold = shouldEnable }
            if trait == .italicFontMask { isItalic = shouldEnable }
            textView.didChangeText()
            notifyModelChange()
        }
    }

    private func symbolicTraitFromMask(_ mask: NSFontTraitMask) -> NSFontDescriptor.SymbolicTraits {
        switch mask {
        case .boldFontMask: return .bold
        case .italicFontMask: return .italic
        case .condensedFontMask: return .condensed
        case .expandedFontMask: return .expanded
        default: return []
        }
    }

    private func toggle(trait: NSFontTraitMask, on font: NSFont) -> NSFont {
        let symTrait = symbolicTraitFromMask(trait)
        var current = font.fontDescriptor.symbolicTraits
        if current.contains(symTrait) {
            current.remove(symTrait)
        } else {
            current.insert(symTrait)
        }
        if let desc = font.fontDescriptor.withSymbolicTraits(current) as NSFontDescriptor? {
            return NSFont(descriptor: desc, size: font.pointSize) ?? font
        }
        return font
    }

    private func set(trait: NSFontTraitMask, on font: NSFont, enabled: Bool) -> NSFont {
        let symTrait = symbolicTraitFromMask(trait)
        var current = font.fontDescriptor.symbolicTraits
        if enabled { current.insert(symTrait) } else { current.remove(symTrait) }
        if let desc = font.fontDescriptor.withSymbolicTraits(current) as NSFontDescriptor? {
            return NSFont(descriptor: desc, size: font.pointSize) ?? font
        }
        return font
    }

    func notifyModelChange() {
        guard let textView, let session else { return }
        session.applyAttributed(textView.attributedString())
        }

    // MARK: - Stored properties, перенесённые из extension-файлов (v1.6.5)

    /// Индекс текущего выделения среди всех совпадений (для «3 из 17»).
    /// nil — выделение не совпадает ни с одним вхождением.
    @Published var findCurrentIndex: Int? = nil
    /// Активна ли подсветка всех вхождений.
    @Published var findHighlightsActive: Bool = false
    /// Последний использованный pattern — сохраняется в findNext/replaceCurrent/replaceAll,
    /// чтобы expandReplacement имел доступ к нему (без прокидывания через каждый уровень).
    var currentPattern: String = ""
    var lastTocHeadingsSnapshot: String = ""
    var isRefreshingToc = false
    let zoomSteps: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
}
