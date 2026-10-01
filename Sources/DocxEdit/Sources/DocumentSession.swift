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
    /// v1.9.0: гибридный (Typora) рендер поверх исходника — тот же source-режим
    /// (текст = источник истины), но разметка вне блока с курсором скрыта.
    @Published var isMarkdownHybrid: Bool = false
    /// markdownSource соответствует модели (исходный текст файла или правки в source).
    /// false — модель правили визуально, исходник нужно пересобрать экспортом.
    private var markdownSourceIsCurrent = false

    /// Исходный текст открытого .md: source/гибрид показывают файл как есть,
    /// без пересборки через модель (она теряет задачи, нумерацию, пустые строки).
    func loadMarkdownSource(_ text: String) {
        markdownSource = text
        markdownSourceIsCurrent = true
    }

    private func refreshMarkdownSourceIfStale() {
        guard !markdownSourceIsCurrent else { return }
        markdownSource = MarkdownIO.exportMarkdown(bridge.model,
                                                   prettyTables: AppPreferences.shared.markdownPrettyTables)
        markdownSourceIsCurrent = true
    }

    /// Войти в исходный режим: экспорт текущей модели в Markdown.
    func enterMarkdownSourceMode() {
        guard mode == .markdown else { return }
        refreshMarkdownSourceIfStale()
        isMarkdownSourceMode = true
        isMarkdownSplitMode = false   // v1.8.3: split и source взаимоисключимы.
        isMarkdownHybrid = false
        attachedController?.refreshStatus()
    }

    /// v1.9.0: войти в гибридный режим (из любого MD-вида).
    func enterMarkdownHybridMode() {
        guard mode == .markdown else { return }
        if !isMarkdownSourceMode { enterMarkdownSourceMode() }
        isMarkdownHybrid = true
    }

    /// v1.8.3: включить split-режим (source | preview рядом).
    func enterMarkdownSplitMode() {
        guard mode == .markdown else { return }
        refreshMarkdownSourceIfStale()
        isMarkdownSourceMode = false
        isMarkdownHybrid = false
        isMarkdownSplitMode = true
    }
    func exitMarkdownSplitMode() { isMarkdownSplitMode = false }

    /// Правка исходника: текст + best-effort синхронизация модели
    /// (swift-markdown отказоустойчив к недописанному синтаксису).
    /// v1.8.3: если открыт split-режим, дополнительно обновляем attributedText
    /// — превью справа переверстается в реальном времени по мере правок слева.
    func applyMarkdownSource(_ text: String) {
        markdownSource = text
        markdownSourceIsCurrent = true
        if let model = try? MarkdownIO.importMarkdown(string: text) {
            bridge.replaceModel(model)
            if isMarkdownSplitMode {
                attributedText = model.toAttributedString(
                    defaultFont: preferredDefaultFont(),
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: bridge.model.pageSettings.usableWidthInPoints)
            }
            attachedController?.refreshStatus()
        }
        markDirty()
    }

    /// v1.8.3: split-режим MD — source слева, превью WYSIWYG справа
    /// (Typora-паттерн). Только для документов в mode == .markdown.
    /// Взаимоисключим с isMarkdownSourceMode: split = оба одновременно.
    @Published var isMarkdownSplitMode: Bool = false

    /// Выйти в WYSIWYG: перестроить attributedText из модели.
    func exitMarkdownSourceMode() {
        isMarkdownSourceMode = false
        isMarkdownHybrid = false
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

    /// Заголовок окна: имя файла. Индикатор «есть несохранённые изменения»
    /// — родная точка в traffic light (`window.isDocumentEdited`, ставится в
    /// `WindowCloseGuard.updateNSView`); дублировать через «*» в тайтле не нужно
    /// (v1.7.1 полировка: избыточная звёздочка убрана).
    var windowTitle: String {
        bridge.fileURL?.lastPathComponent ?? "Без имени"
    }

    /// v1.7.1: время последнего явного сохранения (⌘S / autorecover-restore).
    /// Используется для индикатора «Сохранено 2 мин назад» в статусбаре.
    @Published var lastSavedAt: Date? = nil

    /// v1.8.0: обратная ссылка на контроллер окна, заполняется в
    /// `DocumentController.attach(session:)`. Нужна командной палитре, чтобы
    /// исполнить run-closures, которым требуется прямой доступ к DocumentController
    /// (toggle sidebars, zoom, insertPageBreak и т.п.). Weak — контроллер живёт
    /// в @StateObject окна, а session — в другом; циклов нет, но защищаемся.
    weak var attachedController: DocumentController?

    /// Помечает документ сохранённым по URL. Явно уведомляет наблюдателей —
    /// `NSDocumentBridge` это class, мутация его полей не триггерит `@Published`.
    func markSaved(url: URL) {
        objectWillChange.send()
        bridge.fileURL = url
        bridge.isDirty = false
        lastSavedAt = Date()
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
        isMarkdownHybrid = false
        markdownSource = ""
        markdownSourceIsCurrent = false
        self.attributedText = bridge.model.toAttributedString(
            defaultFont: preferredDefaultFont(),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first,
            usableWidth: bridge.model.pageSettings.usableWidthInPoints)
        // v1.8.7: явно взводим авто-фит только на реальную замену документа
        // (ранее это делала ветка re-sync в updateNSView, но она могла
        // срабатывать повторно и отматывать пользовательский зум — см. баг 2).
        attachedController?.pendingInitialFit = true
    }

    /// Полный сброс на пустой документ.
    func reset() {
        self.bridge = .empty
        self.mode = AppPreferences.shared.newDocumentMode
        isMarkdownSourceMode = false
        isMarkdownHybrid = false
        markdownSource = ""
        markdownSourceIsCurrent = false
        self.attributedText = bridge.model.toAttributedString(
            defaultFont: preferredDefaultFont(),
            fallbackFontName: AppPreferences.shared.favoriteFonts.first,
            usableWidth: bridge.model.pageSettings.usableWidthInPoints)
        attachedController?.pendingInitialFit = true
    }

    /// Применяет новое attributed-представление (после правки пользователем в NSTextView).
    /// Перестраивает DocumentModel из attributed и помечает как «грязный».
    /// **Сохраняет из старой модели `pageSettings`, `metadata`, `styles`** — они не
    /// восстанавливаются из attributed string и раньше сбрасывались на дефолт при
    /// любой правке: терялись пользовательские настройки страницы, метаданные и
    /// override стандартных стилей (баг #6 фидбека v0.1.36 — override стиля в
    /// диалоге «Стили…» сбрасывался при следующей же правке текста).
    func applyAttributed(_ attributed: NSAttributedString) {
        markdownSourceIsCurrent = false
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
        // v1.6.2: YAML front-matter тоже переживает пересборку из attributed.
        newModel.yamlFrontMatter = bridge.model.yamlFrontMatter
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