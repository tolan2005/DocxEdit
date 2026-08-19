//
//  DocumentSession.swift
//  DocxEdit
//
//  Общая сессия документа, разделяемая между AppDelegate и DocumentController.
//  R01: ObservableObject поверх NSDocumentBridge с NSAttributedString для WYSIWYG.
//

import Foundation
import SwiftUI
import AppKit
import DocxCore
import MarkdownIO

@MainActor
final class DocumentSession: ObservableObject {
    /// Текущий открытый документ.
    @Published private(set) var bridge: NSDocumentBridge = .empty

    /// v1.4.0 (ADR-049): режим документа — DOCX или Markdown. Определяется
    /// расширением при открытии; для нового документа — из настроек.
    /// Влияет на формат сохранения по умолчанию и набор инструментов (v1.4.1).
    @Published var mode: DocumentMode

    /// v1.6.0: исходный режим Markdown — редактирование сырого .md текста
    /// с подсветкой синтаксиса (только при mode == .markdown). Источник истины
    /// в этом режиме — `markdownSource`; модель синхронизируется на каждую
    /// правку (для статистики/автосейва) и при выходе в WYSIWYG.
    @Published var isMarkdownSourceMode: Bool = false
    @Published var markdownSource: String = ""

    /// Войти в исходный режим: экспорт текущей модели в Markdown.
    func enterMarkdownSourceMode() {
        guard mode == .markdown else { return }
        markdownSource = MarkdownIO.exportMarkdown(bridge.model,
                                                   prettyTables: AppPreferences.shared.markdownPrettyTables)
        isMarkdownSourceMode = true
    }

    /// Правка исходника: текст + best-effort синхронизация модели
    /// (swift-markdown отказоустойчив к недописанному синтаксису).
    func applyMarkdownSource(_ text: String) {
        markdownSource = text
        if let model = try? MarkdownIO.importMarkdown(string: text) {
            bridge.replaceModel(model)
        }
        markDirty()
    }

    /// Выйти в WYSIWYG: перестроить attributedText из модели.
    func exitMarkdownSourceMode() {
        isMarkdownSourceMode = false
        attributedText = bridge.model.toAttributedString(
            defaultFont: preferredDefaultFont(),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first,
            usableWidth: bridge.model.pageSettings.usableWidthInPoints)
    }

    /// Полное NSAttributedString-представление текущей модели.
    /// Используется NSTextView через textStorage; обновляется при open/reset/import.
    @Published var attributedText: NSAttributedString

    /// Отчёт об импорте (v0.1.56): что не удалось полноценно восстановить из
    /// последнего открытого файла. Показывается в диалоге «Отчёт об открытии».
    @Published var lastImportReport: ImportReport = ImportReport()

    /// v0.5.7 (R08): производительность последнего открытия/сохранения —
    /// длительность и размер файла. Обнуляется при `reset()`. Показывается в
    /// «Отчёт об открытии» и «Статистике документа».
    @Published var lastMetrics: PerformanceMetrics = .init()

    init() {
        self.mode = AppPreferences.shared.newDocumentMode
        self.attributedText = NSAttributedString(
            string: "",
            attributes: Self.currentDefaultAttributes()
        )
    }

    /// Атрибуты для пустого документа/typingAttributes: шрифт и размер из настроек.
    /// Читается статически, чтобы UI Preferences не приходилось прокидывать в session.
    static func currentDefaultAttributes() -> [NSAttributedString.Key: Any] {
        let prefs = AppPreferences.shared
        let font = NSFont(name: prefs.defaultFontName, size: CGFloat(prefs.defaultFontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(prefs.defaultFontSize))
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private func preferredDefaultFont() -> NSFont {
        (Self.currentDefaultAttributes()[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
    }

    /// Изменён ли документ с момента открытия/сохранения.
    var isDirty: Bool { bridge.isDirty }

    /// Уникальный идентификатор сессии — используется как имя файла автосейва.
    let sessionId: UUID = UUID()

    /// Имя файла автосейва в директории autorecover. Стабилен на протяжении
    /// сессии, используется чтобы найти и удалить бэкап при явном сохранении.
    var autorecoverFileName: String { "\(sessionId.uuidString).docxedit-autosave.json" }

    /// Заголовок окна: имя файла + `*` для несохранённых изменений.
    var windowTitle: String {
        let name = bridge.fileURL?.lastPathComponent ?? "Без имени"
        return bridge.isDirty ? "\(name) *" : name
    }

    /// Помечает документ сохранённым по URL. Явно уведомляет наблюдателей —
    /// `NSDocumentBridge` это class, мутация его полей не триггерит `@Published`.
    func markSaved(url: URL) {
        objectWillChange.send()
        bridge.fileURL = url
        bridge.isDirty = false
    }

    /// Помечает документ гряным (например, после правки `bridge.model.styles`
    /// напрямую из UI, минуя текстовые правки). Симметрично `markSaved`.
    func markDirty() {
        objectWillChange.send()
        bridge.isDirty = true
    }

    /// Заменяет документ целиком (при open / new). Пересчитывает attributedText.
    func replace(with bridge: NSDocumentBridge) {
        self.bridge = bridge
        // v1.6.0: открытие/создание документа — всегда в визуальном режиме.
        isMarkdownSourceMode = false
        markdownSource = ""
        self.attributedText = bridge.model.toAttributedString(
            defaultFont: preferredDefaultFont(),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first,
            usableWidth: bridge.model.pageSettings.usableWidthInPoints)
    }

    /// Полный сброс на пустой документ.
    func reset() {
        self.bridge = .empty
        self.mode = AppPreferences.shared.newDocumentMode
        isMarkdownSourceMode = false
        markdownSource = ""
        self.attributedText = bridge.model.toAttributedString(
            defaultFont: preferredDefaultFont(),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first,
            usableWidth: bridge.model.pageSettings.usableWidthInPoints)
    }

    /// Применяет новое attributed-представление (после правки пользователем в NSTextView).
    /// Перестраивает DocumentModel из attributed и помечает как «грязный».
    /// **Сохраняет из старой модели `pageSettings`, `metadata`, `styles`** — они не
    /// восстанавливаются из attributed string и раньше сбрасывались на дефолт при
    /// любой правке: терялись пользовательские настройки страницы, метаданные и
    /// override стандартных стилей (баг #6 фидбека v0.1.36 — override стиля в
    /// диалоге «Стили…» сбрасывался при следующей же правке текста).
    func applyAttributed(_ attributed: NSAttributedString) {
        var newModel = DocumentModel.from(attributed: attributed)
        newModel.pageSettings = bridge.model.pageSettings
        newModel.metadata     = bridge.model.metadata
        newModel.styles       = bridge.model.styles
        newModel.headerFooter = bridge.model.headerFooter
        // v1.5.1: passthrough-части колонтитулов и флаг редактирования тоже
        // переживают пересборку модели из attributed string.
        newModel.preservedHeaderFooter = bridge.model.preservedHeaderFooter
        newModel.headerFooterEdited = bridge.model.headerFooterEdited
        // v1.5.2: passthrough неизвестных частей пакета тоже переживает
        // пересборку модели из attributed string.
        newModel.preservedParts = bridge.model.preservedParts
        newModel.preservedContentTypes = bridge.model.preservedContentTypes
        newModel.preservedSettingsXml = bridge.model.preservedSettingsXml
        // v1.5.4: passthrough extras sectPr (колонки и др.).
        newModel.preservedSectPrExtras = bridge.model.preservedSectPrExtras
        newModel.comments     = bridge.model.comments
        // v0.5.3 (R07): from(attributed:) не пересобирает содержимое сносок
        // (footnoteId на ранах — да, но тексты — отдельная область модели),
        // поэтому переносим их вручную, как и другие метаданные.
        newModel.footnotes    = bridge.model.footnotes
        // v1.5.15/1.5.17: концевые сноски и passthrough стилей таблиц тоже
        // переживают пересборку (были потеряны при первой правке — латентный баг).
        newModel.endnotes     = bridge.model.endnotes
        newModel.preservedTableStylesXml = bridge.model.preservedTableStylesXml
        let newBridge = NSDocumentBridge(model: newModel, fileURL: bridge.fileURL)
        newBridge.isDirty = true
        self.bridge = newBridge
        self.attributedText = attributed
    }

    /// Обновляет только attributedText (без перестроения модели) — используется
    /// для синхронизации UI ↔ модель, когда форматирование было применено
    /// непосредственно к NSTextStorage.
    func syncAttributed(_ attributed: NSAttributedString) {
        self.attributedText = attributed
        bridge.isDirty = true
    }
}

/// v0.5.7 (R08): timings и размеры последнего open/save. Хранится в
/// `DocumentSession.lastMetrics`; показывается в диалогах «Отчёт об открытии»
/// и «Статистика документа». Пустая структура при первом старте.
struct PerformanceMetrics: Equatable {
    var lastOpenMs: Double = 0
    var lastOpenBytes: Int = 0
    var lastSaveMs: Double = 0
    var lastSaveBytes: Int = 0

    var openThroughputMBps: Double {
        guard lastOpenMs > 0.001 else { return 0 }
        return (Double(lastOpenBytes) / 1_048_576.0) / (lastOpenMs / 1000.0)
    }
    var saveThroughputMBps: Double {
        guard lastSaveMs > 0.001 else { return 0 }
        return (Double(lastSaveBytes) / 1_048_576.0) / (lastSaveMs / 1000.0)
    }
}