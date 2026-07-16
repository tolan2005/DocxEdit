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
    private var lastAppliedSpellLanguage: String?
    @Published var showsRuler: Bool = false
    @Published var showsStylesSidebar: Bool = false
    /// v0.4.4 (R06): показывать боковую панель комментариев справа.
    @Published var showsCommentsSidebar: Bool = false
    /// v0.5.4 (R07): показывать боковую панель сносок справа.
    @Published var showsFootnotesSidebar: Bool = false

    func toggleCommentsSidebar() { showsCommentsSidebar.toggle() }
    func toggleFootnotesSidebar() { showsFootnotesSidebar.toggle() }
    /// v0.4.3 (R06): режим «Чтение» — только view-состояние (`isEditable=false`
    /// + скрытие ribbon, увеличенные поля через zoom). Модели не касается.
    @Published var isReadingMode: Bool = false

    func toggleRuler() {
        showsRuler.toggle()
        textView?.enclosingScrollView?.rulersVisible = showsRuler
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
    private var lastVariant: [ListType: MultilevelListVariant] = [:]

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
    private func detectVariant(for info: ListInfo) -> MultilevelListVariant {
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
                let stack = counters.next(level: info.level, format: info.formatStyle)
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
                let stack = counters.next(level: info.level, format: info.formatStyle)
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
    private func selectedParagraphRanges() -> [NSRange] {
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

    func togglePageView() { isPageView.toggle() }

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

    /// Последний использованный pattern — сохраняется в findNext/replaceCurrent/replaceAll,
    /// чтобы expandReplacement имел доступ к нему (без прокидывания через каждый уровень).
    private var currentPattern: String = ""

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

    // MARK: - Операции строк/столбцов таблицы (v0.1.50)

    /// Операции над таблицей, применяемые к таблице в позиции курсора.
    enum TableEdit {
        case addRowAbove, addRowBelow
        case addColumnLeft, addColumnRight
        case deleteRow, deleteColumn, deleteTable
        /// Объединить выделенные ячейки одной строки в одну (colSpan = сумма).
        /// Горизонтальный merge из линейного выделения NSTextView.
        case mergeCells
        /// Объединить прямоугольник ячеек по явным grid-координатам (из диалога-сетки,
        /// v0.1.65). Не зависит от линейного выделения NSTextView — единственный
        /// надёжный способ вертикального/прямоугольного merge.
        case mergeRect(minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)
        /// Разделить текущую ячейку (colSpan>1 → 1x1 + вставка пустых справа).
        case splitCell
        /// v0.1.85: пометить текущую строку как строку-заголовок таблицы (toggle).
        /// В DOCX — `<w:tblHeader/>`; повторяется на каждой странице при печати.
        case toggleHeaderRow
        /// v0.1.86: задать минимальную высоту текущей строки (pt). `nil` — сброс к авто.
        case setRowHeight(CGFloat?)
    }

    /// v0.1.89: фактическая визуальная высота текущей строки таблицы (pt), считывается
    /// из NSLayoutManager. Обходит все абзацы текущей строки (по совпадению startingRow
    /// у cellBlock) и берёт union bounding rect — включает высоту, добавленную ручным
    /// увеличением содержимого. Nil, если курсор не в таблице.
    func currentRowVisualHeight() -> CGFloat? {
        guard let tv = textView, let storage = tv.textStorage,
              let lm = tv.layoutManager, let tc = tv.textContainer,
              storage.length > 0 else { return nil }
        guard let span = tableSpanAtCaret() else { return nil }
        let full = NSRange(location: 0, length: storage.length)
        let ns = storage.string as NSString
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        var loc = span.range.location
        let end = min(NSMaxRange(span.range), storage.length)
        while loc < end {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let probe = min(pr.location, storage.length - 1)
            if let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
               let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
               cb.table === span.nsTable, cb.startingRow == span.caretRow {
                let gr = lm.glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
                if gr.length > 0 {
                    let rect = lm.boundingRect(forGlyphRange: gr, in: tc)
                    minY = min(minY, rect.minY)
                    maxY = max(maxY, rect.maxY)
                }
            }
            loc = pr.length > 0 ? NSMaxRange(pr) : loc + 1
            _ = full
        }
        return (maxY > minY) ? (maxY - minY) : nil
    }

    /// Диапазон таблицы в storage вокруг позиции курсора + текущие координаты ячейки.
    /// Возвращает nil, если курсор не в таблице.
    private struct TableSpan {
        let range: NSRange
        let nsTable: NSTextTable
        let caretRow: Int
        let caretCol: Int
    }

    private func tableSpanAtCaret() -> TableSpan? {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return nil }
        let raw = tv.selectedRange().location
        let probe = min(max(0, raw), storage.length - 1)
        guard let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
              let caretBlock = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first else {
            return nil
        }
        let table = caretBlock.table
        let ns = storage.string as NSString

        // Идём назад по абзацам, пока встречаем ту же NSTextTable.
        var startLoc = ns.paragraphRange(for: NSRange(location: probe, length: 0)).location
        while startLoc > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: startLoc - 1, length: 0))
            guard let pps = storage.attribute(.paragraphStyle, at: prev.location, effectiveRange: nil) as? NSParagraphStyle,
                  let pcb = pps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                  pcb.table === table else { break }
            startLoc = prev.location
        }
        // Вперёд.
        var endLoc = NSMaxRange(ns.paragraphRange(for: NSRange(location: probe, length: 0)))
        while endLoc < storage.length {
            let next = ns.paragraphRange(for: NSRange(location: endLoc, length: 0))
            guard next.length > 0,
                  let nps = storage.attribute(.paragraphStyle, at: next.location, effectiveRange: nil) as? NSParagraphStyle,
                  let ncb = nps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                  ncb.table === table else { break }
            endLoc = NSMaxRange(next)
        }
        return TableSpan(range: NSRange(location: startLoc, length: endLoc - startLoc),
                         nsTable: table,
                         caretRow: caretBlock.startingRow,
                         caretCol: caretBlock.startingColumn)
    }

    /// Применяет операцию к таблице в позиции курсора (add/delete row/col/table).
    /// Извлекает модель таблицы через `DocumentModel.from(attributed:)` на subAttr
    /// текущего span, мутирует, перерендеривает через `appendTable` и заменяет
    /// весь span одним атомарным `replaceCharacters` под `shouldChangeText` —
    /// один шаг undo (паттерн ADR-027).
    func applyTableEdit(_ edit: TableEdit) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard let span = tableSpanAtCaret() else { return }

        // deleteTable — упрощённый путь без извлечения/перерендера.
        if case .deleteTable = edit {
            let attrs = tv.typingAttributes
            let empty = NSAttributedString(string: "", attributes: attrs)
            guard tv.shouldChangeText(in: span.range, replacementString: "") else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: span.range, with: empty)
            storage.endEditing()
            tv.didChangeText()
            let caretLoc = min(span.range.location, storage.length)
            tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
            notifyModelChange()
            refreshSelectionState()
            return
        }

        // Извлекаем модель таблицы из subAttr — reverse-bridge даёт TableBlock.
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var table: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { table = t; break }
        }
        guard var newTable = table else { return }

        let r = span.caretRow
        let c = span.caretCol

        func emptyCell() -> TableCell {
            TableCell(blocks: [.paragraph(Paragraph(
                runs: [Run(text: "", attributes: CharacterAttributes())],
                attributes: ParagraphAttributes()))])
        }

        // (targetRow, targetCol) — куда перевести курсор после перерендера.
        // Add-ops сохраняют позицию исходной ячейки (со сдвигом, если новая
        // строка/столбец добавлены до неё). Delete-ops оставляют курсор в той
        // же строке/столбце (clamp к последнему индексу, если удалили последний).
        var targetRow = r
        var targetCol = c

        switch edit {
        case .addRowAbove:
            let cols = newTable.rows.first?.cells.count ?? 1
            let row = DocxCore.TableRow(cells: (0..<cols).map { _ in emptyCell() })
            newTable.rows.insert(row, at: max(0, min(r, newTable.rows.count)))
            targetRow = r + 1
        case .addRowBelow:
            let cols = newTable.rows.first?.cells.count ?? 1
            let row = DocxCore.TableRow(cells: (0..<cols).map { _ in emptyCell() })
            newTable.rows.insert(row, at: max(0, min(r + 1, newTable.rows.count)))
            targetRow = r
        case .addColumnLeft:
            for i in newTable.rows.indices {
                let idx = max(0, min(c, newTable.rows[i].cells.count))
                newTable.rows[i].cells.insert(emptyCell(), at: idx)
            }
            targetCol = c + 1
        case .addColumnRight:
            for i in newTable.rows.indices {
                let idx = max(0, min(c + 1, newTable.rows[i].cells.count))
                newTable.rows[i].cells.insert(emptyCell(), at: idx)
            }
            targetCol = c
        case .deleteRow:
            guard newTable.rows.count > 1 else {
                applyTableEdit(.deleteTable); return
            }
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows.remove(at: r)
            targetRow = min(r, newTable.rows.count - 1)
        case .deleteColumn:
            guard (newTable.rows.first?.cells.count ?? 0) > 1 else {
                applyTableEdit(.deleteTable); return
            }
            for i in newTable.rows.indices {
                if c >= 0, c < newTable.rows[i].cells.count {
                    newTable.rows[i].cells.remove(at: c)
                }
            }
            targetCol = min(c, (newTable.rows.first?.cells.count ?? 1) - 1)
        case .toggleHeaderRow:
            // v0.1.85: пометить текущую строку как заголовок таблицы (или снять).
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows[r].isHeader.toggle()
            targetRow = r
        case .setRowHeight(let value):
            // v0.1.86: минимальная высота текущей строки. Nil = сброс.
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows[r].height = (value.map { max(0, $0) }).flatMap { $0 > 0 ? $0 : nil }
            targetRow = r
        case .deleteTable:
            return // покрыто выше
        case .mergeCells:
            // Горизонтальный merge из линейного выделения NSTextView. Берём границы
            // от ПЕРВОЙ и ПОСЛЕДНЕЙ ячейки выделения. Вертикальный/прямоугольный
            // merge через выделение невозможен (NSTextView не умеет прямоугольное
            // выделение) — для него есть диалог-сетка → .mergeRect (v0.1.65).
            let sel = tv.selectedRange()
            let ns = storage.string as NSString
            var firstCoord: (row: Int, col: Int, span: Int)? = nil
            var lastCoord: (row: Int, col: Int, span: Int)? = nil
            var loc = sel.location
            let end = NSMaxRange(sel)
            while loc <= end {
                let pr = ns.paragraphRange(for: NSRange(location: min(loc, storage.length - 1), length: 0))
                if let ps = storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle,
                   let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                   cb.table === span.nsTable {
                    let coord = (cb.startingRow, cb.startingColumn, cb.columnSpan)
                    if firstCoord == nil { firstCoord = coord }
                    lastCoord = coord
                }
                if pr.length == 0 { break }
                loc = NSMaxRange(pr)
                if loc == end && pr.location + pr.length == end { break }
            }
            guard let a = firstCoord, let b = lastCoord else { NSSound.beep(); return }
            let minRow = min(a.row, b.row)
            let maxRow = max(a.row, b.row)
            let minCol = min(a.col, b.col)
            let maxCol = max(a.col + a.span - 1, b.col + b.span - 1)
            guard mergeRectInto(&newTable, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol) else {
                NSSound.beep(); return
            }
            targetRow = minRow
            targetCol = minCol
        case let .mergeRect(minRow, maxRow, minCol, maxCol):
            guard mergeRectInto(&newTable, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol) else {
                NSSound.beep(); return
            }
            targetRow = minRow
            targetCol = minCol
        case .splitCell:
            // Возвращаем текущую ячейку в 1x1 + восстанавливаем удалённые ячейки в rows ниже
            // (для rowSpan>1) и справа (для colSpan>1).
            guard r < newTable.rows.count else { return }
            var idxByCol: [Int: Int] = [:]
            var cur = 0
            for (i, cell) in newTable.rows[r].cells.enumerated() {
                for gc in cur..<(cur + max(1, cell.colSpan)) { idxByCol[gc] = i }
                cur += max(1, cell.colSpan)
            }
            guard let cellIdx = idxByCol[c] else { return }
            let currentColSpan = max(1, newTable.rows[r].cells[cellIdx].colSpan)
            let currentRowSpan = max(1, newTable.rows[r].cells[cellIdx].rowSpan)
            guard currentColSpan > 1 || currentRowSpan > 1 else { NSSound.beep(); return }

            let cellStartCol = c
            let cellEndCol = c + currentColSpan - 1
            // Горизонтальный split: у самой ячейки colSpan=1, вставляем справа.
            newTable.rows[r].cells[cellIdx].colSpan = 1
            newTable.rows[r].cells[cellIdx].rowSpan = 1
            for _ in 0..<(currentColSpan - 1) {
                newTable.rows[r].cells.insert(emptyCell(), at: cellIdx + 1)
            }
            // Вертикальный split: в каждой row в диапазоне (r+1 .. r+currentRowSpan-1)
            // вставляем currentColSpan пустых ячеек в позицию с grid-col = cellStartCol.
            if currentRowSpan > 1 {
                for row in (r + 1)...(r + currentRowSpan - 1) where row < newTable.rows.count {
                    // Ищем индекс в row.cells, куда вставлять — первая ячейка с grid-col >= cellStartCol.
                    var insertIdx = newTable.rows[row].cells.count
                    var gridCol = 0
                    for (i, cell) in newTable.rows[row].cells.enumerated() {
                        if gridCol >= cellStartCol { insertIdx = i; break }
                        gridCol += max(1, cell.colSpan)
                    }
                    for _ in cellStartCol...cellEndCol {
                        newTable.rows[row].cells.insert(emptyCell(), at: insertIdx)
                    }
                }
            }
            targetRow = r
            targetCol = c
        }

        // Перерендер — appendTable даёт эквивалентный shape (без хвостового абзаца).
        let payload = NSMutableAttributedString()
        let typingAttrs = tv.typingAttributes
        let defaultFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        appendTable(newTable, to: payload, defaultFont: defaultFont,
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: pageUsableWidth)

        guard tv.shouldChangeText(in: span.range, replacementString: payload.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: span.range, with: payload)
        storage.endEditing()
        tv.didChangeText()
        // Курсор — в целевую ячейку (targetRow, targetCol), а не в top-left.
        let caretLoc = locationOfCell(row: targetRow, col: targetCol,
                                       tableStart: span.range.location,
                                       storage: storage) ?? span.range.location
        tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Объединяет прямоугольник ячеек [minRow…maxRow]×[minCol…maxCol] (в grid-
    /// координатах) внутри `table`. Возвращает false, если прямоугольник вырожден
    /// (одна ячейка) или выходит за границы — тогда вызывающий делает beep.
    /// Общий код для `.mergeCells` (выделение) и `.mergeRect` (диалог-сетка).
    private func mergeRectInto(_ table: inout TableBlock,
                               minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) -> Bool {
        guard minRow >= 0, minCol >= 0, maxRow >= minRow, maxCol >= minCol else { return false }
        guard maxRow > minRow || maxCol > minCol else { return false }
        guard maxRow < table.rows.count else { return false }

        func emptyCell() -> TableCell {
            TableCell(blocks: [.paragraph(Paragraph(
                runs: [Run(text: "", attributes: CharacterAttributes())],
                attributes: ParagraphAttributes()))])
        }

        // Собираем непустое содержимое всех ячеек прямоугольника + удаляем покрытые.
        var mergedBlocks: [Block] = []
        for row in minRow...maxRow {
            var idxByCol: [Int: Int] = [:]
            var cur = 0
            for (i, cell) in table.rows[row].cells.enumerated() {
                for gc in cur..<(cur + max(1, cell.colSpan)) { idxByCol[gc] = i }
                cur += max(1, cell.colSpan)
            }
            var cellIndices = Set<Int>()
            for gc in minCol...maxCol {
                if let idx = idxByCol[gc] { cellIndices.insert(idx) }
            }
            for idx in cellIndices.sorted() {
                for block in table.rows[row].cells[idx].blocks {
                    if case .paragraph(let p) = block,
                       !(p.runs.isEmpty || p.runs.allSatisfy { $0.text.isEmpty }) {
                        mergedBlocks.append(block)
                    }
                }
            }
            let toRemove: [Int]
            if row == minRow, let keepIdx = idxByCol[minCol] {
                toRemove = cellIndices.subtracting([keepIdx]).sorted()
            } else {
                toRemove = cellIndices.sorted()
            }
            for i in toRemove.reversed() {
                table.rows[row].cells.remove(at: i)
            }
        }
        // Находим target (grid-col == minCol) в первой строке после удалений.
        var targetIdx: Int? = nil
        var cur = 0
        for (i, cell) in table.rows[minRow].cells.enumerated() {
            if cur == minCol { targetIdx = i; break }
            cur += max(1, cell.colSpan)
        }
        guard let ti = targetIdx else { return false }
        table.rows[minRow].cells[ti].colSpan = maxCol - minCol + 1
        table.rows[minRow].cells[ti].rowSpan = maxRow - minRow + 1
        if !mergedBlocks.isEmpty {
            table.rows[minRow].cells[ti].blocks = mergedBlocks
        }
        return true
    }

    /// Размер сетки таблицы под курсором + позиция ячейки-курсора (в grid-координатах).
    /// Для диалога объединения ячеек (v0.1.65). Nil, если курсор не в таблице.
    func tableGridInfo() -> (rows: Int, cols: Int, caretRow: Int, caretCol: Int)? {
        guard let span = tableSpanAtCaret(), let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var table: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { table = t; break }
        }
        guard let t = table, !t.rows.isEmpty else { return nil }
        let rows = t.rows.count
        let cols = t.rows.map { row in row.cells.reduce(0) { $0 + max(1, $1.colSpan) } }.max() ?? 1
        let cr = min(max(0, span.caretRow), rows - 1)
        let cc = min(max(0, span.caretCol), cols - 1)
        return (rows, cols, cr, cc)
    }

    /// Полезная ширина страницы (ширина - левое+правое поле) в points.
    /// Используется для позиционирования таблиц (v0.1.73).
    private var pageUsableWidth: CGFloat {
        session?.bridge.model.pageSettings.usableWidthInPoints ?? PageSettings.a4Portrait.usableWidthInPoints
    }

    // MARK: - Стиль таблицы (v0.1.51)

    /// Возвращает текущий стиль таблицы под курсором + позицию ячейки (row, col).
    /// Nil, если курсор не в таблице.
    func currentTableInfo() -> (style: DocxCore.TableStyle, cellBackground: CodableColor?, columnWidth: CGFloat?, row: Int, col: Int)? {
        guard let span = tableSpanAtCaret(),
              let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block {
                let r = min(max(0, span.caretRow), t.rows.count - 1)
                let c = min(max(0, span.caretCol), (t.rows.first?.cells.count ?? 1) - 1)
                let cell = t.rows[r].cells[c]
                return (t.style, cell.backgroundColor, cell.width, r, c)
            }
        }
        return nil
    }

    /// Универсальная мутация таблицы под курсором — извлекает модель, вызывает
    /// `transform(inout TableBlock, row, col)`, перерендеривает через `appendTable`,
    /// заменяет span одним атомарным `replaceCharacters` (один шаг undo). Курсор
    /// возвращается в ту же ячейку (row, col).
    func mutateCurrentTable(_ transform: (inout TableBlock, Int, Int) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard let span = tableSpanAtCaret() else { return }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var newTable: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { newTable = t; break }
        }
        guard var t = newTable else { return }
        transform(&t, span.caretRow, span.caretCol)

        let payload = NSMutableAttributedString()
        let typingAttrs = tv.typingAttributes
        let defaultFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        appendTable(t, to: payload, defaultFont: defaultFont,
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: pageUsableWidth)

        guard tv.shouldChangeText(in: span.range, replacementString: payload.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: span.range, with: payload)
        storage.endEditing()
        tv.didChangeText()
        let caretLoc = locationOfCell(row: span.caretRow, col: span.caretCol,
                                       tableStart: span.range.location, storage: storage) ?? span.range.location
        tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Меняет границы всей таблицы: показывать/цвет/толщина.
    func setTableBorders(hasBorders: Bool, color: NSColor?, width: CGFloat) {
        mutateCurrentTable { t, _, _ in
            t.style.hasBorders = hasBorders
            if let c = color {
                let cc = c.usingColorSpace(.sRGB) ?? c
                t.style.borderColor = CodableColor(red: cc.redComponent, green: cc.greenComponent,
                                                    blue: cc.blueComponent, alpha: cc.alphaComponent)
            } else {
                t.style.borderColor = nil
            }
            t.style.borderWidth = max(0, width)
        }
    }

    /// Заливка текущей ячейки (nil — убрать).
    func setCellBackground(_ color: NSColor?) {
        mutateCurrentTable { t, r, c in
            guard r < t.rows.count, c < t.rows[r].cells.count else { return }
            if let color {
                let cc = color.usingColorSpace(.sRGB) ?? color
                t.rows[r].cells[c].backgroundColor = CodableColor(
                    red: cc.redComponent, green: cc.greenComponent,
                    blue: cc.blueComponent, alpha: cc.alphaComponent)
            } else {
                t.rows[r].cells[c].backgroundColor = nil
            }
        }
    }

    /// Горизонтальное выравнивание таблицы на странице (v0.1.70).
    /// В DOCX — `<w:jc>` в `<w:tblPr>`. С v0.1.92 и визуально в редакторе:
    /// appendTable задаёт contentWidth + левый margin NSTextTable, когда
    /// суммарная ширина колонок известна и меньше usable-ширины страницы.
    func setTableAlignment(_ alignment: DocxCore.TableAlignment) {
        mutateCurrentTable { t, _, _ in
            t.alignment = alignment
        }
    }

    /// Текущее выравнивание таблицы под курсором (для prefill диалога).
    func currentTableAlignment() -> DocxCore.TableAlignment? {
        guard let span = tableSpanAtCaret(),
              let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { return t.alignment }
        }
        return nil
    }

    /// Ширина текущей колонки в points (устанавливается на КАЖДУЮ ячейку колонки).
    /// nil — авто-ширина.
    func setColumnWidth(_ width: CGFloat?) {
        mutateCurrentTable { t, _, c in
            for i in t.rows.indices {
                guard c < t.rows[i].cells.count else { continue }
                t.rows[i].cells[c].width = width
            }
        }
    }

    /// Ищет первый абзац с `NSTextTableBlock.startingRow == row` и `startingColumn == col`
    /// начиная с `tableStart`. Возвращает storage-позицию начала этого абзаца или nil,
    /// если не нашёл (например, targetRow/Col выходят за границы новой таблицы).
    private func locationOfCell(row: Int, col: Int, tableStart: Int, storage: NSTextStorage) -> Int? {
        let ns = storage.string as NSString
        var loc = tableStart
        while loc < storage.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            guard let ps = storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle,
                  let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first else { return nil }
            if cb.startingRow == row && cb.startingColumn == col { return para.location }
            loc = NSMaxRange(para)
        }
        return nil
    }

    // MARK: - Вставка изображения (v0.1.52, R03)

    /// Показывает NSOpenPanel для выбора изображения (PNG/JPEG/GIF/TIFF) и вставляет
    /// его в позицию курсора как inline-attachment. Размер отображения — clamp по
    /// доступной ширине контейнера (`textContainer.containerSize.width`), с сохранением
    /// пропорций.
    func insertImageInteractive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.png, .jpeg, .gif, .tiff, .heic]
        if let svg = UTType("public.svg-image") { types.append(svg) }
        panel.allowedContentTypes = types
        panel.title = "Вставить изображение"
        panel.prompt = "Вставить"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        insertImage(from: url)
    }

    /// Читает файл изображения по URL, создаёт `InlineImage` и вставляет через
    /// `NSTextAttachment` одним атомарным `replaceCharacters` под `shouldChangeText`
    /// (один шаг undo, паттерн ADR-027).
    func insertImage(from url: URL) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard var data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        // Модель/DOCX хранят только PNG/JPEG/GIF/TIFF (форматы, поддерживаемые OOXML).
        // HEIC/SVG (v0.1.97) — конвертируем в PNG на этапе импорта: NSImage читает
        // оба формата нативно (macOS 14+), рендерим через NSBitmapImageRep→PNG.
        // SVG рендерится в растр — векторное качество теряется (для DOCX неизбежно
        // всё равно, т.к. встраивание SVG в OOXML стало распространено недавно).
        var format: InlineImageFormat
        switch ext {
        case "png": format = .png
        case "jpg", "jpeg": format = .jpeg
        case "gif": format = .gif
        case "tif", "tiff": format = .tiff
        case "heic", "heif", "svg":
            guard let src = NSImage(data: data),
                  let tiff = src.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            data = png
            format = .png
        default: format = .png
        }
        guard let ns = NSImage(data: data) else { return }
        // Ужимаем ширину до доступной, если картинка шире.
        let containerW: CGFloat = {
            if let c = tv.textContainer, c.containerSize.width > 0, c.containerSize.width < .infinity {
                return c.containerSize.width - 8 // с зазором
            }
            return 400
        }()
        var displayW = ns.size.width
        var displayH = ns.size.height
        if displayW > containerW, displayW > 0 {
            let scale = containerW / displayW
            displayW = containerW
            displayH *= scale
        }
        let img = InlineImage(format: format, data: data,
                              displayWidth: displayW, displayHeight: displayH)
        let att = makeImageAttachment(from: img)
        let attStr = NSAttributedString(attachment: att)
        let m = NSMutableAttributedString(attributedString: attStr)
        // Наследуем параграф-стиль и шрифт от позиции курсора.
        let sel = tv.selectedRange()
        var attrs = tv.typingAttributes
        if sel.location > 0, sel.location <= storage.length {
            let src = min(sel.location - 1, storage.length - 1)
            if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
        }
        // Уберём старый .attachment из наследуемых атрибутов (он бы приклеился
        // как отдельный ключ, ломая рендер новой картинки).
        attrs.removeValue(forKey: .attachment)
        m.addAttributes(attrs, range: NSRange(location: 0, length: m.length))

        guard tv.shouldChangeText(in: sel, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    // MARK: - Гиперссылки (v0.1.54, R03)

    /// URL гиперссылки в позиции курсора (или в начале выделения). nil, если
    /// на этой позиции ссылки нет. Используется для prefill диалога ⌘K.
    func hyperlinkAtCaret() -> String? {
        guard let tv = textView, let storage = tv.textStorage else { return nil }
        let sel = tv.selectedRange()
        let idx = min(sel.location, storage.length - 1)
        guard idx >= 0, storage.length > 0 else { return nil }
        if let s = storage.attribute(.link, at: idx, effectiveRange: nil) as? String { return s }
        if let u = storage.attribute(.link, at: idx, effectiveRange: nil) as? URL { return u.absoluteString }
        return nil
    }

    /// Текст выделения (пусто = нет выделения). Для prefill поля «Текст» в диалоге.
    func selectedText() -> String {
        guard let tv = textView, let storage = tv.textStorage else { return "" }
        let sel = tv.selectedRange()
        guard sel.length > 0, NSMaxRange(sel) <= storage.length else { return "" }
        return (storage.string as NSString).substring(with: sel)
    }

    /// Вставляет/применяет гиперссылку. Если выделение не пустое — применяет
    /// URL к нему (текст выделения не заменяется, даже если `text` отличается —
    /// сохраняем исходное форматирование). Если выделения нет — вставляет `text`
    /// с гиперссылкой. Один атомарный `replaceCharacters` под shouldChangeText —
    /// один шаг undo (паттерн ADR-027).
    func insertHyperlink(text: String, url: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }

        if sel.length > 0 {
            // Применить к выделению: перезаписываем содержимое теми же символами
            // + атрибут .link, чтобы получить один связный undo (см. ADR-027).
            let existing = storage.attributedSubstring(from: sel)
            let m = NSMutableAttributedString(attributedString: existing)
            m.addAttribute(.link, value: cleanURL, range: NSRange(location: 0, length: m.length))
            guard tv.shouldChangeText(in: sel, replacementString: m.string) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: sel, with: m)
            storage.endEditing()
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + m.length, length: 0))
        } else {
            // Вставить новый текст с ссылкой; атрибуты — из позиции курсора.
            let insertText = text.isEmpty ? cleanURL : text
            var attrs = tv.typingAttributes
            if sel.location > 0, sel.location <= storage.length {
                let src = min(sel.location - 1, storage.length - 1)
                if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
            }
            attrs[.link] = cleanURL
            let attributed = NSAttributedString(string: insertText, attributes: attrs)
            guard tv.shouldChangeText(in: sel, replacementString: insertText) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: sel, with: attributed)
            storage.endEditing()
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + attributed.length, length: 0))
        }
        notifyModelChange()
        refreshSelectionState()
    }

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
    private func collectHeadings() -> [(level: Int, text: String)] {
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

    // MARK: - Свойства изображения (v0.1.60, R03)

    /// Диапазон U+FFFC-символа с `.attachment` в позиции курсора (или выделении).
    /// Возвращает nil, если курсор/выделение не на inline-изображении.
    func imageRangeAtCaret() -> NSRange? {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return nil }
        let sel = tv.selectedRange()
        // Если выделен ровно 1 символ и это attachment — берём его.
        if sel.length == 1, sel.location < storage.length,
           storage.attribute(.attachment, at: sel.location, effectiveRange: nil) is NSTextAttachment {
            return sel
        }
        // Иначе — предыдущий символ от курсора (частый случай: клик правой кнопкой ставит курсор ЗА изображением).
        let idx = min(max(sel.location - 1, 0), storage.length - 1)
        if idx >= 0, storage.attribute(.attachment, at: idx, effectiveRange: nil) is NSTextAttachment {
            return NSRange(location: idx, length: 1)
        }
        // И сам символ на позиции курсора — если он есть.
        if sel.location < storage.length,
           storage.attribute(.attachment, at: sel.location, effectiveRange: nil) is NSTextAttachment {
            return NSRange(location: sel.location, length: 1)
        }
        return nil
    }

    /// Метаданные изображения в позиции курсора: ширина в points, alt-text, выравнивание абзаца.
    /// Используется для prefill диалога «Свойства изображения».
    func imagePropertiesAtCaret() -> (widthPt: CGFloat, heightPt: CGFloat, altText: String, alignment: NSTextAlignment)? {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return nil }
        let alt = (storage.attribute(.docxEditImageAltText, at: range.location, effectiveRange: nil) as? String) ?? ""
        let ps = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
        return (att.bounds.width, att.bounds.height, alt, ps.alignment)
    }

    /// Сохраняет режим обтекания изображения (v0.1.102). Записывается в custom
    /// NSAttributedString-ключ; `DocumentModel.from(attributed:)` подхватывает.
    func setImageWrapAtCaret(_ wrap: InlineImageWrap) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret() else { return }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.docxEditImageWrap, value: wrap.rawValue, range: range)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Возвращает текущий режим обтекания изображения под курсором (или .inline если нет).
    func imageWrapAtCaret() -> InlineImageWrap {
        guard let storage = textView?.textStorage,
              let range = imageRangeAtCaret(),
              let raw = storage.attribute(.docxEditImageWrap, at: range.location, effectiveRange: nil) as? String,
              let w = InlineImageWrap(rawValue: raw)
        else { return .inline }
        return w
    }

    /// Обновляет размер и/или alt-text изображения в позиции курсора.
    /// Один атомарный `replaceCharacters` под shouldChangeText — один шаг undo.
    /// `newWidthPt`==0 сохраняет прежнюю ширину; аналогично `newHeightPt`. `newAltText`==nil
    /// не меняет alt-text; пустая строка — сбрасывает.
    func updateImageAtCaret(newWidthPt: CGFloat, newHeightPt: CGFloat, newAltText: String?) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return }
        // Собираем новый attachment: копируем image, ставим bounds.
        let newAtt = NSTextAttachment()
        newAtt.image = att.image
        let curW = att.bounds.width
        let curH = att.bounds.height
        let targetW = newWidthPt > 0 ? newWidthPt : curW
        // Сохраняем пропорции, если задана только ширина.
        let targetH: CGFloat
        if newHeightPt > 0 {
            targetH = newHeightPt
        } else if newWidthPt > 0 && curW > 0 {
            targetH = curH * (newWidthPt / curW)
        } else {
            targetH = curH
        }
        newAtt.bounds = NSRect(x: 0, y: 0, width: targetW, height: targetH)

        // Строим новый одиночный attributed-symbol с прежними атрибутами (paragraph, hyperlink, styleId и т.д.).
        var attrs = storage.attributes(at: range.location, effectiveRange: nil)
        attrs[.attachment] = newAtt
        if let alt = newAltText {
            if alt.isEmpty { attrs.removeValue(forKey: .docxEditImageAltText) }
            else { attrs[.docxEditImageAltText] = alt }
        }
        let m = NSAttributedString(string: "\u{FFFC}", attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Поворачивает изображение под курсором по часовой стрелке на `degreesCW`
    /// градусов (bake в bitmap — angle не хранится отдельно). Один шаг undo.
    /// Для 90°/270° меняет местами width/height у attachment bounds.
    func rotateImageAtCaret(degreesCW: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image,
              let rotated = bakeRotated(src, degreesCW: degreesCW) else { return }
        let normalized = Int((degreesCW.truncatingRemainder(dividingBy: 180)).rounded())
        let swap = normalized != 0
        let curW = att.bounds.width
        let curH = att.bounds.height
        let newW = swap ? curH : curW
        let newH = swap ? curW : curH
        writeRotatedAttachment(rotated, size: NSSize(width: newW, height: newH),
                               at: range, in: storage, tv: tv)
    }

    /// Зеркалит изображение по горизонтали (bake в bitmap). Один шаг undo.
    func flipImageAtCaretHorizontal() {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image,
              let flipped = bakeFlipped(src, horizontal: true) else { return }
        writeRotatedAttachment(flipped, size: att.bounds.size, at: range, in: storage, tv: tv)
    }

    private func writeRotatedAttachment(_ image: NSImage, size: NSSize, at range: NSRange,
                                        in storage: NSTextStorage, tv: NSTextView) {
        let newAtt = NSTextAttachment()
        newAtt.image = image
        newAtt.bounds = NSRect(origin: .zero, size: size)
        var attrs = storage.attributes(at: range.location, effectiveRange: nil)
        attrs[.attachment] = newAtt
        let m = NSAttributedString(string: "\u{FFFC}", attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    private func bakeRotated(_ src: NSImage, degreesCW: CGFloat) -> NSImage? {
        let origSize = src.size
        guard origSize.width > 0, origSize.height > 0 else { return nil }
        let swap = Int((degreesCW.truncatingRemainder(dividingBy: 180)).rounded()) != 0
        let newSize = swap ? NSSize(width: origSize.height, height: origSize.width) : origSize
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let t = NSAffineTransform()
        t.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        // CW-поворот в системе координат AppKit (y-up) = negative radians.
        t.rotate(byRadians: -degreesCW * .pi / 180)
        t.translateX(by: -origSize.width / 2, yBy: -origSize.height / 2)
        t.concat()
        src.draw(at: .zero, from: NSRect(origin: .zero, size: origSize),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    private func bakeFlipped(_ src: NSImage, horizontal: Bool) -> NSImage? {
        let s = src.size
        guard s.width > 0, s.height > 0 else { return nil }
        let out = NSImage(size: s)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let t = NSAffineTransform()
        if horizontal {
            t.translateX(by: s.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
        } else {
            t.translateX(by: 0, yBy: s.height)
            t.scaleX(by: 1, yBy: -1)
        }
        t.concat()
        src.draw(at: .zero, from: NSRect(origin: .zero, size: s),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    /// Обрезает изображение под курсором. `top`/`right`/`bottom`/`left` — доли [0, 1)
    /// от исходных сторон, обрезаемые с соответствующего края. Bake в bitmap; один шаг undo.
    func cropImageAtCaret(topFrac: CGFloat, rightFrac: CGFloat, bottomFrac: CGFloat, leftFrac: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image else { return }
        let t = max(0, min(0.99, topFrac))
        let r = max(0, min(0.99, rightFrac))
        let b = max(0, min(0.99, bottomFrac))
        let l = max(0, min(0.99, leftFrac))
        guard (l + r) < 1, (t + b) < 1 else { return }
        let origSize = src.size
        guard origSize.width > 0, origSize.height > 0 else { return }
        let newW = origSize.width  * (1 - l - r)
        let newH = origSize.height * (1 - t - b)
        let out = NSImage(size: NSSize(width: newW, height: newH))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        // Источник рисуем со сдвигом: (-l·W, -b·H) (нижний-левый угол исходника ниже
        // нового bounds на bottomFrac, левее на leftFrac).
        src.draw(at: NSPoint(x: -origSize.width * l, y: -origSize.height * b),
                 from: NSRect(origin: .zero, size: origSize),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        // Отобразительные размеры сохраняют пропорции обрезки:
        let curW = att.bounds.width
        let curH = att.bounds.height
        let dispW = curW * (1 - l - r)
        let dispH = curH * (1 - t - b)
        writeRotatedAttachment(out, size: NSSize(width: dispW, height: dispH),
                               at: range, in: storage, tv: tv)
    }

    /// Удаляет изображение в позиции курсора — один шаг undo.
    func deleteImageAtCaret() {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret() else { return }
        guard tv.shouldChangeText(in: range, replacementString: "") else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: "")
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// True, если курсор на inline-изображении (для disabled-state пунктов меню).
    var isCaretOnImage: Bool { imageRangeAtCaret() != nil }

    /// Вставляет разрыв страницы (U+000C, Form Feed) в позиции курсора.
    /// В DOCX сериализуется как `<w:br w:type="page"/>` (см. DocxIO renderRun).
    /// При включённых непечатаемых символах DocxLayoutManager рисует маркер.
    func insertPageBreak() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let breakStr = "\u{000C}"
        guard tv.shouldChangeText(in: range, replacementString: breakStr) else { return }
        var attrs = tv.typingAttributes
        // Наследуем шрифт из позиции курсора; если пусто — из typingAttributes.
        if range.location > 0, range.location <= storage.length {
            let src = min(range.location - 1, storage.length - 1)
            if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
        }
        let attributed = NSAttributedString(string: breakStr, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: attributed)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
        notifyModelChange()
    }

    /// Переход по номеру страницы/строки/абзаца. Возвращает true, если целевой
    /// объект найден (курсор поставлен и скролл выполнен). Страница оценивается
    /// как в статистике (usedRect / (pageHeight - margins)).
    func goTo(target: GoToTarget, number: Int) -> Bool {
        guard let tv = textView, let storage = tv.textStorage, number >= 1 else { return false }
        let text = storage.string as NSString

        switch target {
        case .paragraph:
            guard let start = paragraphStart(number: number, in: text) else { return false }
            focus(range: NSRange(location: start, length: 0))
            return true

        case .line:
            guard let lm = tv.layoutManager else { return false }
            var count = 0
            var foundGlyphRange: NSRange?
            let glyphRange = lm.glyphRange(for: tv.textContainer!)
            lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, gRange, stop in
                count += 1
                if count == number {
                    foundGlyphRange = gRange
                    stop.pointee = true
                }
            }
            guard let gr = foundGlyphRange else { return false }
            let charRange = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
            focus(range: NSRange(location: charRange.location, length: 0))
            return true

        case .page:
            guard let lm = tv.layoutManager, let tc = tv.textContainer,
                  let storage = tv.textStorage else { return false }
            let pageSettings = session?.bridge.model.pageSettings
            let pageHeight   = pageSettings?.pageSizeInPoints.height ?? 842
            let topMargin    = CGFloat(pageSettings?.margins.top    ?? 72)
            let bottomMargin = CGFloat(pageSettings?.margins.bottom ?? 72)
            let usable = max(1, pageHeight - topMargin - bottomMargin)
            let targetY = usable * CGFloat(number - 1)
            // Форсируем layout до запроса glyphIndex — иначе на «непрогретом» LM
            // (только что открытом документе) glyphIndex(for:in:) может вернуть 0.
            lm.ensureLayout(for: tc)
            let numGlyphs = lm.numberOfGlyphs
            guard numGlyphs > 0 else {
                focus(range: NSRange(location: 0, length: 0))
                return true
            }
            let glyphIdx = lm.glyphIndex(for: NSPoint(x: 0, y: targetY), in: tc)
            // Clamp — glyphIndex может вернуть numGlyphs (за концом) или fractional-адрес.
            let safeGlyphIdx = min(max(0, glyphIdx), numGlyphs - 1)
            let charIdx = lm.characterIndexForGlyph(at: safeGlyphIdx)
            let safeCharIdx: Int
            if charIdx == NSNotFound || charIdx < 0 {
                safeCharIdx = 0
            } else {
                safeCharIdx = min(charIdx, storage.length)
            }
            focus(range: NSRange(location: safeCharIdx, length: 0))
            return true
        }
    }

    private func paragraphStart(number: Int, in text: NSString) -> Int? {
        var idx = 0
        var loc = 0
        let total = text.length
        while true {
            idx += 1
            if idx == number { return loc }
            let paraRange = text.paragraphRange(for: NSRange(location: loc, length: 0))
            let next = paraRange.location + paraRange.length
            if next > total || next <= loc { return nil }
            loc = next
        }
    }

    private func focus(range: NSRange) {
        guard let tv = textView else { return }
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.window?.makeFirstResponder(tv)
    }

    private func performFinder(_ action: NSTextFinder.Action) {
        guard let textView else { return }
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        textView.performTextFinderAction(item)
    }

    func setZoom(_ level: Double) { zoomLevel = max(0.25, min(4.0, level)) }
    func zoomIn()    { setZoom(snapZoom(up: true)) }
    func zoomOut()   { setZoom(snapZoom(up: false)) }
    func resetZoom() { setZoom(1.0) }

    /// Подгоняет масштаб так, чтобы ширина ОДНОЙ страницы совпала с шириной вьюпорта.
    /// Считает: newMag = viewportWidth / (pageWidth + внешний зазор).
    func fitPageWidth() {
        guard let sv = textView?.enclosingScrollView else { return }
        let viewportW = sv.contentSize.width
        let pageW = session?.bridge.model.pageSettings.pageSizeInPoints.width ?? 595
        guard pageW > 0, viewportW > 0 else { return }
        // Небольшой запас (16pt) чтобы страница не упиралась в края скролла.
        setZoom(Double((viewportW - 16) / pageW))
    }

    /// Подгоняет масштаб так, чтобы ДВЕ страницы поместились рядом по ширине.
    func fitTwoPages() {
        guard let sv = textView?.enclosingScrollView else { return }
        let viewportW = sv.contentSize.width
        let pageW = session?.bridge.model.pageSettings.pageSizeInPoints.width ?? 595
        guard pageW > 0, viewportW > 0 else { return }
        // 2 страницы + зазор между ними (16pt) + запас по краям (24pt).
        setZoom(Double((viewportW - 24) / (pageW * 2 + 16)))
    }

    private let zoomSteps: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
    private func snapZoom(up: Bool) -> Double {
        if up  { return zoomSteps.first(where: { $0 > zoomLevel + 0.01 }) ?? 4.0 }
        else   { return zoomSteps.last(where:  { $0 < zoomLevel - 0.01 }) ?? 0.25 }
    }

    /// Очистка форматирования в выделении.
    func clearFormatting() {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ]
        } else if textView.shouldChangeText(in: range, replacementString: nil) {
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributes([
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ], range: range)
            textView.textStorage?.endEditing()
            textView.didChangeText()
            notifyModelChange()
        }
        refreshSelectionState()
    }

    /// Обновляет все UI-флаги на основе курсора/выделения.
    /// При смешанном выделении: fontName = "", fontSize = 0, hasMixedFonts/Sizes = true.
    /// Определяет язык текущего абзаца через NLLanguageRecognizer (для отображения
    /// в статусбаре). Использует до 1000 символов вокруг курсора для скорости.
    private func detectLanguageAroundCaret() -> String? {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let loc = min(textView.selectedRange().location, ns.length - 1)
        let start = max(0, loc - 500)
        let end = min(ns.length, loc + 500)
        let sample = ns.substring(with: NSRange(location: start, length: end - start))
        // NLLanguageRecognizer нужен ≥ нескольких слов; пустой/короткий текст → nil.
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Устанавливает язык проверки орфографии для NSTextView. Влияет на
    /// подчёркивание орфографических ошибок; текущее определение языка в
    /// статусбаре — независимая величина.
    func setSpellCheckLanguage(_ code: String) {
        guard let textView else { return }
        textView.setSpellingState(0, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        NSSpellChecker.shared.setLanguage(code)
        // Пере-запустить проверку — простой способ: re-toggle continuousSpellChecking.
        let was = textView.isContinuousSpellCheckingEnabled
        textView.isContinuousSpellCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = was
    }

    func refreshSelectionState() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()

        if range.length > 0 {
            // Анализируем все шрифты/размеры в выделении
            var fontNames = Set<String>()
            var fontSizes = Set<CGFloat>()
            storage.enumerateAttribute(.font, in: range, options: []) { val, _, _ in
                if let f = val as? NSFont {
                    fontNames.insert(f.familyName ?? f.fontName)
                    fontSizes.insert(f.pointSize)
                }
            }
            hasMixedFonts = fontNames.count > 1
            hasMixedSizes = fontSizes.count > 1
            fontName = hasMixedFonts ? "" : (fontNames.first ?? fontName)
            fontSize  = hasMixedSizes ? 0 : (fontSizes.first ?? fontSize)

            // B/I/U — по первому символу выделения
            let first = storage.attributes(at: range.location, effectiveRange: nil)
            if let f = first[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                isBold   = t.contains(.bold)
                isItalic = t.contains(.italic)
            }
            isUnderline     = ((first[.underlineStyle]     as? Int) ?? 0) != 0
            isStrikethrough = ((first[.strikethroughStyle] as? Int) ?? 0) != 0
            let firstOffset = (first[.baselineOffset] as? CGFloat) ?? 0
            isSuperscript = firstOffset > 0.5
            isSubscript   = firstOffset < -0.5
            if let c = first[.foregroundColor] as? NSColor { textColor = c }
            highlightColor = first[.backgroundColor] as? NSColor
            if let ps = first[.paragraphStyle] as? NSParagraphStyle {
                textAlignment = ps.alignment
                lineSpacingMultiple = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1.0
                updateListState(from: ps)
            }
            currentStyleId = (first[.docxEditStyleId] as? String) ?? "Normal"
            currentCharStyleId = first[.docxEditCharStyleId] as? String
        } else {
            // Позиция курсора — typingAttributes
            hasMixedFonts = false
            hasMixedSizes = false
            let attrs = textView.typingAttributes
            if let f = attrs[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                isBold    = t.contains(.bold)
                isItalic  = t.contains(.italic)
                fontName  = f.familyName ?? f.fontName
                fontSize  = f.pointSize
            }
            isUnderline     = ((attrs[.underlineStyle]     as? Int) ?? 0) != 0
            isStrikethrough = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0
            let attrsOffset = (attrs[.baselineOffset] as? CGFloat) ?? 0
            isSuperscript = attrsOffset > 0.5
            isSubscript   = attrsOffset < -0.5
            if let c = attrs[.foregroundColor] as? NSColor { textColor = c }
            highlightColor = attrs[.backgroundColor] as? NSColor
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
                textAlignment = ps.alignment
                lineSpacingMultiple = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1.0
                updateListState(from: ps)
            }
            currentStyleId = (attrs[.docxEditStyleId] as? String) ?? "Normal"
            currentCharStyleId = attrs[.docxEditCharStyleId] as? String
        }
        // Курсор в таблице? — читаем NSTextTableBlock из paragraphStyle позиции.
        isCaretInTable = tableSpanAtCaret() != nil
        if storage.length > 0 {
            let probe = min(max(0, textView.selectedRange().location), storage.length - 1)
            isCurrentRowHeader = (storage.attribute(.docxEditRowHeader, at: probe, effectiveRange: nil) as? Bool) ?? false
            // v0.1.90: источник истины — `.height` самого NSTextTableBlock (его пишет
            // и ресайз мышью, и appendTable). Кастомный ключ — фолбэк для случаев,
            // когда блок недоступен.
            var rowH: CGFloat? = nil
            if let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
               let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
               cb.valueType(for: .height) == .absoluteValueType, cb.value(for: .height) > 0 {
                rowH = cb.value(for: .height)
            } else {
                let raw = storage.attribute(.docxEditRowHeight, at: probe, effectiveRange: nil)
                if let v = raw as? CGFloat { rowH = v }
                else if let v = raw as? Double { rowH = CGFloat(v) }
                else if let v = raw as? NSNumber { rowH = CGFloat(truncating: v) }
            }
            currentRowHeight = rowH
        } else {
            isCurrentRowHeader = false
            currentRowHeight = nil
        }
        currentLanguageCode = detectLanguageAroundCaret()
        // v0.3.1: авто-переключение спелчек-языка на определённый язык абзаца.
        if AppPreferences.shared.autoDetectSpellLanguage,
           let lang = currentLanguageCode,
           lang != lastAppliedSpellLanguage,
           ["ru", "en"].contains(lang) {
            let bcp = lang == "ru" ? "ru_RU" : "en_US"
            setSpellCheckLanguage(bcp)
            lastAppliedSpellLanguage = lang
        }
    }

    /// Обновляет published-состояние списка (тип + вариант галереи) по стилю абзаца
    /// и запоминает распознанный вариант как «последний» для будущих ⌘]/⌘[.
    private func updateListState(from ps: NSParagraphStyle) {
        let info = ParagraphAttributes.from(nsParagraphStyle: ps).listInfo
        currentListType = info?.listType
        if let info {
            let variant = detectVariant(for: info)
            if variant.format(at: info.level) == info.formatStyle {
                currentListVariantId = variant.id
                lastVariant[info.listType] = variant
            } else {
                currentListVariantId = nil
            }
        } else {
            currentListVariantId = nil
        }
    }

    func refreshStatus() {
        guard let session else { return }
        let stats = DocumentStatisticsCalculator.calculate(session.bridge.model)
        statusText = "Слов: \(stats.words) · Символов: \(stats.characters) · \(session.bridge.model.metadata.language)"
    }

    /// Уведомление от NSTextView: пользователь изменил текст.
    func userDidEdit(text: NSAttributedString) {
        session?.applyAttributed(text)
        refreshStatus()
        maybeAutoRefreshToc()
    }

    /// v0.5.6 (R07): если в документе есть TOC-блок и последняя правка задела
    /// заголовок (paragraph.styleId начинается на "Heading"), пересобираем
    /// оглавление. Дешёвая эвристика — проверяем СУЩЕСТВОВАНИЕ хоть одного
    /// TOC-блока в текущем storage; если нет — сразу выходим. При наличии
    /// сверяем список заголовков (`collectHeadings`) с последним снэпшотом;
    /// перерисовываем только при отличии — избегаем лишних правок при обычной
    /// печати в теле абзацев.
    private var lastTocHeadingsSnapshot: String = ""
    private var isRefreshingToc = false
    private func maybeAutoRefreshToc() {
        guard !isRefreshingToc, let tv = textView, let storage = tv.textStorage else { return }
        var hasToc = false
        storage.enumerateAttribute(.docxEditTocBlock,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { val, _, stop in
            if val != nil { hasToc = true; stop.pointee = true }
        }
        guard hasToc else { return }
        let key = collectHeadings().map { "\($0.level)|\($0.text)" }.joined(separator: "\n")
        guard key != lastTocHeadingsSnapshot else { return }
        lastTocHeadingsSnapshot = key
        isRefreshingToc = true
        updateTableOfContents()
        isRefreshingToc = false
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

    private func notifyModelChange() {
        guard let textView, let session else { return }
        session.applyAttributed(textView.attributedString())
    }
}