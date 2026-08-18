//
//  CommentsEngine.swift
//  DocxEdit
//
//  v0.4.4 (R06): движок комментариев. Первая R06-подсистема-компаньон
//  (DESIGN_R06.md §2): вся логика — здесь; в DocumentController лишь ссылка
//  на движок. Идентичность треда с текстом — через custom NSAttributedString
//  key `.docxEditCommentId` (§3): переживает пересборку модели.
//

import Foundation
import AppKit
import DocxCore

@MainActor
final class CommentsEngine: ObservableObject {
    weak var textView: NSTextView?
    weak var session: DocumentSession?

    /// Триггерится при add/remove/resolve — для перерисовки UI-панелей.
    @Published private(set) var version: Int = 0

    private var bridge: NSDocumentBridge? { session?.bridge }

    // MARK: - API

    /// Добавляет тред к текущему выделению. При пустом выделении —
    /// расширяет диапазон на 1 символ (правее курсора, у конца документа —
    /// левее), потому что NSAttributedString не хранит атрибуты на 0-длину.
    /// Возвращает id созданного треда или nil, если добавить не удалось
    /// (нет textView / документ пуст).
    @discardableResult
    func addComment(text: String, author: String? = nil) -> String? {
        let author = author ?? Self.defaultAuthor()
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return nil }
        var range = tv.selectedRange()
        if range.length == 0 {
            if range.location < storage.length { range.length = 1 }
            else if range.location > 0 { range.location -= 1; range.length = 1 }
            else { return nil }
        }
        // Клэмп на всякий случай.
        range = NSRange(location: max(0, range.location),
                        length: min(range.length, storage.length - range.location))
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return nil }
        let thread = CommentThread(author: author, text: text)
        storage.beginEditing()
        storage.addAttribute(.docxEditCommentId, value: thread.id, range: range)
        storage.endEditing()
        tv.didChangeText()
        bridge?.appendCommentThread(thread)
        session?.markDirty()
        version += 1
        return thread.id
    }

    /// Ответ в тред.
    func addReply(threadId: String, text: String, author: String? = nil) {
        let author = author ?? Self.defaultAuthor()
        guard let bridge, var thread = bridge.model.comments.first(where: { $0.id == threadId }) else { return }
        thread.replies.append(CommentReply(author: author, text: text))
        bridge.updateCommentThread(thread)
        session?.markDirty()
        version += 1
    }

    /// Помечает тред решённым/нерешённым (визуально не подчёркивает,
    /// оставаясь в списке до явного удаления — как принято в текстовых редакторах).
    func setResolved(threadId: String, resolved: Bool) {
        guard let bridge, var thread = bridge.model.comments.first(where: { $0.id == threadId }) else { return }
        thread.resolved = resolved
        bridge.updateCommentThread(thread)
        session?.markDirty()
        version += 1
    }

    /// Удаляет тред + снимает атрибут с якорного текста (если он ещё
    /// существует — при осиротевшем треде атрибута может уже не быть,
    /// это не ошибка).
    func removeComment(threadId: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        var anchor: NSRange? = nil
        storage.enumerateAttribute(.docxEditCommentId, in: full, options: []) { val, r, stop in
            if let id = val as? String, id == threadId {
                anchor = r; stop.pointee = true
            }
        }
        if let range = anchor, tv.shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            storage.removeAttribute(.docxEditCommentId, range: range)
            storage.endEditing()
            tv.didChangeText()
        }
        bridge?.removeCommentThread(id: threadId)
        session?.markDirty()
        version += 1
    }

    /// Треды в порядке появления в тексте (осиротевшие — в конце).
    /// Возвращает (тред, якорный диапазон или nil если осиротевший).
    func listComments() -> [(thread: CommentThread, anchor: NSRange?)] {
        guard let bridge, let storage = textView?.textStorage else { return [] }
        var anchors: [String: NSRange] = [:]
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.docxEditCommentId, in: full, options: []) { val, r, _ in
            if let id = val as? String, anchors[id] == nil { anchors[id] = r }
        }
        let anchored = bridge.model.comments
            .filter { anchors[$0.id] != nil }
            .sorted { (anchors[$0.id]?.location ?? 0) < (anchors[$1.id]?.location ?? 0) }
            .map { ($0, anchors[$0.id]) }
        let orphans = bridge.model.comments
            .filter { anchors[$0.id] == nil }
            .map { ($0, NSRange?.none) }
        return anchored + orphans
    }

    /// Позиционирует курсор на якорный текст треда и прокручивает к нему.
    func goToComment(threadId: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.docxEditCommentId, in: full, options: []) { val, r, stop in
            if let id = val as? String, id == threadId {
                tv.setSelectedRange(r)
                tv.scrollRangeToVisible(r)
                stop.pointee = true
            }
        }
    }

    /// Тред под курсором (если есть) — для показа в панели «Ответить/Решить».
    func threadAtCaret() -> CommentThread? {
        guard let tv = textView, let storage = tv.textStorage,
              storage.length > 0 else { return nil }
        let loc = min(tv.selectedRange().location, storage.length - 1)
        guard let id = storage.attribute(.docxEditCommentId, at: loc, effectiveRange: nil) as? String else {
            return nil
        }
        return bridge?.model.comments.first { $0.id == id }
    }

    // MARK: - Utils

    static func defaultAuthor() -> String {
        // Пробуем реальное полное имя пользователя macOS; иначе — короткий логин;
        // в песочнице (SwiftPM tests) не должно упасть.
        let full = NSFullUserName()
        if !full.isEmpty { return full }
        return NSUserName().isEmpty ? "Аноним" : NSUserName()
    }
}
