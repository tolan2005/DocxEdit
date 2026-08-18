//
//  DocumentMode.swift
//  DocxEdit
//
//  v1.4.0 (ADR-049): режим документа — DOCX (полный WYSIWYG) или Markdown
//  (ограниченный набор инструментов, сохранение в .md по умолчанию).
//  Режим — свойство DocumentSession (per-window), модель документа общая.
//

import Foundation

enum DocumentMode: String, CaseIterable, Identifiable {
    case docx
    case markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .docx:     return "DOCX"
        case .markdown: return "Markdown"
        }
    }

    /// Расширение файла при сохранении «по умолчанию» в этом режиме.
    var saveExtension: String {
        switch self {
        case .docx:     return "docx"
        case .markdown: return "md"
        }
    }

    /// Имя файла по умолчанию для «Сохранить как…» в этом режиме.
    var defaultSaveName: String { "Без имени.\(saveExtension)" }

    /// Режим по расширению файла. Неизвестные расширения — .docx
    /// (сохраняет прежнее поведение для doc/rtf/odt/txt).
    static func from(url: URL) -> DocumentMode {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return .markdown
        default:               return .docx
        }
    }

    // MARK: - Ограничение инструментов в MD-режиме (v1.4.1, ADR-049)

    /// Группы ribbon, полностью скрываемые в Markdown-режиме
    /// (id из `RibbonGroupDef.all`). Частично урезанные группы
    /// (home.font, home.paragraph, insert.links, view.zoom) режутся
    /// гранулярно внутри RibbonView по `isMarkdown`.
    static let markdownHiddenRibbonGroups: Set<String> = [
        "insert.references", // оглавление/сноски — в MD нет
        "layout.breaks",     // разрывы страниц — в MD нет страниц
        "layout.headers",    // колонтитулы/номера страниц
        "review.comments",   // комментарии не экспортируются в MD
        "review.changes",    // track changes не экспортируется в MD
        "review.reports",    // отчёт об открытии — специфика DOCX-импорта
        "view.mode",         // вид страницы/режим чтения
    ]

    /// Команды каталога ribbon (id из `RibbonCommandDef.all`), разрешённые
    /// в Markdown-режиме — фильтр группы «Избранное».
    static let markdownAllowedCommands: Set<String> = [
        "hyperlink", "image", "table", "symbol", "print", "exportPDF",
        "statistics", "findReplace", "goTo", "styles", "readingMode",
    ]
}
