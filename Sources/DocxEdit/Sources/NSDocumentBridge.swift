//
//  NSDocumentBridge.swift
//  DocxEdit
//
//  Обёртка над DocumentModel с поддержкой undo/redo, файловых URL и dirty-флага.
//

import Foundation
import DocxCore

/// Мост между UI-уровнем и моделью документа. В R01 — упрощённый.
final class NSDocumentBridge {
    private(set) var model: DocumentModel
    var fileURL: URL?
    var isDirty: Bool = false

    init(model: DocumentModel, fileURL: URL? = nil) {
        self.model = model
        self.fileURL = fileURL
    }

    static let empty = NSDocumentBridge(model: DocumentModel())
}

extension NSDocumentBridge {
    /// Упрощённый toggle атрибута символа: применяется ко всем ранам первого параграфа.
    func toggleAttribute(keyPath: WritableKeyPath<CharacterAttributes, Bool>) {
        guard var p = model.sections.first?.blocks.first.flatMap({
            if case .paragraph(let p) = $0 { return p } else { return nil }
        }) else { return }
        for i in p.runs.indices {
            p.runs[i].attributes[keyPath: keyPath].toggle()
        }
        model.sections[0].blocks[0] = .paragraph(p)
        isDirty = true
    }

    func toggleAttribute(keyPath: WritableKeyPath<CharacterAttributes, UnderlineStyle>) {
        guard var p = model.sections.first?.blocks.first.flatMap({
            if case .paragraph(let p) = $0 { return p } else { return nil }
        }) else { return }
        for i in p.runs.indices {
            let current = p.runs[i].attributes[keyPath: keyPath]
            p.runs[i].attributes[keyPath: keyPath] = (current == .none) ? .single : .none
        }
        model.sections[0].blocks[0] = .paragraph(p)
        isDirty = true
    }

    func clearFormatting() {
        for section in model.sections.indices {
            for blockIdx in model.sections[section].blocks.indices {
                if case .paragraph(var p) = model.sections[section].blocks[blockIdx] {
                    p.runs = p.runs.map { run in
                        var a = run
                        a.attributes = CharacterAttributes()
                        return a
                    }
                    model.sections[section].blocks[blockIdx] = .paragraph(p)
                }
            }
        }
        isDirty = true
    }

    // MARK: - Override стилей (для диалога «Стили…»)

    func setParagraphStyleOverride(id: String, def: ParagraphStyleDef?) {
        if let def { model.styles.paragraphStyles[id] = def }
        else       { model.styles.paragraphStyles.removeValue(forKey: id) }
        isDirty = true
    }

    func setCharacterStyleOverride(id: String, def: CharacterStyleDef?) {
        if let def { model.styles.characterStyles[id] = def }
        else       { model.styles.characterStyles.removeValue(forKey: id) }
        isDirty = true
    }

    var paragraphStyleOverrides: [String: ParagraphStyleDef] { model.styles.paragraphStyles }
    var characterStyleOverrides: [String: CharacterStyleDef] { model.styles.characterStyles }

    // MARK: - Колонтитулы

    func setHeaderFooter(_ hf: HeaderFooter) {
        model.headerFooter = hf
        // v1.5.1: колонтитул отредактирован — экспорт регенерирует части из
        // модели (lossless passthrough исходных байтов отключается).
        model.headerFooterEdited = true
        isDirty = true
    }

    var headerFooter: HeaderFooter { model.headerFooter }

    // MARK: - Замена модели целиком (v1.6.0, MD source-режим)

    /// Заменяет модель (реимпорт из Markdown-исходника). Метаданные/настройки
    /// страницы/стили переносятся — из Markdown они не восстанавливаются.
    func replaceModel(_ new: DocumentModel) {
        var m = new
        m.metadata = model.metadata
        m.pageSettings = model.pageSettings
        m.styles = model.styles
        m.headerFooter = model.headerFooter
        m.yamlFrontMatter = model.yamlFrontMatter
        model = m
        isDirty = true
    }

    // MARK: - Сноски (v0.5.3, R07)

    /// Добавляет новую сноску. id должен быть уникальным (не пересекаться
    /// с существующими). Проверяет, чтобы не было дубликата.
    func addFootnote(_ footnote: Footnote) {
        guard !model.footnotes.contains(where: { $0.id == footnote.id }) else { return }
        model.footnotes.append(footnote)
        isDirty = true
    }

    /// Обновляет текст существующей сноски. Если нет — no-op.
    func updateFootnoteText(id: String, text: String) {
        guard let idx = model.footnotes.firstIndex(where: { $0.id == id }) else { return }
        model.footnotes[idx].text = text
        isDirty = true
    }

    /// Удаляет сноску по id из модели. Якорь в тексте (custom-атрибут) —
    /// отдельно, чистит вызывающий код.
    func removeFootnote(id: String) {
        model.footnotes.removeAll { $0.id == id }
        isDirty = true
    }

    // MARK: - Концевые сноски (v1.5.15)

    /// Обновляет текст существующей концевой сноски. Если нет — no-op.
    func updateEndnoteText(id: String, text: String) {
        guard let idx = model.endnotes.firstIndex(where: { $0.id == id }) else { return }
        model.endnotes[idx].text = text
        isDirty = true
    }

    var endnotes: [Footnote] { model.endnotes }

    /// Добавляет концевую сноску (v1.6.2, UI-вставка).
    func addEndnote(_ endnote: Footnote) {
        guard !model.endnotes.contains(where: { $0.id == endnote.id }) else { return }
        model.endnotes.append(endnote)
        isDirty = true
    }

    var footnotes: [Footnote] { model.footnotes }

    /// v0.5.4: полная замена списка сносок (используется renumberFootnotes).
    func replaceFootnotes(_ notes: [Footnote]) {
        model.footnotes = notes
        isDirty = true
    }

    // MARK: - Параметры страницы (v0.1.56)

    /// Заменяет параметры страницы текущей модели и помечает документ dirty.
    /// Вызывается при смене defaultPageSettings в Preferences — чтобы открытый
    /// документ сразу обновил ориентацию/поля/формат (пробрасывание через
    /// NotificationCenter → Coordinator → controller.setPageSettings).
    func setPageSettings(_ settings: PageSettings) {
        model.pageSettings = settings
        isDirty = true
    }

    // MARK: - Метаданные документа (v0.2.1, R04)

    func setMetadata(title: String, author: String, subject: String,
                     keywords: [String], language: String) {
        model.metadata.title = title
        model.metadata.author = author
        model.metadata.subject = subject
        model.metadata.keywords = keywords
        model.metadata.language = language
        model.metadata.modifiedAt = Date()
        isDirty = true
    }

    var metadata: DocumentMetadata { model.metadata }

    // MARK: - Комментарии (v0.4.4, R06)

    func appendCommentThread(_ thread: CommentThread) {
        model.comments.append(thread)
        isDirty = true
    }

    func updateCommentThread(_ thread: CommentThread) {
        if let idx = model.comments.firstIndex(where: { $0.id == thread.id }) {
            model.comments[idx] = thread
            isDirty = true
        }
    }

    func removeCommentThread(id: String) {
        model.comments.removeAll { $0.id == id }
        isDirty = true
    }
}

// CharacterAttributes.Value больше не нужен — оставлен для совместимости заглушек.
