//
//  RibbonView.swift
//  DocxEdit
//
//  v0.1.14: ribbon-тулбар с закладками (Главная / Разметка / Вид) в стиле
//  Mac-подобных редакторов. Кастомный SwiftUI-вид (не NSToolbar): закладки + группы,
//  раскладка в 2 строки, элементы не скрываются. Отменяет ADR-016 (NSToolbar).
//

import SwiftUI
import AppKit
import DocxCore

struct RibbonView: View {
    @ObservedObject var controller: DocumentController
    @ObservedObject var prefs: AppPreferences
    @ObservedObject var appDelegate: AppDelegate

    enum Tab: String, CaseIterable, Identifiable {
        case home   = "Главная"
        case insert = "Вставка"
        case review = "Обзор"
        case view   = "Вид"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .home

    var body: some View {
        VStack(spacing: 0) {
            // Строка быстрого доступа (Создать/Открыть/Сохранить/Печать/⌘Z/⌘⇧Z)
            // перенесена в системный title bar через `.toolbar` DocumentWindowView
            // (v0.1.48, как в Mac-подобных редакторов). Ribbon начинается с закладок.
            tabBar
            Divider()
            Group {
                switch tab {
                case .home:   homeTab
                case .insert: insertTab
                case .review: reviewTab
                case .view:   viewTab
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    // MARK: - Закладки

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == t ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Вкладка «Главная»

    private var homeTab: some View {
        HStack(alignment: .top, spacing: 10) {
            group("Буфер обмена") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        btn("scissors",          "Вырезать (⌘X)")   { responder(#selector(NSText.cut(_:))) }
                        btn("doc.on.doc",        "Копировать (⌘C)") { responder(#selector(NSText.copy(_:))) }
                        btn("doc.on.clipboard",  "Вставить (⌘V)")   { responder(#selector(NSText.paste(_:))) }
                        btn("doc.on.clipboard.fill", "Вставить с сохранением стиля (⇧⌥⌘V)") {
                            appDelegate.pasteAsPlainText()
                        }
                    }
                    HStack(spacing: 2) {
                        btn("paintbrush", "Копировать формат (⌘⇧C)") {
                            controller.copyFormatting()
                        }
                        fmt("paintbrush.pointed",
                            controller.hasCopiedFormatting,
                            "Вставить формат (⌘⇧V)") {
                            controller.pasteFormatting()
                        }
                        .disabled(!controller.hasCopiedFormatting)
                    }
                }
            }

            group("Шрифт") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        FontPickerView(
                            selectedFont: Binding(get: { controller.fontName },
                                                  set: { controller.applyFont(name: $0) }),
                            favoriteFonts: prefs.favoriteFonts,
                            recentFonts:   prefs.recentFonts,
                            allFonts:      controller.availableFonts,
                            onSelect:      { controller.applyFont(name: $0) }
                        )
                        .frame(width: 160, height: 22)

                        FontSizeControl(
                            fontSize: $controller.fontSize,
                            isMixed:  controller.hasMixedSizes,
                            onCommit: { controller.applyFontSize(points: $0) }
                        )
                    }
                    HStack(spacing: 2) {
                        fmt("bold",          controller.isBold,          "Жирный (⌘B)")       { controller.toggleBold() }
                        fmt("italic",        controller.isItalic,        "Курсив (⌘I)")       { controller.toggleItalic() }
                        fmt("underline",     controller.isUnderline,     "Подчёркнутый (⌘U)") { controller.toggleUnderline() }
                        fmt("strikethrough", controller.isStrikethrough, "Зачёркнутый (⌘⇧X)") { controller.toggleStrikethrough() }
                        fmt("textformat.superscript", controller.isSuperscript, "Надстрочный (⌃⌘=)") { controller.toggleSuperscript() }
                        fmt("textformat.subscript",   controller.isSubscript,   "Подстрочный (⌃⌘-)") { controller.toggleSubscriptStyle() }
                        divider
                        ColorWellView(color: Binding(get: { controller.textColor },
                                                     set: { controller.applyTextColor($0) }))
                            .frame(width: 24, height: 22)
                            .help("Цвет текста")
                        HighlightPickerButton(controller: controller)
                        btn("textformat.slash", "Очистить форматирование") { controller.clearFormatting() }
                        Menu {
                            Button("ВЕРХНИЙ")                    { controller.applyChangeCase(.upper) }
                            Button("нижний")                     { controller.applyChangeCase(.lower) }
                            Button("Каждое Слово С Заглавной")   { controller.applyChangeCase(.title) }
                            Button("Как в предложениях")         { controller.applyChangeCase(.sentence) }
                            Button("иНВЕРТИРОВАТЬ рЕГИСТР")      { controller.applyChangeCase(.toggleCase) }
                        } label: {
                            Image(systemName: "textformat")
                                .font(.system(size: 12))
                                .frame(width: 26, height: 22)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Регистр")
                    }
                }
            }

            group("Абзац") {
                VStack(alignment: .leading, spacing: 4) {
                    AlignmentPicker(alignment: Binding(
                        get: { controller.textAlignment },
                        set: { controller.applyAlignment($0) }
                    ))
                    HStack(spacing: 2) {
                        fmt("list.bullet", controller.currentListType == .bulleted, "Маркированный список") {
                            controller.toggleList(.bulleted)
                        }
                        fmt("list.number", controller.currentListType == .numbered, "Нумерованный список") {
                            controller.toggleList(.numbered)
                        }
                        multilevelListMenu
                        divider
                        btn("decrease.indent", "Уменьшить отступ (⌘[)") { controller.decreaseIndent() }
                        btn("increase.indent", "Увеличить отступ (⌘])") { controller.increaseIndent() }
                        divider
                        lineSpacingMenu
                    }
                }
            }

            group("Стили") {
                paragraphStyleMenu
                characterStyleMenu
            }

            group("Редактирование") {
                HStack(spacing: 2) {
                    btn("magnifyingglass",     "Найти (⌘F)")      { controller.showFindBar() }
                    btn("arrow.left.arrow.right", "Заменить (⌥⌘F)") { controller.showReplaceBar() }
                    btn("arrow.right.doc.on.clipboard", "Перейти к… (⌘⌥G)") { controller.showGoToDialog() }
                }
            }

            Spacer(minLength: 0)
        }
    }

    /// Послать действие в цепочку респондеров (первому респондеру — NSTextView).
    private func responder(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    /// Пикер стандартного стиля абзаца (Обычный / Заголовок 1–6).
    private var paragraphStyleMenu: some View {
        Menu {
            ForEach(StandardParagraphStyle.all) { style in
                Button {
                    controller.applyParagraphStyle(id: style.id)
                } label: {
                    if controller.currentStyleId == style.id {
                        Label(style.name, systemImage: "checkmark")
                    } else {
                        Text(style.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(StandardParagraphStyle.find(id: controller.currentStyleId)?.name ?? "Обычный")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 128, height: 22)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .help("Стиль абзаца")
    }

    /// Пикер символьного стиля (Strong / Emphasis / Code) — применяется к выделению.
    private var characterStyleMenu: some View {
        Menu {
            ForEach(StandardCharacterStyle.all) { style in
                Button {
                    controller.applyCharacterStyle(id: style.id)
                } label: {
                    if controller.currentCharStyleId == style.id {
                        Label(style.def.name, systemImage: "checkmark")
                    } else {
                        Text(style.def.name)
                    }
                }
            }
            Divider()
            Button("Убрать стиль знака") { controller.applyCharacterStyle(id: nil) }
        } label: {
            HStack(spacing: 4) {
                Text(controller.currentCharStyleId.flatMap { StandardCharacterStyle.find(id: $0)?.def.name } ?? "Без стиля")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 128, height: 22)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .help("Стиль знака (Strong/Emphasis/Code)")
    }

    /// Галерея вариантов многоуровневого списка (форматы маркеров по уровням).
    private var multilevelListMenu: some View {
        Menu {
            Section("Нумерованные") {
                ForEach(MultilevelListVariant.presets.filter { $0.listType == .numbered }) { v in
                    variantButton(v)
                }
            }
            Section("Маркированные") {
                ForEach(MultilevelListVariant.presets.filter { $0.listType == .bulleted }) { v in
                    variantButton(v)
                }
            }
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .help("Многоуровневый список")
    }

    private func variantButton(_ v: MultilevelListVariant) -> some View {
        Button {
            controller.applyListVariant(v)
        } label: {
            if controller.currentListVariantId == v.id {
                Label(v.title, systemImage: "checkmark")
            } else {
                Text(v.title)
            }
        }
    }

    private var lineSpacingMenu: some View {
        Menu {
            Button("Одинарный (1.0)")  { controller.applyLineSpacing(1.0) }
            Button("1.15")             { controller.applyLineSpacing(1.15) }
            Button("Полуторный (1.5)") { controller.applyLineSpacing(1.5) }
            Button("Двойной (2.0)")    { controller.applyLineSpacing(2.0) }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .help("Межстрочный интервал")
    }

    // MARK: - Вкладка «Вставка»

    private var insertTab: some View {
        HStack(alignment: .top, spacing: 10) {
            group("Иллюстрации") {
                HStack(spacing: 2) {
                    btn("photo", "Изображение") { appDelegate.insertImage() }
                }
            }
            group("Ссылки") {
                HStack(spacing: 2) {
                    btn("link", "Гиперссылка (⌘K)") { appDelegate.showHyperlink() }
                    // v0.5.3 (R07): сноска.
                    btn("textformat.superscript", "Сноска (⌘⌥F)") { appDelegate.insertFootnote() }
                }
            }
            group("Таблицы") {
                HStack(spacing: 2) {
                    btn("tablecells", "Таблица (⌘⌥T)") { appDelegate.insertTable() }
                }
            }
            group("Изменить таблицу") {
                HStack(spacing: 2) {
                    btn("arrow.up.to.line", "Добавить строку выше") { appDelegate.tableAddRowAbove() }
                    btn("arrow.down.to.line", "Добавить строку ниже") { appDelegate.tableAddRowBelow() }
                    btn("arrow.left.to.line", "Добавить столбец слева") { appDelegate.tableAddColumnLeft() }
                    btn("arrow.right.to.line", "Добавить столбец справа") { appDelegate.tableAddColumnRight() }
                    divider
                    btn("square.grid.2x2.fill", "Объединить ячейки…") { appDelegate.tableMergeCells() }
                    btn("square.split.2x1", "Разделить ячейку") { appDelegate.tableSplitCell() }
                    divider
                    btn("rectangle.badge.minus", "Удалить строку") { appDelegate.tableDeleteRow() }
                    btn("rectangle.on.rectangle.slash", "Удалить столбец") { appDelegate.tableDeleteColumn() }
                    btn("trash", "Удалить таблицу") { appDelegate.tableDeleteTable() }
                    divider
                    btn("slider.horizontal.3", "Свойства таблицы…") { appDelegate.showTableProperties() }
                }
                .disabled(!controller.isCaretInTable)
                .opacity(controller.isCaretInTable ? 1.0 : 0.4)
            }
            group("Страницы") {
                HStack(spacing: 2) {
                    btn("arrow.turn.up.right", "Разрыв страницы (⌘⏎)") { controller.insertPageBreak() }
                }
            }
            group("Символы") {
                HStack(spacing: 2) {
                    btn("character", "Символ…") { appDelegate.showSymbol() }
                    Menu {
                        Button("Дата") { appDelegate.insertDateTime("date") }
                        Button("Время") { appDelegate.insertDateTime("time") }
                        Button("Дата и время") { appDelegate.insertDateTime("datetime") }
                    } label: {
                        Image(systemName: "calendar")
                            .frame(width: 28, height: 22)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Дата и время")
                }
            }
            // Будущие группы (заготовки для R07):
            //   «Ссылки» → «Сноска», «Оглавление»
            Spacer(minLength: 0)
        }
    }

    // MARK: - Вкладка «Обзор» (v0.1.56)

    private var reviewTab: some View {
        HStack(alignment: .top, spacing: 10) {
            group("Правописание") {
                HStack(spacing: 4) {
                    btnLabeled("checkmark.circle", "Проверить", "Открыть панель проверки правописания и грамматики") {
                        appDelegate.reviewCheckSpelling()
                    }
                    fmtLabeled("textformat.abc.dottedunderline",
                               "При вводе",
                               controller.continuousSpellCheck,
                               "Подчёркивать ошибки красным по мере набора") {
                        controller.toggleContinuousSpellCheck()
                    }
                    fmtLabeled("text.book.closed",
                               "Грамматика",
                               controller.grammarCheck,
                               "Проверять грамматику при вводе") {
                        controller.toggleGrammarCheck()
                    }
                }
            }
            group("Замены") {
                Menu {
                    Toggle("«Умные» кавычки",
                           isOn: Binding(get: { controller.smartQuotes },
                                         set: { _ in controller.toggleSmartQuotes() }))
                    Toggle("«Умные» тире",
                           isOn: Binding(get: { controller.smartDashes },
                                         set: { _ in controller.toggleSmartDashes() }))
                    Toggle("Автозамена ссылок (детекторы данных)",
                           isOn: Binding(get: { controller.dataDetectors },
                                         set: { _ in controller.toggleDataDetectors() }))
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "wand.and.stars").font(.system(size: 15))
                        Text("Замены").font(.system(size: 10))
                    }
                    .frame(width: 56, height: 46)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 60)
                .help("Автоматические замены при вводе")
            }
            group("Отчёты") {
                btnLabeled("doc.text.magnifyingglass", "Отчёт",
                           "Отчёт об открытии — что не удалось восстановить из файла") {
                    appDelegate.showImportReport()
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Вкладка «Вид»

    private var viewTab: some View {
        HStack(alignment: .top, spacing: 10) {
            group("Режим") {
                fmt("doc.text", controller.isPageView, "Вид страницы (A4) (⌘⌥P)") {
                    controller.togglePageView()
                }
            }
            group("Показать") {
                fmt("paragraphsign", controller.showsInvisibleCharacters, "Непечатаемые символы (⌘⇧8)") {
                    controller.toggleInvisibleCharacters()
                }
            }
            group("Масштаб") {
                HStack(spacing: 2) {
                    btn("minus", "Уменьшить (⌘-)") { controller.zoomOut() }
                    Text("\(Int(controller.zoomLevel * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .frame(width: 46, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture { controller.resetZoom() }
                        .help("Сбросить масштаб (⌘0)")
                    btn("plus", "Увеличить (⌘=)") { controller.zoomIn() }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Группа ribbon (контент + подпись снизу + разделитель)

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 3) {
                content()
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 52)
        }
    }

    // MARK: - Кнопки

    /// Кнопка-переключатель: активное состояние — подсветкой фона (ADR-013).
    private func fmt(_ symbol: String, _ isOn: Bool, _ help: String,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Кнопка без состояния.
    private func btn(_ symbol: String, _ help: String,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, 2)
    }

    /// «Крупная» кнопка с иконкой и подписью под ней (паттерн Mac-подобных редакторов).
    /// Используется для важных действий, где иконка одна недостаточно понятна.
    private func btnLabeled(_ symbol: String, _ label: String, _ help: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(label).font(.system(size: 10))
            }
            .frame(width: 56, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Палитра подсветки: цветные квадраты + «Без подсветки». v0.1.83.
    struct HighlightPickerButton: View {
        @ObservedObject var controller: DocumentController
        @State private var isShown = false

        static let colors: [(name: String, color: NSColor)] = [
            ("Жёлтый",         NSColor(srgbRed: 1,   green: 1,   blue: 0,   alpha: 1)),
            ("Ярко-зелёный",   NSColor(srgbRed: 0,   green: 1,   blue: 0,   alpha: 1)),
            ("Голубой",        NSColor(srgbRed: 0,   green: 1,   blue: 1,   alpha: 1)),
            ("Розовый",        NSColor(srgbRed: 1,   green: 0,   blue: 1,   alpha: 1)),
            ("Синий",          NSColor(srgbRed: 0,   green: 0,   blue: 1,   alpha: 1)),
            ("Красный",        NSColor(srgbRed: 1,   green: 0.3, blue: 0.3, alpha: 1)),
            ("Т.-жёлтый",      NSColor(srgbRed: 0.5, green: 0.5, blue: 0,   alpha: 1)),
            ("Т.-зелёный",     NSColor(srgbRed: 0,   green: 0.5, blue: 0,   alpha: 1)),
            ("Т.-голубой",     NSColor(srgbRed: 0,   green: 0.5, blue: 0.5, alpha: 1)),
            ("Т.-фиолетовый",  NSColor(srgbRed: 0.5, green: 0,   blue: 0.5, alpha: 1)),
            ("Т.-синий",       NSColor(srgbRed: 0,   green: 0,   blue: 0.5, alpha: 1)),
            ("Т.-красный",     NSColor(srgbRed: 0.5, green: 0,   blue: 0,   alpha: 1)),
            ("Чёрный",         NSColor.black),
            ("Т.-серый",       NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
            ("Св.-серый",      NSColor(srgbRed: 0.75, green: 0.75, blue: 0.75, alpha: 1)),
            ("Белый",          NSColor.white),
        ]

        var body: some View {
            Button {
                isShown.toggle()
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "highlighter").font(.system(size: 12))
                    Rectangle()
                        .fill(Color(nsColor: controller.highlightColor ?? .yellow))
                        .frame(width: 18, height: 3)
                }
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Цвет подсветки")
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Цвет подсветки").font(.caption).foregroundColor(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.colors, id: \.name) { entry in
                            Button {
                                controller.applyHighlightColor(entry.color)
                                isShown = false
                            } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: entry.color))
                                    .frame(width: 20, height: 20)
                                    .overlay(RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help(entry.name)
                        }
                    }
                    Divider()
                    Button {
                        controller.applyHighlightColor(nil)
                        isShown = false
                    } label: {
                        Label("Без подсветки", systemImage: "nosign")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }
        }
    }

    /// Крупная toggle-кнопка с иконкой + подписью (ribbon-style).
    private func fmtLabeled(_ symbol: String, _ label: String, _ isOn: Bool, _ help: String,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(label).font(.system(size: 10))
            }
            .frame(width: 56, height: 46)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? Color.accentColor.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
