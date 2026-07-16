//
//  DocxEditApp.swift
//  DocxEdit
//
//  v0.1.4: Open Recent, About-панель, меню выравнивания, Preferences, иконка.
//

import SwiftUI
import AppKit
import DocxCore
import DocxIO
import RtfIO
import MarkdownIO
import PdfExporter
import EncodingDetector

// MARK: - App

@main
struct DocxEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let session = DocumentSession()

    var body: some Scene {
        WindowGroup("DocxEdit", id: "main") {
            DocumentWindowView()
                .environmentObject(session)
                .environmentObject(appDelegate)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    appDelegate.session = session
                    appDelegate.openInitialDocumentFromCommandLine()
                }
        }
        // v0.1.48: строка быстрого доступа встроена в системный title bar
        // (см. .toolbar в DocumentWindowView). unifiedCompact — как в Mac-подобных редакторов.
        .windowToolbarStyle(.unifiedCompact)
        Settings {
            PreferencesView()
        }
        .commands {
            // MARK: About
            CommandGroup(replacing: .appInfo) {
                Button("О DocxEdit") { showAboutPanel() }
                Button("Проверить обновления…") { appDelegate.checkForUpdates() }
            }

            // MARK: File
            CommandGroup(replacing: .newItem) {
                Button("Новый")     { appDelegate.newDocument() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Открыть…") { appDelegate.openDocument() }
                    .keyboardShortcut("o", modifiers: .command)

                // Open Recent — нативный механизм NSDocumentController
                RecentFilesMenu(appDelegate: appDelegate)

                Divider()

                Button("Сохранить")       { appDelegate.saveDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Сохранить как…") { appDelegate.saveDocumentAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Menu("Экспортировать в") {
                    Button("PDF…")      { appDelegate.exportPDF() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("DOCX…")    { appDelegate.exportDOCX() }
                    Button("Markdown…"){ appDelegate.exportMarkdown() }
                    Button("RTF…")     { appDelegate.exportRTF() }
                    Button("ODT…")     { appDelegate.exportODT() }
                    Button("Обычный текст (TXT)…") { appDelegate.exportTXT() }
                }

                Divider()

                Button("Свойства документа…") { appDelegate.showDocumentProperties() }

                Divider()

                Button("Печать…") { appDelegate.printDocument() }
                    .keyboardShortcut("p", modifiers: .command)
            }

            // MARK: Edit — поиск
            CommandGroup(after: .pasteboard) {
                Button("Вставить с сохранением стиля") { appDelegate.pasteAsPlainText() }
                    .keyboardShortcut("v", modifiers: [.command, .shift, .option])
                Divider()
                Button("Найти…")    { appDelegate.findInDocument() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Заменить…") { appDelegate.replaceInDocument() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Расширенный поиск…") { appDelegate.showFindReplace() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Перейти к…") { appDelegate.showGoTo() }
                    .keyboardShortcut("g", modifiers: [.command, .option])
            }

            // MARK: Format — отдельное меню «Формат» в строке меню (как в Mac-подобных редакторов).
            // Раньше блок жил в CommandGroup(replacing: .toolbar), из-за чего все
            // команды форматирования сваливались в системный «Вид» (там раздел
            // Toolbar — Show/Hide Toolbar). Итог: меню «Вид» переполнено, меню
            // «Формат» отсутствует. Решение — свой CommandMenu.
            CommandMenu("Формат") {
                Button("Жирный")       { appDelegate.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Курсив")       { appDelegate.toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Подчёркнутый") { appDelegate.toggleUnderline() }
                    .keyboardShortcut("u", modifiers: .command)
                Divider()
                Button("По левому краю")  { appDelegate.applyAlignment(.left) }
                    .keyboardShortcut("{", modifiers: .command)
                Button("По центру")       { appDelegate.applyAlignment(.center) }
                    .keyboardShortcut("|", modifiers: .command)
                Button("По правому краю") { appDelegate.applyAlignment(.right) }
                    .keyboardShortcut("}", modifiers: .command)
                Button("По ширине")       { appDelegate.applyAlignment(.justified) }
                    .keyboardShortcut("}", modifiers: [.command, .option])
                Divider()
                Button("Зачёркнутый") { appDelegate.toggleStrikethrough() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Надстрочный") { appDelegate.toggleSuperscript() }
                    .keyboardShortcut("=", modifiers: [.command, .control])
                Button("Подстрочный") { appDelegate.toggleSubscript() }
                    .keyboardShortcut("-", modifiers: [.command, .control])
                Menu("Регистр") {
                    Button("ВЕРХНИЙ") { appDelegate.changeCase("upper") }
                    Button("нижний")   { appDelegate.changeCase("lower") }
                    Button("Каждое Слово С Заглавной") { appDelegate.changeCase("title") }
                    Button("Как в предложениях") { appDelegate.changeCase("sentence") }
                    Button("иНВЕРТИРОВАТЬ рЕГИСТР") { appDelegate.changeCase("toggle") }
                }
                Divider()
                Menu("Межстрочный интервал") {
                    Button("Одинарный (1.0)") { appDelegate.applyLineSpacing(1.0) }
                    Button("1.15")            { appDelegate.applyLineSpacing(1.15) }
                    Button("Полуторный (1.5)") { appDelegate.applyLineSpacing(1.5) }
                    Button("Двойной (2.0)")   { appDelegate.applyLineSpacing(2.0) }
                }
                Divider()
                Button("Маркированный список")  { appDelegate.toggleList(.bulleted) }
                Button("Нумерованный список")   { appDelegate.toggleList(.numbered) }
                Menu("Многоуровневый список") {
                    ForEach(MultilevelListVariant.presets.filter { $0.listType == .numbered }) { v in
                        Button(v.title) { appDelegate.applyListVariant(v.id) }
                    }
                    Divider()
                    ForEach(MultilevelListVariant.presets.filter { $0.listType == .bulleted }) { v in
                        Button(v.title) { appDelegate.applyListVariant(v.id) }
                    }
                }
                Divider()
                Menu("Стиль") {
                    Button("Обычный")     { appDelegate.applyParagraphStyle("Normal")   }
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    Divider()
                    Button("Заголовок 1") { appDelegate.applyParagraphStyle("Heading1") }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("Заголовок 2") { appDelegate.applyParagraphStyle("Heading2") }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("Заголовок 3") { appDelegate.applyParagraphStyle("Heading3") }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                    Button("Заголовок 4") { appDelegate.applyParagraphStyle("Heading4") }
                        .keyboardShortcut("4", modifiers: [.command, .option])
                    Button("Заголовок 5") { appDelegate.applyParagraphStyle("Heading5") }
                        .keyboardShortcut("5", modifiers: [.command, .option])
                    Button("Заголовок 6") { appDelegate.applyParagraphStyle("Heading6") }
                        .keyboardShortcut("6", modifiers: [.command, .option])
                }
                Menu("Стиль знака") {
                    Button("Сильное (Strong)")   { appDelegate.applyCharacterStyle("Strong")   }
                    Button("Выделение (Emphasis)") { appDelegate.applyCharacterStyle("Emphasis") }
                    Button("Код (Code)")         { appDelegate.applyCharacterStyle("CodeChar") }
                    Divider()
                    Button("Убрать стиль знака") { appDelegate.applyCharacterStyle(nil) }
                }
                Button("Стили…") { appDelegate.showStyles() }
                    .keyboardShortcut("s", modifiers: [.command, .option, .shift])
                Divider()
                Button("Увеличить отступ") { appDelegate.increaseIndent() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Уменьшить отступ") { appDelegate.decreaseIndent() }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button("Копировать формат") { appDelegate.copyFormatting() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Вставить формат") { appDelegate.pasteFormatting() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Divider()
                Button("Очистить форматирование") { appDelegate.clearFormatting() }
                    .keyboardShortcut(" ", modifiers: .command)
                Divider()
                Menu("Цвет подсветки") {
                    Button("Жёлтый ▓")       { appDelegate.applyHighlight(NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)) }
                    Button("Ярко-зелёный ▓") { appDelegate.applyHighlight(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)) }
                    Button("Голубой ▓")      { appDelegate.applyHighlight(NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)) }
                    Button("Розовый ▓")      { appDelegate.applyHighlight(NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)) }
                    Button("Красный ▓")      { appDelegate.applyHighlight(NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1)) }
                    Divider()
                    Button("Без подсветки")  { appDelegate.applyHighlight(nil) }
                }
                Button("Заменить шрифты…") { appDelegate.showFontReplace() }
                Divider()
                Button("Абзац…") { appDelegate.showParagraphIndents() }
            }

            // MARK: Вид — вид страницы, непечатаемые, масштаб (в подменю).
            // Вливаемся в системный «Вид» SwiftUI (Toolbar/Full Screen уже там).
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Вид страницы") { appDelegate.togglePageView() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Непечатаемые символы") { appDelegate.toggleInvisibleCharacters() }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Линейка") { appDelegate.toggleRuler() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Панель стилей") { appDelegate.toggleStylesSidebar() }
                Button("Панель комментариев") { appDelegate.toggleCommentsSidebar() }
                Button("Панель сносок") { appDelegate.toggleFootnotesSidebar() }
                Button("Режим чтения") { appDelegate.toggleReadingMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Menu("Масштаб") {
                    Button("Увеличить")    { appDelegate.zoomIn() }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("Уменьшить")    { appDelegate.zoomOut() }
                        .keyboardShortcut("-", modifiers: .command)
                    Button("Реальный размер (100%)") { appDelegate.zoomReset() }
                        .keyboardShortcut("0", modifiers: .command)
                    Divider()
                    Button("По ширине страницы") { appDelegate.fitPageWidth() }
                    Button("Две страницы")       { appDelegate.fitTwoPages() }
                }
            }

            // MARK: Вставка — таблица, разрыв страницы (⌘⏎), колонтитулы
            CommandMenu("Вставка") {
                Button("Гиперссылка…") { appDelegate.showHyperlink() }
                Button("Закладка…") { appDelegate.showBookmarks() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Комментарий") { appDelegate.insertCommentAtSelection() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                // v0.5.3 (R07): сноска. Шорткат — как в Mac-подобных редакторов.
                Button("Сноска…") { appDelegate.insertFootnote() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                // v0.5.5/6 (R07): TOC + перекрёстные ссылки.
                Divider()
                Button("Оглавление") { appDelegate.insertTOC() }
                Button("Обновить оглавление") { appDelegate.updateTOC() }
                Button("Перекрёстная ссылка…") { appDelegate.showCrossReference() }
                Divider()
                Button("Изображение…") { appDelegate.insertImage() }
                Button("Свойства изображения…") { appDelegate.showImageProperties() }
                Button("Обрезать изображение…") { appDelegate.showImageCrop() }
                Divider()
                Button("Таблица…") { appDelegate.insertTable() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Menu("Изменить таблицу") {
                    Button("Добавить строку выше") { appDelegate.tableAddRowAbove() }
                    Button("Добавить строку ниже") { appDelegate.tableAddRowBelow() }
                    Divider()
                    Button("Добавить столбец слева") { appDelegate.tableAddColumnLeft() }
                    Button("Добавить столбец справа") { appDelegate.tableAddColumnRight() }
                    Divider()
                    Button("Объединить ячейки…") { appDelegate.tableMergeCells() }
                    Button("Разделить ячейку") { appDelegate.tableSplitCell() }
                    Divider()
                    Button("Строка-заголовок таблицы") { appDelegate.tableToggleHeaderRow() }
                    Button("Высота строки…") { appDelegate.tableShowRowHeight() }
                    Divider()
                    Button("Удалить строку") { appDelegate.tableDeleteRow() }
                    Button("Удалить столбец") { appDelegate.tableDeleteColumn() }
                    Button("Удалить таблицу") { appDelegate.tableDeleteTable() }
                }
                Button("Свойства таблицы…") { appDelegate.showTableProperties() }
                Divider()
                Button("Разрыв страницы") { appDelegate.insertPageBreak() }
                    .keyboardShortcut(.return, modifiers: .command)
                Menu("Разрыв раздела") {
                    Button("Следующая страница") { appDelegate.insertPageBreak() }
                    Button("Непрерывный")         { appDelegate.insertPageBreak() }
                    Button("Чётная страница")     { appDelegate.insertPageBreak() }
                    Button("Нечётная страница")   { appDelegate.insertPageBreak() }
                }
                Divider()
                Button("Номера страниц") { appDelegate.togglePageNumbers() }
                Button("Колонтитулы…") { appDelegate.showHeaderFooter() }
                Divider()
                Button("Символ…") { appDelegate.showSymbol() }
                Menu("Дата и время") {
                    Button("Дата") { appDelegate.insertDateTime("date") }
                    Button("Время") { appDelegate.insertDateTime("time") }
                    Button("Дата и время") { appDelegate.insertDateTime("datetime") }
                }
                Menu("Специальные знаки") {
                    Button("Длинное тире (—)") { appDelegate.insertText("—") }
                    Button("Короткое тире (–)") { appDelegate.insertText("–") }
                    Button("Многоточие (…)") { appDelegate.insertText("…") }
                    Divider()
                    Button("Неразрывный пробел") { appDelegate.insertText("\u{00A0}") }
                    Button("Тонкий пробел") { appDelegate.insertText("\u{2009}") }
                    Divider()
                    Button("Знак © (Copyright)") { appDelegate.insertText("©") }
                    Button("Знак ® (Registered)") { appDelegate.insertText("®") }
                    Button("Знак ™ (Trademark)") { appDelegate.insertText("™") }
                    Button("Знак § (Section)") { appDelegate.insertText("§") }
                    Button("Знак ¶ (Paragraph)") { appDelegate.insertText("¶") }
                }
            }

            // MARK: Инструменты — статистика, правописание, отчёт об открытии
            CommandMenu("Инструменты") {
                Button("Статистика документа…") { appDelegate.showStatistics() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Button("Правописание и грамматика…") { appDelegate.reviewCheckSpelling() }
                    .keyboardShortcut(":", modifiers: [.command])
                Button("Пользовательский словарь…") { appDelegate.showCustomDictionary() }
                Divider()
                Menu("Отслеживание правок") {
                    Button("Записывать правки") { appDelegate.toggleTrackChanges() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Divider()
                    Button("Следующая правка") { appDelegate.goToNextRevision() }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                    Button("Принять правку под курсором")   { appDelegate.acceptCurrentRevision() }
                    Button("Отклонить правку под курсором") { appDelegate.rejectCurrentRevision() }
                    Divider()
                    Button("Принять все правки")   { appDelegate.acceptAllChanges() }
                    Button("Отклонить все правки") { appDelegate.rejectAllChanges() }
                }
                Divider()
                Button("Отчёт об открытии…") { appDelegate.showImportReport() }
            }
        }
    }
}

// MARK: - О программе (панель About с changelog последних релизов)

/// Данные последних релизов для панели About. Обновляется вручную при каждом релизе
/// (синхронно с §5 «История релизов» в CLAUDE.md).
enum AboutReleaseNotes {
    static let recent: [(version: String, codename: String, summary: String)] = [
        ("1.1.0", "GitHub Publishing & Auto-Update", "R11 — публикация релизов на GitHub и встроенный auto-updater. **Часть A (публикация)**: `scripts/publish-github.sh` — обёртка над `gh` CLI, создаёт GitHub Release, аплоадит `.dmg`/`.app.zip`/`SHA256SUMS`, ротация — оставляет последние `KEEP_RELEASES` (по умолчанию 3), удаляя старые Releases (git-теги сохраняются). `scripts/release.sh` вызывает publish автоматически; флаг `--no-publish` пропускает. Идемпотентно (повторный запуск с той же версией = `gh release upload --clobber`). **Часть B (auto-updater)**: `Sources/DocxEdit/Sources/UpdaterEngine.swift` + `UpdateNotificationView.swift` — при запуске (через 2 сек, чтобы не блокировать splash) дёргает `api.github.com/repos/tolan2005/DocxEdit/releases/latest`, парсит `tag_name`, сравнивает semver с текущей `CFBundleShortVersionString`. Если новее — banner-окно с release notes и кнопками «Установить сейчас / Позже / Пропустить эту версию». Установка: скачивание `.dmg` в temp через `URLSession.download`, обязательная SHA256-верификация против `SHA256SUMS` (при несовпадении — отказ, файл удаляется), `NSWorkspace.open(dmg)` — пользователь перетаскивает в /Applications вручную. Настройка «Проверять обновления» на вкладке «Основные»: При запуске / Раз в день / Раз в неделю / Никогда (default: При запуске). При «Никогда» — 0 сетевых запросов. Ручная проверка — меню DocxEdit → «Проверить обновления…». User-Agent строго `DocxEdit/<v> (macOS)` без ID машины. UI-паттерн — `NSWindow(contentRect:) + NSHostingView(sizingOptions:[])` (ADR-039 п.7). **Что НЕ сделано в v1.1.0** (post-1.2 задачи): прогресс-бар при загрузке (сейчас 0→1), in-place replace для `.app.zip` через helper-скрипт, кеш metadata на 1 час против rate-limit кластерного NAT, snapshot-тест `UpdateNotificationView`. Ограничения (в §7 known-limitations): требует Developer ID + нотаризацию для замены без Gatekeeper-варнинга (текущий ad-hoc-подписанный DMG будет предупреждать; см. R1 в REQUIREMENTS_AUTOUPDATE §8)."),
        ("1.0.0", "R10 Milestone — Public Release", "🎉 Первая публичная стабильная версия DocxEdit. Что вошло за R10 «Release»: (a) EN-локализация меню (v0.7.1, ~130 ключей) и всех SwiftUI-диалогов (v0.7.2, ~180 ключей) — итого ~300 переводов через LocalizedStringKey/Bundle.module без ручных обёрток над NSLocalizedString; (b) переписан `README.md` — English, покрывает архитектуру, сборку, тесты, известные ограничения; (c) актуализация статуса. **Что в 1.0.0 реализовано** (весь путь R01→R10): нативный macOS редактор с ribbon в стиле современных настольных текстовых процессоров; форматирование (B/I/U/S/sub/super, char/para styles, colors, highlight, format painter); структура (multilevel lists, tables с merge/split/borders, images HEIC/SVG с rotate/crop/wrap, hyperlinks, bookmarks, cross-refs, footnotes, section breaks, header/footer с variants, TOC как SDT); review (reading mode, comments с DOCX round-trip, track changes включая rPrChange); диагностика (Import Report, Performance metrics); I/O DOCX/DOC/RTF/ODT/MD/TXT/PDF; печать; auto-recovery; spell+grammar с auto-language; 204 XCTest теста через 5 таргетов, ~1.4 c. **Post-1.0 задачи** (осознанно): multi-doc tabs (нужен рефакторинг single-session), полный native ODT writer (сейчас — NSAttributedString bridge), настоящий `<w:fldChar w:instr=\"TOC\">` complex field, полное сохранение старых attrs в rPrChange, Developer ID signing + нотаризация (ad-hoc-подписанный DMG для сборки текущей). Оставшиеся ру-строки в редких дочерних view — правятся по мере обнаружения."),
        ("0.7.2", "R10b — Dialog Localization", "R10 «Release» продолжение — EN-перевод всех SwiftUI-диалогов. Добавлено ~180 переводов в `en.lproj/Localizable.strings` (общий счёт ключей ~300): Preferences (Основные/Шрифты/Страница/По умолчанию, вкладки и подписи), настройки страницы (пресеты полей, ориентация, зеркальные поля), свойства документа (Название/Автор/Тема/Ключевые слова/Язык), колонтитулы (Header/Footer/Different first page/Different odd-even), стили (Paragraph/Character, редактор атрибутов), диалог абзаца (отступы, First-line/Hanging, интервалы), таблица (Merge/Split, свойства, ширина/высота, Show borders), изображение (Alt text, Wrap, Rotate/Crop), Find & Replace (Whole word/Case sensitive/Regex), закладки и cross-refs, диалог символов, замена шрифтов, sidebars (Comments/Footnotes/Styles), Track Changes UI. Инженерная схема без правки Swift-кода: все SwiftUI-литералы уже — LocalizedStringKey, лишь пополняем словарь. Тесты: 202 всего, PASS."),
    ]
}

@MainActor
private func showAboutPanel() {
    let credits = NSMutableAttributedString()
    for entry in AboutReleaseNotes.recent {
        credits.append(NSAttributedString(
            string: "\(entry.version) — \(entry.codename)\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 11)]
        ))
        credits.append(NSAttributedString(
            string: "\(entry.summary)\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        ))
    }
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

// MARK: - Open Recent (динамическое подменю)

private struct RecentFilesMenu: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Menu("Недавние файлы") {
            if appDelegate.recentURLs.isEmpty {
                Text("Нет недавних файлов").foregroundStyle(.secondary)
            } else {
                ForEach(appDelegate.recentURLs, id: \.absoluteString) { url in
                    Button(url.lastPathComponent) {
                        appDelegate.loadFromURL(url)
                    }
                }
                Divider()
                Button("Очистить список") {
                    appDelegate.clearRecentFiles()
                }
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Сессия привязывается в `.onAppear` окна SwiftUI — позже, чем Finder может
    /// вызвать `application(_:open:)`. Поэтому при появлении сессии догружаем
    /// отложенный URL (см. `pendingOpenURL` / `loadFromURL`).
    var session: DocumentSession? {
        didSet {
            guard session != nil, let url = pendingOpenURL else { return }
            pendingOpenURL = nil
            loadFromURL(url)
        }
    }
    /// URL файла, который Finder попросил открыть до привязки сессии.
    private var pendingOpenURL: URL?
    @Published var recentURLs: [URL] = []

    private static let recentKey = "recentFilePaths"
    private static let maxRecent = 10

    private var didReorganizeMenus = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        loadRecentURLs()
        openInitialDocumentFromCommandLine()
        // v0.3.4: показ диалога восстановления, если предыдущий сеанс упал.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.presentAutorecoverIfNeeded()
        }
        // SwiftUI собирает `NSApp.mainMenu` не в applicationDidFinishLaunching
        // (там его ещё нет), а к моменту показа первого окна. Наблюдаем за
        // окном и переносим системные пункты Правка → Вставка один раз.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        // v1.1.0: автопроверка обновлений (тихая, соблюдает настройку «Никогда»).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UpdaterEngine.shared.checkOnLaunchIfNeeded()
        }
        // Наблюдаем за появлением availableUpdate — показываем banner-окно.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("docxEditUpdateAvailable"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.presentUpdateBannerIfAny()
        }
        // UpdaterEngine — ObservableObject; подписка на @Published через Combine
        // конфликтует с @MainActor init'ом, поэтому используем KVO-free тикер:
        // раз в 5 сек смотрим availableUpdate и показываем окно, если появилось.
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.presentUpdateBannerIfAny() }
        }
    }

    @objc private func onWindowDidBecomeMain(_ note: Notification) {
        guard !didReorganizeMenus else { return }
        // Дадим SwiftUI один runloop-круг до трогания меню.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didReorganizeMenus else { return }
            self.reorganizeMenusForInsertTab()
            self.didReorganizeMenus = true
        }
    }

    /// Переносит системные пункты «Автозаполнение», «Начать диктовку»,
    /// «Эмодзи и символы» из меню «Правка» в меню «Вставка» — как в мейнстрим-редакторов for
    /// Mac (пункт #4 фидбека). Одноразового удаления недостаточно: macOS
    /// автоматически ре-инжектит эти items каждый раз, когда меню становится
    /// активным. Поэтому ставим `NSMenuDelegate` на Правку и вычищаем items в
    /// `menuNeedsUpdate:`. В «Вставку» добавляем свои собственные NSMenuItem с
    /// теми же action-selectors — они работают через цепочку респондеров.
    func reorganizeMenusForInsertTab() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let editSubmenu = mainMenu.item(withTitle: "Правка")?.submenu
            ?? mainMenu.item(withTitle: "Edit")?.submenu
        let insertSubmenu = mainMenu.item(withTitle: "Вставка")?.submenu
            ?? mainMenu.item(withTitle: "Insert")?.submenu
        guard let editMenu = editSubmenu, let insertMenu = insertSubmenu else { return }

        // 1) Добавляем свои копии в «Вставка» через селекторы (action route до NSTextView).
        insertMenu.addItem(NSMenuItem.separator())
        let emoji = NSMenuItem(title: "Эмодзи и символы",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " ")
        emoji.keyEquivalentModifierMask = [.command, .control]
        insertMenu.addItem(emoji)
        let dictation = NSMenuItem(title: "Начать диктовку",
            action: NSSelectorFromString("startDictation:"),
            keyEquivalent: "")
        insertMenu.addItem(dictation)

        // 2) Вешаем делегата на Правку, который чистит ре-инжект от AppKit.
        let del = EditMenuCleanupDelegate()
        editMenu.delegate = del
        editMenuCleanupDelegate = del
        del.menuNeedsUpdate(editMenu)   // первичная чистка
    }
    private var editMenuCleanupDelegate: EditMenuCleanupDelegate?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func openInitialDocumentFromCommandLine() {
        for arg in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
               !isDir.boolValue, hasSupportedExtension(url) {
                DispatchQueue.main.async { [weak self] in self?.loadFromURL(url) }
                return
            }
        }
    }

    // MARK: Finder

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        loadFromURL(first)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        loadFromURL(URL(fileURLWithPath: filename)); return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { loadFromURL(URL(fileURLWithPath: first)) }
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: Действия меню — файл

    func newDocument() {
        let ps = AppPreferences.shared.defaultPageSettings
        let model = DocumentModel(pageSettings: ps)
        let bridge = NSDocumentBridge(model: model)
        session?.replace(with: bridge)
    }

    /// v0.3.4: сканирует autorecover-директорию на файлы, оставшиеся с
    /// предыдущего сеанса (крах / принудительное завершение). Показывает
    /// системный alert с выбором: восстановить документ (open .json как
    /// DocumentModel) или отбросить (удалить файл).
    func presentAutorecoverIfNeeded() {
        let dir = DocumentController.autorecoverDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]),
              !entries.isEmpty else { return }
        let files = entries.filter { $0.pathExtension == "json" }
        guard !files.isEmpty else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        let alert = NSAlert()
        alert.messageText = "Восстановление документов"
        alert.informativeText = "Найдено \(sorted.count) автосохранённых копий с прошлого сеанса. Восстановить?"
        alert.addButton(withTitle: "Восстановить")
        alert.addButton(withTitle: "Отбросить все")
        alert.addButton(withTitle: "Позже")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            // Восстанавливаем самую свежую читаемую копию; только её файл и удаляем.
            // Остальные копии остаются на диске — будут предложены при следующем
            // запуске (v0.4.1: раньше цикл удалял ВСЕ файлы, показав лишь первый, —
            // потеря данных при нескольких несохранённых документах).
            for url in sorted {
                guard let data = try? Data(contentsOf: url),
                      let model = try? JSONDecoder().decode(DocumentModel.self, from: data) else {
                    // Нечитаемый/несовместимый файл пропускаем и НЕ удаляем.
                    continue
                }
                let bridge = NSDocumentBridge(model: model)
                session?.replace(with: bridge)
                session?.markDirty()
                try? FileManager.default.removeItem(at: url)
                break
            }
        } else if resp == .alertSecondButtonReturn {
            for url in sorted { try? FileManager.default.removeItem(at: url) }
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "docx") ?? .data,
            .init(filenameExtension: "doc")  ?? .data,
            .init(filenameExtension: "rtf")  ?? .data,
            .init(filenameExtension: "md")   ?? .data,
            .init(filenameExtension: "txt")  ?? .data,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { loadFromURL(url) }
    }

    func saveDocument() {
        if let url = session?.bridge.fileURL { saveToURL(url) } else { saveDocumentAs() }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = "Без имени.docx"
        if panel.runModal() == .OK, let url = panel.url { saveToURL(url) }
    }

    func exportPDF()      { exportDocument(format: .pdf) }
    func exportDOCX()     { exportDocument(format: .docx) }
    func exportMarkdown() { exportDocument(format: .markdown) }
    func exportRTF()      { exportDocument(format: .rtf) }
    func exportTXT()      { exportDocument(format: .txt) }
    func exportODT()      { exportDocument(format: .odt) }

    func printDocument() {
        NotificationCenter.default.post(name: .docxEditPrint, object: nil)
    }

    func showFontReplace() {
        NotificationCenter.default.post(name: .docxEditShowFontReplace, object: nil)
    }

    // MARK: - Auto-Update (v1.1.0)

    private var updateWindow: NSWindow?

    /// Ручная проверка обновлений через меню DocxEdit → «Проверить обновления…».
    func checkForUpdates() {
        UpdaterEngine.shared.checkNow()
        // Через 3 сек — если появилась ошибка/нет обновлений, покажем алерт.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            if UpdaterEngine.shared.availableUpdate != nil {
                self.presentUpdateBannerIfAny()
            } else if let err = UpdaterEngine.shared.lastError {
                let alert = NSAlert()
                alert.messageText = "Обновление"
                alert.informativeText = err
                alert.runModal()
                UpdaterEngine.shared.lastError = nil
            }
        }
    }

    /// Показать banner-окно, если UpdaterEngine нашёл обновление.
    /// Идемпотентно — не открывает второе окно, если одно уже висит.
    @MainActor
    func presentUpdateBannerIfAny() {
        guard let release = UpdaterEngine.shared.availableUpdate else { return }
        if let w = updateWindow, w.isVisible { return }

        let view = UpdateNotificationView(
            release: release,
            onInstall: { [weak self] in self?.closeUpdateWindow() },
            onLater:   { [weak self] in
                UpdaterEngine.shared.dismissCurrentAvailable()
                self?.closeUpdateWindow()
            },
            onSkip:    { [weak self] in
                UpdaterEngine.shared.skipCurrentAvailable()
                self?.closeUpdateWindow()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Обновление доступно"
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.updateWindow = win
    }

    private func closeUpdateWindow() {
        updateWindow?.orderOut(nil)
        updateWindow = nil
    }

    // MARK: Действия меню — правка

    func findInDocument()    { NotificationCenter.default.post(name: .docxEditShowFind,    object: nil) }
    func replaceInDocument() { NotificationCenter.default.post(name: .docxEditShowReplace, object: nil) }
    func showGoTo()          { NotificationCenter.default.post(name: .docxEditShowGoTo,    object: nil) }

    // MARK: Действия меню — формат

    func toggleBold()          { NotificationCenter.default.post(name: .docxEditToggleBold,          object: nil) }
    func toggleItalic()        { NotificationCenter.default.post(name: .docxEditToggleItalic,        object: nil) }
    func toggleUnderline()     { NotificationCenter.default.post(name: .docxEditToggleUnderline,     object: nil) }
    func toggleStrikethrough() { NotificationCenter.default.post(name: .docxEditToggleStrikethrough, object: nil) }
    func toggleSuperscript()   { NotificationCenter.default.post(name: .docxEditToggleSuperscript,   object: nil) }
    func toggleSubscript()     { NotificationCenter.default.post(name: .docxEditToggleSubscript,     object: nil) }
    func changeCase(_ mode: String) { NotificationCenter.default.post(name: .docxEditChangeCase, object: NSString(string: mode)) }
    func copyFormatting()  { NotificationCenter.default.post(name: .docxEditCopyFormatting,  object: nil) }
    func pasteFormatting() { NotificationCenter.default.post(name: .docxEditPasteFormatting, object: nil) }
    /// nil = снять подсветку.
    func applyHighlight(_ color: NSColor?) { NotificationCenter.default.post(name: .docxEditApplyHighlight, object: color) }
    func clearFormatting()     { NotificationCenter.default.post(name: .docxEditClearFormatting,     object: nil) }
    func zoomIn()              { NotificationCenter.default.post(name: .docxEditZoomIn,              object: nil) }
    func zoomOut()             { NotificationCenter.default.post(name: .docxEditZoomOut,             object: nil) }
    func zoomReset()           { NotificationCenter.default.post(name: .docxEditZoomReset,           object: nil) }
    func fitPageWidth()        { NotificationCenter.default.post(name: .docxEditFitPageWidth,        object: nil) }
    func fitTwoPages()         { NotificationCenter.default.post(name: .docxEditFitTwoPages,         object: nil) }
    func togglePageView()      { NotificationCenter.default.post(name: .docxEditTogglePageView,      object: nil) }
    func togglePageNumbers()   { NotificationCenter.default.post(name: .docxEditTogglePageNumbers,   object: nil) }
    func showHeaderFooter()    { NotificationCenter.default.post(name: .docxEditShowHeaderFooter,     object: nil) }
    func insertTable()         { NotificationCenter.default.post(name: .docxEditShowInsertTable,     object: nil) }
    func tableAddRowAbove()    { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "addRowAbove")) }
    func tableAddRowBelow()    { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "addRowBelow")) }
    func tableAddColumnLeft()  { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "addColumnLeft")) }
    func tableAddColumnRight() { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "addColumnRight")) }
    func tableDeleteRow()      { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "deleteRow")) }
    func tableDeleteColumn()   { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "deleteColumn")) }
    func tableDeleteTable()    { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "deleteTable")) }
    func tableMergeCells()     { NotificationCenter.default.post(name: .docxEditShowMergeCells, object: nil) }
    func tableSplitCell()      { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "splitCell")) }
    func tableToggleHeaderRow() { NotificationCenter.default.post(name: .docxEditTableEdit, object: NSString(string: "toggleHeaderRow")) }
    func tableShowRowHeight()   { NotificationCenter.default.post(name: .docxEditShowRowHeight, object: nil) }
    func showParagraphIndents() { NotificationCenter.default.post(name: .docxEditShowParagraphIndents, object: nil) }
    func showFindReplace()      { NotificationCenter.default.post(name: .docxEditShowFindReplace, object: nil) }
    func showImageCrop()        { NotificationCenter.default.post(name: .docxEditShowImageCrop, object: nil) }
    func showDocumentProperties() { NotificationCenter.default.post(name: .docxEditShowDocumentProperties, object: nil) }
    func showBookmarks()          { NotificationCenter.default.post(name: .docxEditShowBookmarks, object: nil) }
    func showCustomDictionary()   { NotificationCenter.default.post(name: .docxEditShowCustomDictionary, object: nil) }
    func showTableProperties() { NotificationCenter.default.post(name: .docxEditShowTableProperties, object: nil) }
    func insertImage()         { NotificationCenter.default.post(name: .docxEditInsertImage, object: nil) }
    func showImageProperties() { NotificationCenter.default.post(name: .docxEditShowImageProperties, object: nil) }
    func showHyperlink()       { NotificationCenter.default.post(name: .docxEditShowHyperlink, object: nil) }
    func insertFootnote()      { NotificationCenter.default.post(name: .docxEditInsertFootnote, object: nil) }
    func insertTOC()           { NotificationCenter.default.post(name: .docxEditInsertTOC, object: nil) }
    func updateTOC()           { NotificationCenter.default.post(name: .docxEditUpdateTOC, object: nil) }
    func showCrossReference()  { NotificationCenter.default.post(name: .docxEditShowCrossReference, object: nil) }
    func showSymbol()          { NotificationCenter.default.post(name: .docxEditShowSymbol, object: nil) }
    /// Тег: "date" / "time" / "datetime"
    func insertDateTime(_ kind: String) {
        NotificationCenter.default.post(name: .docxEditInsertDateTime, object: NSString(string: kind))
    }
    /// Одиночный символ / короткая строка для быстрой вставки из ribbon-меню.
    func insertText(_ text: String) {
        NotificationCenter.default.post(name: .docxEditInsertText, object: NSString(string: text))
    }
    func reviewCheckSpelling() { NotificationCenter.default.post(name: .docxEditCheckSpelling, object: nil) }
    func showImportReport()    { NotificationCenter.default.post(name: .docxEditShowImportReport, object: nil) }
    func toggleInvisibleCharacters() { NotificationCenter.default.post(name: .docxEditToggleInvisibles, object: nil) }
    func toggleRuler()               { NotificationCenter.default.post(name: .docxEditToggleRuler,      object: nil) }
    func toggleStylesSidebar()       { NotificationCenter.default.post(name: .docxEditToggleStylesSidebar, object: nil) }
    func toggleReadingMode()         { NotificationCenter.default.post(name: .docxEditToggleReadingMode,   object: nil) }
    func toggleCommentsSidebar()     { NotificationCenter.default.post(name: .docxEditToggleCommentsSidebar, object: nil) }
    func toggleFootnotesSidebar()    { NotificationCenter.default.post(name: .docxEditToggleFootnotesSidebar, object: nil) }
    func insertCommentAtSelection()  { NotificationCenter.default.post(name: .docxEditInsertComment,       object: nil) }
    func toggleTrackChanges()        { NotificationCenter.default.post(name: .docxEditToggleTrackChanges, object: nil) }
    func acceptAllChanges()          { NotificationCenter.default.post(name: .docxEditAcceptAllChanges,  object: nil) }
    func rejectAllChanges()          { NotificationCenter.default.post(name: .docxEditRejectAllChanges,  object: nil) }
    func goToNextRevision()          { NotificationCenter.default.post(name: .docxEditGoToNextRevision,   object: nil) }
    func acceptCurrentRevision()     { NotificationCenter.default.post(name: .docxEditAcceptCurrentRev, object: nil) }
    func rejectCurrentRevision()     { NotificationCenter.default.post(name: .docxEditRejectCurrentRev, object: nil) }
    func showStatistics()      { NotificationCenter.default.post(name: .docxEditShowStatistics,    object: nil) }

    func applyAlignment(_ alignment: NSTextAlignment) {
        NotificationCenter.default.post(
            name: .docxEditApplyAlignment,
            object: NSNumber(value: alignment.rawValue)
        )
    }

    func applyLineSpacing(_ multiple: CGFloat) {
        NotificationCenter.default.post(
            name: .docxEditApplyLineSpacing,
            object: NSNumber(value: Double(multiple))
        )
    }
    func increaseIndent() { NotificationCenter.default.post(name: .docxEditIncreaseIndent, object: nil) }
    func decreaseIndent() { NotificationCenter.default.post(name: .docxEditDecreaseIndent, object: nil) }

    func toggleList(_ type: ListType) {
        NotificationCenter.default.post(name: .docxEditToggleList, object: NSString(string: type.rawValue))
    }

    func applyListVariant(_ id: String) {
        NotificationCenter.default.post(name: .docxEditApplyListVariant, object: NSString(string: id))
    }

    func applyParagraphStyle(_ id: String) {
        NotificationCenter.default.post(name: .docxEditApplyParagraphStyle, object: NSString(string: id))
    }

    func applyCharacterStyle(_ id: String?) {
        NotificationCenter.default.post(name: .docxEditApplyCharacterStyle, object: id.map { NSString(string: $0) })
    }

    func showStyles() { NotificationCenter.default.post(name: .docxEditShowStyles, object: nil) }
    func insertPageBreak() { NotificationCenter.default.post(name: .docxEditInsertPageBreak, object: nil) }

    func pasteAsPlainText() {
        NotificationCenter.default.post(name: .docxEditPasteAsPlainText, object: nil)
    }

    func applyFontName(_ name: String) {
        NotificationCenter.default.post(name: .docxEditApplyFont, object: name)
    }
    func applyFontSize(_ size: CGFloat) {
        NotificationCenter.default.post(name: .docxEditApplyFontSize, object: NSNumber(value: Double(size)))
    }

    // MARK: Recent files

    func clearRecentFiles() {
        recentURLs = []
        UserDefaults.standard.removeObject(forKey: Self.recentKey)
    }

    private func loadRecentURLs() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
        recentURLs = paths.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecentURL(_ url: URL) {
        var urls = recentURLs.filter { $0 != url }
        urls.insert(url, at: 0)
        if urls.count > Self.maxRecent { urls = Array(urls.prefix(Self.maxRecent)) }
        recentURLs = urls
        UserDefaults.standard.set(urls.map(\.path), forKey: Self.recentKey)
    }

    // MARK: Загрузка / сохранение

    private func hasSupportedExtension(_ url: URL) -> Bool {
        ["docx", "doc", "rtf", "md", "markdown", "txt", "odt"].contains(url.pathExtension.lowercased())
    }

    func loadFromURL(_ url: URL) {
        // Сессия ещё не привязана (открытие из Finder до появления окна) —
        // запоминаем URL, догрузим в `session.didSet`.
        guard session != nil else {
            pendingOpenURL = url
            return
        }
        do {
            let ext = url.pathExtension.lowercased()
            let model: DocumentModel
            var report: ImportReport = ImportReport()
            // v0.5.7 (R08): замер длительности open + размер файла.
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let openStart = Date()
            switch ext {
            case "docx", "doc":
                let r = try DocxIO.importDocxWithReport(url: url)
                model = r.0; report = r.1
            case "rtf":
                model = try RtfIO.importRTF(url: url)
            case "odt":
                model = try OdtIO.importODT(url: url)
            case "md", "markdown":
                model = try MarkdownIO.importMarkdown(url: url)
            case "txt":
                let data = try Data(contentsOf: url)
                let encoding = EncodingDetector.detect(data: data)
                let text = EncodingDetector.decode(data, using: encoding)
                model = plainTextToDocument(text)
            default:
                let r = try DocxIO.importDocxWithReport(url: url)
                model = r.0; report = r.1
            }
            let openMs = Date().timeIntervalSince(openStart) * 1000.0
            let bridge = NSDocumentBridge(model: model, fileURL: url)
            bridge.isDirty = false
            session?.replace(with: bridge)
            session?.lastImportReport = report
            session?.lastMetrics.lastOpenMs = openMs
            session?.lastMetrics.lastOpenBytes = fileSize
            addRecentURL(url)
        } catch {
            presentError(error)
        }
    }

    private func saveToURL(_ url: URL) {
        guard let session else { return }
        do {
            // v0.5.7 (R08): замер длительности save.
            let saveStart = Date()
            try DocxIO.exportDocx(session.bridge.model, to: url)
            let saveMs = Date().timeIntervalSince(saveStart) * 1000.0
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            session.lastMetrics.lastSaveMs = saveMs
            session.lastMetrics.lastSaveBytes = bytes
            session.markSaved(url: url)
            addRecentURL(url)
            // v0.2.6: успешно сохранили — убираем автосейв.
            NotificationCenter.default.post(name: .docxEditClearAutorecover, object: nil)
        } catch { presentError(error) }
    }

    private func exportDocument(format: ExportFormat) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.defaultFilename(for: session.bridge)
        switch format {
        case .pdf:      panel.allowedContentTypes = [.init(filenameExtension: "pdf") ?? .data]
        case .docx:     panel.allowedContentTypes = [.init(filenameExtension: "docx") ?? .data]
        case .markdown: panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .data]
        case .rtf:      panel.allowedContentTypes = [.init(filenameExtension: "rtf") ?? .data]
        case .txt:      panel.allowedContentTypes = [.init(filenameExtension: "txt") ?? .data]
        case .odt:      panel.allowedContentTypes = [.init(filenameExtension: "odt") ?? .data]
        }
        // v0.3.5: для TXT — accessory view с выбором кодировки.
        var selectedTxtEncoding: String.Encoding = .utf8
        if format == .txt {
            panel.accessoryView = txtEncodingAccessoryView { selectedTxtEncoding = $0 }
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                switch format {
                case .pdf:      try PdfExporter.exportToPDF(session.bridge.model, to: url)
                case .docx:     try DocxIO.exportDocx(session.bridge.model, to: url)
                case .markdown: try MarkdownIO.exportMarkdown(session.bridge.model, to: url)
                case .rtf:      try RtfIO.exportRTF(session.bridge.model, to: url)
                case .txt:      try exportPlainText(session.bridge.model, to: url, encoding: selectedTxtEncoding)
                case .odt:      try OdtIO.exportODT(session.bridge.model, to: url)
                }
            } catch { presentError(error) }
        }
    }

    /// v0.3.5: TXT-экспорт — конкатенация plain-text параграфов + перевод строки.
    /// Изображения/таблицы теряются (upstream ограничение plain text).
    private func exportPlainText(_ model: DocumentModel, to url: URL, encoding: String.Encoding) throws {
        var out: [String] = []
        for section in model.sections {
            for block in section.blocks {
                if case let .paragraph(p) = block {
                    out.append(p.runs.map { $0.text }.joined())
                }
            }
        }
        let text = out.joined(separator: "\n")
        // Для не-Unicode кодировок недопустимые символы заменяются на "?"
        let data: Data = text.data(using: encoding, allowLossyConversion: true) ?? Data()
        try data.write(to: url, options: .atomic)
    }

    /// NSSavePanel accessory: выпадающий список кодировок для TXT-экспорта.
    private func txtEncodingAccessoryView(onChange: @escaping (String.Encoding) -> Void) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 34))
        let label = NSTextField(labelWithString: "Кодировка:")
        label.frame = NSRect(x: 8, y: 8, width: 90, height: 20)
        let popup = NSPopUpButton(frame: NSRect(x: 100, y: 4, width: 210, height: 26))
        // v0.4.1: ISO 8859-5 (кириллица) — через CFStringEncodings; раньше пункт
        // был ошибочно замаплен на .isoLatin1 (ISO 8859-1, западноевропейская).
        let isoCyrillic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.isoLatinCyrillic.rawValue)))
        let opts: [(String, String.Encoding)] = [
            ("UTF-8", .utf8),
            ("UTF-16", .utf16),
            ("Windows-1251 (CP1251)", .windowsCP1251),
            ("ISO 8859-5 (кириллица)", isoCyrillic),
            ("MacRoman", .macOSRoman),
            ("ASCII", .ascii),
        ]
        for (name, _) in opts { popup.addItem(withTitle: name) }
        popup.selectItem(at: 0)
        popup.target = TxtEncodingHelper.shared
        popup.action = #selector(TxtEncodingHelper.select(_:))
        TxtEncodingHelper.shared.options = opts
        TxtEncodingHelper.shared.callback = onChange
        container.addSubview(label)
        container.addSubview(popup)
        return container
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Ошибка"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func plainTextToDocument(_ text: String) -> DocumentModel {
        let paragraphs = text.components(separatedBy: "\n").map { line in
            Paragraph(runs: [Run(text: line, attributes: CharacterAttributes())],
                      attributes: ParagraphAttributes())
        }
        let blocks = paragraphs.isEmpty
            ? [Block.paragraph(.empty)]
            : paragraphs.map { Block.paragraph($0) }
        return DocumentModel(sections: [DocumentSection(blocks: blocks)])
    }
}

// MARK: - Вспомогательные типы

/// v0.3.5: helper для NSPopUpButton в TXT-экспорте (нужен @objc target).
final class TxtEncodingHelper: NSObject {
    static let shared = TxtEncodingHelper()
    var options: [(String, String.Encoding)] = []
    var callback: ((String.Encoding) -> Void)?
    @objc func select(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < options.count { callback?(options[i].1) }
    }
}

enum ExportFormat {
    case pdf, docx, markdown, rtf, txt, odt

    func defaultFilename(for bridge: NSDocumentBridge) -> String {
        let base = bridge.fileURL?.deletingPathExtension().lastPathComponent ?? "Без имени"
        switch self {
        case .pdf:      return "\(base).pdf"
        case .docx:     return "\(base).docx"
        case .markdown: return "\(base).md"
        case .rtf:      return "\(base).rtf"
        case .txt:      return "\(base).txt"
        case .odt:      return "\(base).odt"
        }
    }
}

extension Notification.Name {
    static let docxEditDocumentChanged   = Notification.Name("docxEditDocumentChanged")
    static let docxEditShowFind          = Notification.Name("docxEditShowFind")
    static let docxEditShowReplace       = Notification.Name("docxEditShowReplace")
    static let docxEditToggleBold        = Notification.Name("docxEditToggleBold")
    static let docxEditToggleItalic      = Notification.Name("docxEditToggleItalic")
    static let docxEditToggleUnderline   = Notification.Name("docxEditToggleUnderline")
    static let docxEditToggleStrikethrough = Notification.Name("docxEditToggleStrikethrough")
    static let docxEditToggleSuperscript   = Notification.Name("docxEditToggleSuperscript")
    static let docxEditToggleSubscript     = Notification.Name("docxEditToggleSubscript")
    static let docxEditChangeCase          = Notification.Name("docxEditChangeCase")
    static let docxEditClearFormatting   = Notification.Name("docxEditClearFormatting")
    static let docxEditApplyFont         = Notification.Name("docxEditApplyFont")
    static let docxEditApplyFontSize     = Notification.Name("docxEditApplyFontSize")
    static let docxEditApplyAlignment    = Notification.Name("docxEditApplyAlignment")
    static let docxEditZoomIn            = Notification.Name("docxEditZoomIn")
    static let docxEditZoomOut           = Notification.Name("docxEditZoomOut")
    static let docxEditZoomReset         = Notification.Name("docxEditZoomReset")
    static let docxEditFitPageWidth      = Notification.Name("docxEditFitPageWidth")
    static let docxEditFitTwoPages       = Notification.Name("docxEditFitTwoPages")
    static let docxEditTogglePageView    = Notification.Name("docxEditTogglePageView")
    static let docxEditTogglePageNumbers = Notification.Name("docxEditTogglePageNumbers")
    static let docxEditShowHeaderFooter  = Notification.Name("docxEditShowHeaderFooter")
    static let docxEditShowInsertTable   = Notification.Name("docxEditShowInsertTable")
    static let docxEditTableEdit         = Notification.Name("docxEditTableEdit")
    static let docxEditShowTableProperties = Notification.Name("docxEditShowTableProperties")
    static let docxEditInsertImage       = Notification.Name("docxEditInsertImage")
    static let docxEditShowHyperlink     = Notification.Name("docxEditShowHyperlink")
    static let docxEditInsertFootnote      = Notification.Name("docxEditInsertFootnote")
    static let docxEditInsertTOC           = Notification.Name("docxEditInsertTOC")
    static let docxEditUpdateTOC           = Notification.Name("docxEditUpdateTOC")
    static let docxEditShowCrossReference  = Notification.Name("docxEditShowCrossReference")
    static let docxEditPageSettingsChanged = Notification.Name("docxEditPageSettingsChanged")
    static let docxEditPageSettingsApplied = Notification.Name("docxEditPageSettingsApplied")
    static let docxEditShowImportReport  = Notification.Name("docxEditShowImportReport")
    static let docxEditCheckSpelling     = Notification.Name("docxEditCheckSpelling")
    static let docxEditShowImageProperties = Notification.Name("docxEditShowImageProperties")
    static let docxEditShowMergeCells    = Notification.Name("docxEditShowMergeCells")
    static let docxEditShowSymbol        = Notification.Name("docxEditShowSymbol")
    static let docxEditInsertDateTime    = Notification.Name("docxEditInsertDateTime")
    static let docxEditInsertText        = Notification.Name("docxEditInsertText")
    static let docxEditApplyLineSpacing  = Notification.Name("docxEditApplyLineSpacing")
    static let docxEditIncreaseIndent    = Notification.Name("docxEditIncreaseIndent")
    static let docxEditDecreaseIndent    = Notification.Name("docxEditDecreaseIndent")
    static let docxEditToggleList        = Notification.Name("docxEditToggleList")
    static let docxEditApplyListVariant  = Notification.Name("docxEditApplyListVariant")
    static let docxEditPasteAsPlainText  = Notification.Name("docxEditPasteAsPlainText")
    static let docxEditApplyParagraphStyle = Notification.Name("docxEditApplyParagraphStyle")
    static let docxEditApplyCharacterStyle = Notification.Name("docxEditApplyCharacterStyle")
    static let docxEditShowStyles          = Notification.Name("docxEditShowStyles")
    static let docxEditInsertPageBreak     = Notification.Name("docxEditInsertPageBreak")
    static let docxEditToggleInvisibles  = Notification.Name("docxEditToggleInvisibles")
    static let docxEditToggleRuler       = Notification.Name("docxEditToggleRuler")
    static let docxEditToggleStylesSidebar = Notification.Name("docxEditToggleStylesSidebar")
    static let docxEditToggleReadingMode   = Notification.Name("docxEditToggleReadingMode")
    static let docxEditToggleCommentsSidebar = Notification.Name("docxEditToggleCommentsSidebar")
    static let docxEditToggleFootnotesSidebar = Notification.Name("docxEditToggleFootnotesSidebar")
    static let docxEditInsertComment       = Notification.Name("docxEditInsertComment")
    static let docxEditToggleTrackChanges  = Notification.Name("docxEditToggleTrackChanges")
    static let docxEditAcceptAllChanges    = Notification.Name("docxEditAcceptAllChanges")
    static let docxEditRejectAllChanges    = Notification.Name("docxEditRejectAllChanges")
    static let docxEditGoToNextRevision    = Notification.Name("docxEditGoToNextRevision")
    static let docxEditAcceptCurrentRev    = Notification.Name("docxEditAcceptCurrentRev")
    static let docxEditRejectCurrentRev    = Notification.Name("docxEditRejectCurrentRev")
    static let docxEditShowStatistics    = Notification.Name("docxEditShowStatistics")
    static let docxEditPrint             = Notification.Name("docxEditPrint")
    static let docxEditShowFontReplace   = Notification.Name("docxEditShowFontReplace")
    static let docxEditShowGoTo          = Notification.Name("docxEditShowGoTo")
    static let docxEditCopyFormatting    = Notification.Name("docxEditCopyFormatting")
    static let docxEditPasteFormatting   = Notification.Name("docxEditPasteFormatting")
    static let docxEditApplyHighlight    = Notification.Name("docxEditApplyHighlight")
    static let docxEditShowRowHeight     = Notification.Name("docxEditShowRowHeight")
    static let docxEditShowParagraphIndents = Notification.Name("docxEditShowParagraphIndents")
    static let docxEditShowFindReplace      = Notification.Name("docxEditShowFindReplace")
    static let docxEditShowImageCrop        = Notification.Name("docxEditShowImageCrop")
    static let docxEditShowDocumentProperties = Notification.Name("docxEditShowDocumentProperties")
    static let docxEditShowBookmarks          = Notification.Name("docxEditShowBookmarks")
    static let docxEditShowCustomDictionary   = Notification.Name("docxEditShowCustomDictionary")
    static let docxEditClearAutorecover       = Notification.Name("docxEditClearAutorecover")
}

/// Делегат меню «Правка», удаляющий системные пункты (Автозаполнение/Диктовка/
/// Эмодзи и символы), которые AppKit автоматически ре-инжектит при открытии.
/// Копии этих пунктов размещены в меню «Вставка» (см. reorganizeMenusForInsertTab).
final class EditMenuCleanupDelegate: NSObject, NSMenuDelegate {
    private let titlesToRemove: Set<String> = [
        "Автозаполнение", "AutoFill", "Auto Fill",
        "Начать диктовку", "Начать диктовку…", "Start Dictation", "Start Dictation…",
        "Эмодзи и символы", "Emoji & Symbols",
        "Символы", "Special Characters…", "Special Characters",
    ]
    func menuNeedsUpdate(_ menu: NSMenu) {
        for i in stride(from: menu.items.count - 1, through: 0, by: -1) {
            let item = menu.items[i]
            if titlesToRemove.contains(item.title) {
                menu.removeItem(at: i)
            }
        }
        // Уборка осиротевших сепараторов в конце.
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}
