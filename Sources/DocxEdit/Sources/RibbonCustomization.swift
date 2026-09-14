//
//  RibbonCustomization.swift
//  DocxEdit (v1.2.0)
//
//  Каталог групп и команд ribbon для системы пользовательской настройки:
//  - RibbonGroupDef  — все группы всех вкладок (id, название, вкладка);
//    пользователь может скрыть любую (AppPreferences.hiddenRibbonGroups).
//  - RibbonCommandDef — каталог команд для группы «Избранное» на «Главной»
//    (AppPreferences.ribbonFavorites — упорядоченный список id).
//
//  Каталог — единственный источник истины для RibbonCustomizeView (диалог
//  настройки) и RibbonView (рендер). Новые группы/команды добавлять сюда.
//

import SwiftUI
import AppKit

// MARK: - Группы

struct RibbonGroupDef: Identifiable {
    let id: String        // "home.font"
    let title: String     // «Шрифт»
    let tab: String       // «Главная» — для секций в диалоге настройки

    static let all: [RibbonGroupDef] = [
        // Главная
        .init(id: "home.clipboard",  title: "Буфер обмена",  tab: "Главная"),
        .init(id: "home.font",       title: "Шрифт",         tab: "Главная"),
        .init(id: "home.paragraph",  title: "Абзац",         tab: "Главная"),
        .init(id: "home.styles",     title: "Стили",         tab: "Главная"),
        .init(id: "home.editing",    title: "Редактирование", tab: "Главная"),
        // Вставка
        .init(id: "insert.illustrations", title: "Иллюстрации", tab: "Вставка"),
        .init(id: "insert.links",         title: "Ссылки",      tab: "Вставка"),
        .init(id: "insert.tables",        title: "Таблицы",     tab: "Вставка"),
        .init(id: "insert.references",    title: "Оглавление и сноски", tab: "Вставка"),
        .init(id: "insert.symbols",       title: "Символы",     tab: "Вставка"),
        // Разметка
        .init(id: "layout.breaks",  title: "Разрывы",     tab: "Разметка"),
        .init(id: "layout.headers", title: "Колонтитулы", tab: "Разметка"),
        // Таблица
        .init(id: "table.rows",  title: "Строки и столбцы", tab: "Таблица"),
        .init(id: "table.cells", title: "Ячейки",           tab: "Таблица"),
        .init(id: "table.props", title: "Свойства",         tab: "Таблица"),
        // Обзор
        .init(id: "review.spelling", title: "Правописание", tab: "Обзор"),
        .init(id: "review.comments", title: "Комментарии",  tab: "Обзор"),
        .init(id: "review.changes",  title: "Правки",       tab: "Обзор"),
        .init(id: "review.subst",    title: "Замены",       tab: "Обзор"),
        .init(id: "review.reports",  title: "Отчёты",       tab: "Обзор"),
        // Вид
        .init(id: "view.mode", title: "Режим",    tab: "Вид"),
        .init(id: "view.show", title: "Показать", tab: "Вид"),
        .init(id: "view.panels", title: "Панели", tab: "Вид"),
        .init(id: "view.zoom", title: "Масштаб",  tab: "Вид"),
    ]

    static func groups(forTab tab: String) -> [RibbonGroupDef] {
        all.filter { $0.tab == tab }
    }
}

// MARK: - Команды «Избранного»

struct RibbonCommandDef: Identifiable {
    let id: String
    let title: String
    let symbol: String   // SF Symbol
    let run: @MainActor (DocumentController, AppDelegate) -> Void

    /// Каталог команд, доступных для добавления в «Избранное».
    /// Порядок каталога = порядок отображения выбранных в группе.
    /// v1.8.0: используется также командной палитрой (⌘⇧P) — поиск по title.
    static let all: [RibbonCommandDef] = [
        // v1.8.0: файловые операции (не в «Избранное» ribbon, но в палитре нужны).
        .init(id: "new",         title: "Новый документ",   symbol: "doc.badge.plus") { _, a in a.newDocument() },
        .init(id: "newMD",       title: "Новый Markdown",   symbol: "m.square") { _, a in a.newMarkdownDocument() },
        .init(id: "open",        title: "Открыть…",         symbol: "folder") { _, a in a.openDocument() },
        .init(id: "save",        title: "Сохранить",        symbol: "arrow.down.doc") { _, a in a.saveDocument() },
        .init(id: "saveAs",      title: "Сохранить как…",   symbol: "arrow.down.doc.on.rectangle") { _, a in a.saveDocumentAs() },
        .init(id: "exportDOCX",  title: "Экспорт в DOCX…",  symbol: "doc.richtext") { _, a in a.exportDOCX() },
        .init(id: "exportRTF",   title: "Экспорт в RTF…",   symbol: "doc.plaintext") { _, a in a.exportRTF() },
        .init(id: "exportMD",    title: "Экспорт в Markdown…", symbol: "text.alignleft") { _, a in a.exportMarkdown() },
        .init(id: "exportTXT",   title: "Экспорт в TXT…",   symbol: "text.quote") { _, a in a.exportTXT() },
        .init(id: "exportODT",   title: "Экспорт в ODT…",   symbol: "doc") { _, a in a.exportODT() },
        .init(id: "preferences", title: "Настройки…",       symbol: "gear") { _, _ in NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) },
        // Форматирование (публикуют notifications — исполняет Coordinator key window).
        .init(id: "bold",        title: "Полужирный",       symbol: "bold") { _, _ in NotificationCenter.default.post(name: .docxEditToggleBold, object: nil) },
        .init(id: "italic",      title: "Курсив",           symbol: "italic") { _, _ in NotificationCenter.default.post(name: .docxEditToggleItalic, object: nil) },
        .init(id: "underline",   title: "Подчёркнутый",     symbol: "underline") { _, _ in NotificationCenter.default.post(name: .docxEditToggleUnderline, object: nil) },
        .init(id: "strike",      title: "Зачёркнутый",      symbol: "strikethrough") { _, _ in NotificationCenter.default.post(name: .docxEditToggleStrikethrough, object: nil) },
        .init(id: "clearFmt",    title: "Очистить форматирование", symbol: "clear") { _, _ in NotificationCenter.default.post(name: .docxEditClearFormatting, object: nil) },
        // Панели (toggle).
        .init(id: "navigator",   title: "Навигатор",        symbol: "list.bullet.indent") { c, _ in c.toggleNavigatorSidebar() },
        .init(id: "stylesPanel", title: "Панель стилей",    symbol: "list.bullet.rectangle.portrait") { c, _ in c.toggleStylesSidebar() },
        .init(id: "commentsPanel", title: "Панель комментариев", symbol: "bubble.left.and.bubble.right") { c, _ in c.toggleCommentsSidebar() },
        .init(id: "footnotesPanel", title: "Панель сносок", symbol: "text.append") { c, _ in c.toggleFootnotesSidebar() },
        // Вид.
        .init(id: "pageView",    title: "Вид страницы (переключить)", symbol: "doc.richtext") { c, _ in c.togglePageView() },
        .init(id: "zoomIn",      title: "Увеличить масштаб", symbol: "plus.magnifyingglass") { c, _ in c.zoomIn() },
        .init(id: "zoomOut",     title: "Уменьшить масштаб", symbol: "minus.magnifyingglass") { c, _ in c.zoomOut() },
        .init(id: "zoom100",     title: "Масштаб 100%",     symbol: "1.magnifyingglass") { c, _ in c.setZoom(1.0) },
        .init(id: "fitWidth",    title: "По ширине страницы", symbol: "arrow.left.and.right") { c, _ in c.fitPageWidth() },
        // Остальные — как раньше.
        .init(id: "pageBreak",   title: "Разрыв страницы",  symbol: "arrow.turn.up.right") { c, _ in c.insertPageBreak() },
        .init(id: "headerFooter", title: "Колонтитулы…",    symbol: "rectangle.topthird.inset.filled") { _, a in a.showHeaderFooter() },
        .init(id: "pageNumbers", title: "Номера страниц",   symbol: "number.circle") { _, a in a.togglePageNumbers() },
        .init(id: "toc",         title: "Оглавление",       symbol: "list.bullet.rectangle") { _, a in a.insertTOC() },
        .init(id: "bookmark",    title: "Закладка…",        symbol: "bookmark") { _, a in a.showBookmarks() },
        .init(id: "crossref",    title: "Перекрёстная ссылка…", symbol: "arrow.triangle.branch") { _, a in a.showCrossReference() },
        .init(id: "hyperlink",   title: "Гиперссылка…",     symbol: "link") { _, a in a.showHyperlink() },
        .init(id: "footnote",    title: "Сноска…",          symbol: "text.append") { _, a in a.insertFootnote() },
        .init(id: "comment",     title: "Комментарий",      symbol: "text.bubble") { _, a in a.insertCommentAtSelection() },
        .init(id: "image",       title: "Изображение…",     symbol: "photo") { _, a in a.insertImage() },
        .init(id: "table",       title: "Таблица…",         symbol: "tablecells") { _, a in a.insertTable() },
        .init(id: "symbol",      title: "Символ…",          symbol: "character") { _, a in a.showSymbol() },
        .init(id: "print",       title: "Печать…",          symbol: "printer") { _, a in a.printDocument() },
        .init(id: "exportPDF",   title: "Экспорт в PDF…",   symbol: "doc.badge.arrow.up") { _, a in a.exportPDF() },
        .init(id: "statistics",  title: "Статистика…",      symbol: "chart.bar.doc.horizontal") { _, a in a.showStatistics() },
        .init(id: "findReplace", title: "Расширенный поиск…", symbol: "text.magnifyingglass") { _, a in a.showFindReplace() },
        .init(id: "goTo",        title: "Перейти к…",       symbol: "arrow.right.doc.on.clipboard") { _, a in a.showGoTo() },
        .init(id: "paragraph",   title: "Абзац…",           symbol: "text.alignleft") { _, a in a.showParagraphIndents() },
        .init(id: "styles",      title: "Стили…",           symbol: "paintpalette") { _, a in a.showStyles() },
        .init(id: "fontReplace", title: "Заменить шрифты…", symbol: "textformat.abc") { _, a in a.showFontReplace() },
        .init(id: "readingMode", title: "Режим чтения",     symbol: "book") { _, a in a.toggleReadingMode() },
        .init(id: "trackChanges", title: "Записывать правки", symbol: "pencil.line") { _, a in a.toggleTrackChanges() },
        .init(id: "ruler",       title: "Линейка",          symbol: "ruler") { _, a in a.toggleRuler() },
        .init(id: "invisibles",  title: "Непечатаемые символы", symbol: "paragraphsign") { _, a in a.toggleInvisibleCharacters() },
    ]

    static func find(id: String) -> RibbonCommandDef? {
        all.first { $0.id == id }
    }
}
