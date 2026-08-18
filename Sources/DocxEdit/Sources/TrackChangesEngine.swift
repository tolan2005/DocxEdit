//
//  TrackChangesEngine.swift
//  DocxEdit
//
//  v0.4.6 (R06): движок отслеживания правок. Второй R06-компаньон.
//
//  Механика: при `isRecording = true` каждая правка перехватывается в
//  `interceptChange` (вызывается из Coordinator.textView(_:shouldChangeTextIn:)
//  ДО реального изменения storage). Вставка — сам разрешаем правку и после
//  фиксации помечаем вставленный диапазон `.docxEditInsertion`. Удаление —
//  НЕ даём удалить: сами помечаем существующий диапазон `.docxEditDeletion`
//  + strikethrough, возвращаем false. Замена = удаление + вставка.
//

import Foundation
import AppKit

@MainActor
final class TrackChangesEngine: ObservableObject {
    weak var textView: NSTextView?
    weak var session: DocumentSession?

    @Published var isRecording: Bool = false
    @Published private(set) var version: Int = 0

    private let author: String = CommentsEngine.defaultAuthor()

    /// Serialize revision info в строку для custom-атрибута.
    private func revValue() -> String {
        let iso = ISO8601DateFormatter().string(from: Date())
        return "\(author)|\(iso)|\(UUID().uuidString.prefix(8))"
    }

    /// Вызывается из Coordinator в `textView(_:shouldChangeTextIn:replacementString:)`
    /// при `isRecording`. Возвращает true — «правку разрешаю, применяй как есть»
    /// (Coordinator ниже применит и потом должен позвать `finalizeInsertion` для
    /// пометки вставленного диапазона); false — «правку отменил, я применил свою».
    ///
    /// Для чистой вставки (`range.length == 0`, есть replacement) → возвращаем
    /// true и запоминаем ожидание в `pendingInsertion`, чтобы в `textDidChange`
    /// пометить свежий диапазон.
    ///
    /// Для чистого удаления (есть длина, replacement пустой) → сами
    /// помечаем `.docxEditDeletion` + strikethrough, false.
    ///
    /// Для замены (есть и длина, и replacement) → помечаем деление, вставляем
    /// новый текст с insertion-меткой; false. MVP: реализуем упрощённо —
    /// пропускаем через дефолт (без пометки), т.к. корректный replace через
    /// два шага требует undo-совместимости; замену покроем в следующем цикле,
    /// а пока track изменений отслеживает только чистые вставки/удаления.
    func interceptChange(range: NSRange, replacementString: String?) -> Bool {
        guard isRecording, let tv = textView, let storage = tv.textStorage else {
            return true
        }
        // 1) Чистая вставка.
        if range.length == 0, let s = replacementString, !s.isEmpty {
            pendingInsertion = (location: range.location, length: (s as NSString).length)
            return true
        }
        // 2) Чистое удаление — метим (не удаляем).
        if range.length > 0, replacementString?.isEmpty ?? false {
            let val = revValue()
            guard tv.shouldChangeText(in: range, replacementString: nil) else { return false }
            storage.beginEditing()
            storage.addAttribute(.docxEditDeletion, value: val, range: range)
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.strikethroughColor, value: NSColor.systemRed, range: range)
            storage.endEditing()
            tv.didChangeText()
            version += 1
            // Перемещаем курсор за удаляемый span, чтобы поведение походило
            // на реальное удаление.
            tv.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
            return false
        }
        // 3) Замена и прочее — пропускаем без пометки (MVP).
        return true
    }

    private var pendingInsertion: (location: Int, length: Int)?

    /// Вызывать после `textDidChange` (когда NSTextView уже применил вставку).
    func finalizeInsertionIfPending() {
        guard isRecording, let tv = textView, let storage = tv.textStorage,
              let ins = pendingInsertion else { return }
        pendingInsertion = nil
        let range = NSRange(location: ins.location, length: ins.length)
        // Клэмп на случай последующих правок.
        guard range.location + range.length <= storage.length else { return }
        let val = revValue()
        storage.beginEditing()
        storage.addAttribute(.docxEditInsertion, value: val, range: range)
        // Визуально — цвет вставки (accent).
        storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
        storage.endEditing()
        version += 1
    }

    // MARK: - Управление и обход

    func toggle() { isRecording.toggle(); version += 1 }

    /// Принять все правки: снять маркеры insertion + удалить помеченные
    /// deletions. Один шаг undo.
    func acceptAll() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        // Собираем удаления → удаляем справа налево.
        var deletions: [NSRange] = []
        storage.enumerateAttribute(.docxEditDeletion, in: full, options: []) { val, r, _ in
            if val != nil { deletions.append(r) }
        }
        // Insertion — просто снять маркеры и покрасить в labelColor.
        var insertions: [NSRange] = []
        storage.enumerateAttribute(.docxEditInsertion, in: full, options: []) { val, r, _ in
            if val != nil { insertions.append(r) }
        }
        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        for r in insertions {
            storage.removeAttribute(.docxEditInsertion, range: r)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: r)
        }
        for r in deletions.sorted(by: { $0.location > $1.location }) {
            storage.deleteCharacters(in: r)
        }
        storage.endEditing()
        tv.didChangeText()
        version += 1
    }

    /// Отклонить все правки: удалить вставки + снять маркеры/зачёркивание с
    /// удалений (текст возвращается в живой поток).
    func rejectAll() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        var insertions: [NSRange] = []
        storage.enumerateAttribute(.docxEditInsertion, in: full, options: []) { val, r, _ in
            if val != nil { insertions.append(r) }
        }
        var deletions: [NSRange] = []
        storage.enumerateAttribute(.docxEditDeletion, in: full, options: []) { val, r, _ in
            if val != nil { deletions.append(r) }
        }
        guard tv.shouldChangeText(in: full, replacementString: nil) else { return }
        storage.beginEditing()
        for r in deletions {
            storage.removeAttribute(.docxEditDeletion, range: r)
            storage.removeAttribute(.strikethroughStyle, range: r)
            storage.removeAttribute(.strikethroughColor, range: r)
        }
        for r in insertions.sorted(by: { $0.location > $1.location }) {
            storage.deleteCharacters(in: r)
        }
        storage.endEditing()
        tv.didChangeText()
        version += 1
    }

    /// Число активных ревизий (для статусбара / индикатора).
    func revisionCount() -> Int {
        listRevisions().count
    }

    // MARK: - Обход и точечное принятие/отклонение

    /// Один изменённый диапазон.
    struct Revision {
        enum Kind { case insertion, deletion }
        let kind: Kind
        let range: NSRange
        let value: String   // "author|iso-date|revId"
        var author: String { value.split(separator: "|").first.map(String.init) ?? "" }
    }

    /// Все правки в порядке появления в тексте. Соседние символы с одним и тем
    /// же значением атрибута группируются в один Revision (через
    /// `longestEffectiveRange`).
    func listRevisions() -> [Revision] {
        guard let storage = textView?.textStorage else { return [] }
        let full = NSRange(location: 0, length: storage.length)
        var revs: [Revision] = []
        var loc = 0
        while loc < full.length {
            let range = NSRange(location: loc, length: full.length - loc)
            var effective = NSRange(location: 0, length: 0)
            let ins = storage.attribute(.docxEditInsertion, at: loc,
                                        longestEffectiveRange: &effective, in: range) as? String
            let del = storage.attribute(.docxEditDeletion, at: loc,
                                        longestEffectiveRange: &effective, in: range) as? String
            if let s = ins {
                revs.append(Revision(kind: .insertion, range: effective, value: s))
            } else if let s = del {
                revs.append(Revision(kind: .deletion, range: effective, value: s))
            }
            loc = effective.location + max(effective.length, 1)
        }
        return revs
    }

    /// Ближайшая правка от текущей позиции курсора; nil — нет правок.
    func nextRevision() -> Revision? {
        guard let tv = textView else { return nil }
        let caret = tv.selectedRange().location
        let revs = listRevisions()
        return revs.first { $0.range.location >= caret } ?? revs.first
    }

    /// Позиционирует курсор на следующую правку.
    func goToNextRevision() {
        guard let rev = nextRevision(), let tv = textView else { return }
        tv.setSelectedRange(rev.range)
        tv.scrollRangeToVisible(rev.range)
    }

    /// Принять одну правку в указанном диапазоне.
    func acceptOne(_ rev: Revision) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard tv.shouldChangeText(in: rev.range, replacementString: nil) else { return }
        storage.beginEditing()
        switch rev.kind {
        case .insertion:
            storage.removeAttribute(.docxEditInsertion, range: rev.range)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: rev.range)
            storage.endEditing()
            tv.didChangeText()
        case .deletion:
            storage.deleteCharacters(in: rev.range)
            storage.endEditing()
            tv.didChangeText()
        }
        version += 1
    }

    /// Отклонить одну правку в указанном диапазоне.
    func rejectOne(_ rev: Revision) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard tv.shouldChangeText(in: rev.range, replacementString: nil) else { return }
        storage.beginEditing()
        switch rev.kind {
        case .insertion:
            storage.deleteCharacters(in: rev.range)
            storage.endEditing()
            tv.didChangeText()
        case .deletion:
            storage.removeAttribute(.docxEditDeletion, range: rev.range)
            storage.removeAttribute(.strikethroughStyle, range: rev.range)
            storage.removeAttribute(.strikethroughColor, range: rev.range)
            storage.endEditing()
            tv.didChangeText()
        }
        version += 1
    }
}
