//
//  DocumentWindowView.swift
//  DocxEdit
//
//  v0.1.9: тулбар переведён на нативный NSToolbar (через SwiftUI .toolbar) —
//  авто-overflow в », системные отступы, элементы не наезжают друг на друга.
//

import SwiftUI
import AppKit
import DocxCore

// MARK: - Драг-разделитель боковых панелей (v1.5.9)

/// Узкая зона захвата у левого края панели: тянем влево — панель шире,
/// вправо — уже. Диапазон — DocumentController.sidebarWidthRange.
struct SidebarResizer: View {
    @Binding var width: CGFloat
    /// v1.5.11: leading = true для панели у ЛЕВОГО края (навигатор) —
    /// тянем вправо, чтобы расширить.
    var leading: Bool = false
    @State private var startWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Divider()
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if startWidth == 0 { startWidth = width }
                            let r = DocumentController.sidebarWidthRange
                            let delta = leading ? g.translation.width : -g.translation.width
                            width = min(r.upperBound, max(r.lowerBound, startWidth + delta))
                        }
                        .onEnded { _ in startWidth = 0 }
                )
        }
        .frame(width: 8)
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Главный вид окна

struct DocumentWindowView: View {
    @EnvironmentObject private var session: DocumentSession
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var controller = DocumentController()
    @ObservedObject private var prefs = AppPreferences.shared

    @State private var saveToast: SaveToastState? = nil
    @State private var pendingDefaultFont: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // v0.4.3 (R06): режим «Чтение» скрывает ribbon.
            // v1.6.0: исходный MD-режим тоже (форматирование неприменимо к исходнику).
            if !controller.isReadingMode && !session.isMarkdownSourceMode {
                RibbonView(controller: controller, prefs: prefs, appDelegate: appDelegate, session: session)
                Divider()
            }
            // v1.7.2: баннер «Шрифт по умолчанию изменён — применить к этому документу?».
            if let font = pendingDefaultFont {
                DefaultFontChangedBanner(
                    fontName: font,
                    onApply: {
                        controller.applyFontToWholeDocument(name: font)
                        pendingDefaultFont = nil
                    },
                    onDismiss: { pendingDefaultFont = nil }
                )
                Divider()
            }

            HStack(spacing: 0) {
                // v1.5.11: навигатор по заголовкам — слева (как Navigation Pane).
                if controller.showsNavigatorSidebar {
                    NavigatorSidebarView(controller: controller,
                                         width: $controller.navigatorSidebarWidth)
                    SidebarResizer(width: $controller.navigatorSidebarWidth, leading: true)
                }
                // v1.6.0: исходный Markdown — вместо WYSIWYG-редактора.
                // v1.8.3: split-режим — source слева, WYSIWYG-превью справа.
                if session.isMarkdownSplitMode {
                    HSplitView {
                        MarkdownSourceView(
                            text: $session.markdownSource,
                            onChange: { session.applyMarkdownSource($0) }
                        )
                        .frame(minWidth: 240)
                        TextEditorRepresentable(controller: controller, session: session)
                            .frame(minWidth: 240)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if session.isMarkdownSourceMode {
                    MarkdownSourceView(
                        text: $session.markdownSource,
                        hybrid: session.isMarkdownHybrid,
                        baseURL: session.bridge.fileURL?.deletingLastPathComponent(),
                        onChange: { session.applyMarkdownSource($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                ZStack {
                    TextEditorRepresentable(controller: controller, session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // v1.7.1: подсказка на пустом документе (empty state).
                    // Скрывается при первом keystroke — attributedText.length > 0.
                    // allowsHitTesting=false, чтобы клик уходил в редактор.
                    if session.attributedText.length == 0, session.bridge.fileURL == nil {
                        EmptyDocumentHint(mode: session.mode)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                }
                if controller.showsStylesSidebar && !session.isMarkdownSourceMode {
                    SidebarResizer(width: $controller.stylesSidebarWidth)
                    StylesSidebarView(controller: controller,
                                      width: $controller.stylesSidebarWidth)
                }
                if controller.showsCommentsSidebar && !session.isMarkdownSourceMode {
                    SidebarResizer(width: $controller.commentsSidebarWidth)
                    CommentsSidebarView(engine: controller.comments,
                                        width: $controller.commentsSidebarWidth,
                                        onClose: { controller.toggleCommentsSidebar() })
                }
                if controller.showsFootnotesSidebar && !session.isMarkdownSourceMode {
                    SidebarResizer(width: $controller.footnotesSidebarWidth)
                    FootnotesSidebarView(controller: controller,
                                         width: $controller.footnotesSidebarWidth)
                }
            }

            Divider()

            StatusBar(controller: controller, trackChanges: controller.trackChanges, session: session)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(.background)
        }
        .navigationTitle(session.windowTitle)
        .background(WindowCloseGuard(session: session, appDelegate: appDelegate))
        .overlay(alignment: .bottom) {
            if let t = saveToast {
                SaveToastView(state: t) {
                    if let url = t.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { controller.attach(session: session) }
        // v1.7.2: тост о сохранении. Только key window — иначе тост дублируется во всех окнах.
        .onReceive(NotificationCenter.default.publisher(for: .docxEditShowSaveToast)) { note in
            guard controller.textView?.window?.isKeyWindow == true,
                  let text = note.userInfo?["text"] as? String else { return }
            let url = note.userInfo?["url"] as? URL
            withAnimation(.easeOut(duration: 0.18)) { saveToast = SaveToastState(text: text, url: url) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeIn(duration: 0.25)) {
                    if saveToast?.id == note.userInfo?["_id"] as? UUID || saveToast != nil {
                        saveToast = nil
                    }
                }
            }
        }
        // v1.7.2: смена defaultFontName в Preferences → баннер в открытых окнах,
        // если у документа есть контент (пустой — не имеет смысла применять).
        .onReceive(NotificationCenter.default.publisher(for: .docxEditDefaultFontChanged)) { note in
            guard let name = note.userInfo?["newFontName"] as? String,
                  session.attributedText.length > 0 else { return }
            pendingDefaultFont = name
        }
        // v0.1.48: строка быстрого доступа (Создать/Открыть/Сохранить/Печать/⌘Z/⌘⇧Z)
        // — в системный title bar (как в Mac-подобных редакторов). Через SwiftUI `.toolbar`
        // + `.windowToolbarStyle(.unifiedCompact)` на Scene: NSToolbar встраивается
        // в титлбар, ribbon (закладки + группы) остаётся под ним. Раньше плашка
        // жила отдельной строкой над закладками ribbon.
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { appDelegate.newDocument() } label: {
                    Image(systemName: "doc.badge.plus")
                }.help("Создать (⌘N)")
                Button { appDelegate.openDocument() } label: {
                    Image(systemName: "folder")
                }.help("Открыть (⌘O)")
                Button { appDelegate.saveDocument() } label: {
                    Image(systemName: "square.and.arrow.down")
                }.help("Сохранить (⌘S)")
                Button { appDelegate.printDocument() } label: {
                    Image(systemName: "printer")
                }.help("Печать (⌘P)")
            }
            ToolbarItemGroup(placement: .navigation) {
                Button { controller.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }.help("Отменить (⌘Z)")
                Button { controller.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }.help("Вернуть (⇧⌘Z)")
            }
        }
    }
}

// MARK: - Заголовок окна + подтверждение закрытия при несохранённых изменениях

/// Невидимый мост к `NSWindow`: ставит делегата для `windowShouldClose`
/// (диалог Сохранить/Не сохранять/Отмена) и синхронизирует нативный индикатор
/// правки (точка в кнопке закрытия) + represented URL. Делегат-форвардинг
/// сохраняет поведение делегата SwiftUI для прочих методов.
struct WindowCloseGuard: NSViewRepresentable {
    let session: DocumentSession
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.session = session
        context.coordinator.appDelegate = appDelegate
        DispatchQueue.main.async {
            if let w = v.window { context.coordinator.attach(to: w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.session = session
        context.coordinator.appDelegate = appDelegate
        if context.coordinator.window == nil, let w = nsView.window {
            context.coordinator.attach(to: w)
        }
        context.coordinator.syncEditedState()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var previousDelegate: NSWindowDelegate?
        var session: DocumentSession?
        var appDelegate: AppDelegate?

        func attach(to w: NSWindow) {
            guard window == nil else { return }
            window = w
            previousDelegate = w.delegate
            w.delegate = self
            syncEditedState()
        }

        /// Синхронизирует нативный индикатор правки и represented URL.
        func syncEditedState() {
            guard let window, let session else { return }
            MainActor.assumeIsolated {
                window.isDocumentEdited = session.bridge.isDirty
                window.representedURL = session.bridge.fileURL
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let session, let appDelegate else { return true }
            return MainActor.assumeIsolated {
                guard session.bridge.isDirty else { return true }
                let alert = NSAlert()
                alert.messageText = "Сохранить изменения перед закрытием?"
                let name = session.bridge.fileURL?.lastPathComponent ?? "Без имени"
                alert.informativeText = "Документ «\(name)» содержит несохранённые изменения."
                alert.addButton(withTitle: "Сохранить")      // .alertFirstButtonReturn
                alert.addButton(withTitle: "Не сохранять")   // .alertSecondButtonReturn
                alert.addButton(withTitle: "Отмена")         // .alertThirdButtonReturn
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    appDelegate.saveDocument()
                    // Закрываем только если сохранение прошло (иначе — отмена панели).
                    return !session.bridge.isDirty
                case .alertSecondButtonReturn:
                    // v1.7.0: «Не сохранять» — пользователь явно отказался от
                    // изменений. Убираем и autorecover-копию этой сессии, иначе
                    // (при последующем крахе других окон) её предложат восстановить.
                    let dir = DocumentController.autorecoverDirectory
                    let url = dir.appendingPathComponent(session.autorecoverFileName)
                    try? FileManager.default.removeItem(at: url)
                    let mdURL = url.deletingPathExtension().appendingPathExtension("md")
                    try? FileManager.default.removeItem(at: mdURL)
                    return true
                default:
                    return false
                }
            }
        }

        // Форвардинг прочих методов делегата на делегата SwiftUI.
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (previousDelegate?.responds(to: aSelector) ?? false)
        }
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let pd = previousDelegate, pd.responds(to: aSelector) { return pd }
            return nil
        }
    }
}

// MARK: - Контрол размера шрифта (− / поле / +)

struct FontSizeControl: View {
    @Binding var fontSize: CGFloat
    var isMixed: Bool
    var onCommit: (CGFloat) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField("", text: $text)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .font(.system(size: 12))
                .focused($focused)
                .frame(width: 32, height: 22)
                .onAppear { syncText() }
                .onChange(of: fontSize) { _ in if !focused { syncText() } }
                .onChange(of: isMixed)  { _ in if !focused { syncText() } }
                .onSubmit {
                    if let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 {
                        commit(CGFloat(v))
                    } else { syncText() }
                }

            Button { step(+1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .fixedSize()
    }

    private func syncText() {
        text = isMixed ? "" : (fontSize > 0 ? "\(Int(fontSize))" : "")
    }

    private func step(_ delta: CGFloat) {
        commit(max(1, min(144, (isMixed ? 12 : fontSize) + delta)))
    }

    private func commit(_ value: CGFloat) {
        fontSize = value
        onCommit(value)
    }
}

// MARK: - Кнопки выравнивания

struct AlignmentPicker: View {
    @Binding var alignment: NSTextAlignment

    private let items: [(NSTextAlignment, String, String)] = [
        (.left,      "text.alignleft",   "По левому краю"),
        (.center,    "text.aligncenter", "По центру"),
        (.right,     "text.alignright",  "По правому краю"),
        (.justified, "text.justify",     "По ширине"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0.rawValue) { (al, icon, tip) in
                Button { alignment = al } label: {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(alignment == al ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tip)
            }
        }
    }
}

// MARK: - Компактный color well (NSColorWell, .default style)

struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        // Сравниваем в едином цветовом пространстве: прямое != у NSColor
        // между разными colorspace даёт ложное «не равны» → лишний цикл/дёрганье.
        let lhs = well.color.usingColorSpace(.sRGB)
        let rhs = color.usingColorSpace(.sRGB)
        if lhs != rhs { well.color = color }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 26, height: proposal.height ?? 22)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: ColorWellView
        init(parent: ColorWellView) { self.parent = parent }

        @objc func colorChanged(_ sender: NSColorWell) { parent.color = sender.color }
    }
}

// MARK: - Строка состояния

struct StatusBar: View {
    @ObservedObject var controller: DocumentController
    // v0.4.6: подписываемся на trackChanges отдельно — Published-поля живут
    // в движке, а controller.trackChanges сам по себе не пропускает изменения
    // через ObservedObject controller. Использую `.init` вместо `_` из-за
    // особенностей init ObservedObject wrapper.
    @ObservedObject var trackChanges: TrackChangesEngine
    // v1.4.0 (ADR-049): сессия нужна для индикатора/переключателя режима.
    @ObservedObject var session: DocumentSession

    private let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }()

    var body: some View {
        HStack(spacing: 10) {
            // v1.2.1: клик по счётчику слов открывает полную статистику (⌥⌘I).
            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(name: .docxEditShowStatistics, object: nil)
                }
                .help("Статистика документа (⌥⌘I)")
            Divider().frame(height: 12)
            LanguageIndicator(controller: controller)
            Divider().frame(height: 12)
            ModeIndicator(session: session)
            // v1.7.1: индикатор сохранения. Показывает «Изменения не сохранены»
            // (⌘S), «Сохранено только что / N мин / чч:мм» — как в Pages/Notion.
            Divider().frame(height: 12)
            SavedIndicator(session: session)
            // v1.6.0: исходный Markdown (только в MD-режиме) — ⌘/.
            if session.mode == .markdown {
                Divider().frame(height: 12)
                MarkdownViewPicker(session: session)
            }
            Spacer()
            // v0.4.6 (R06): индикатор track-changes в статусбаре.
            if trackChanges.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                    Text("Записываются правки")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.1)))
                Divider().frame(height: 12)
            }
            // v0.4.8 (R06): панель обхода правок (если есть хотя бы одна).
            let revCount = trackChanges.revisionCount()
            if revCount > 0 {
                HStack(spacing: 6) {
                    Text("Правок: \(revCount)").font(.caption)
                    Button { controller.trackChanges.goToNextRevision() } label: {
                        Image(systemName: "chevron.right.circle")
                    }.buttonStyle(.plain).help("Следующая правка (⇧⌘])")
                    Button {
                        let e = controller.trackChanges
                        if let tv = controller.textView {
                            let caret = tv.selectedRange().location
                            let r = e.listRevisions().first { $0.range.contains(caret) } ?? e.nextRevision()
                            if let r { e.acceptOne(r) }
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }.buttonStyle(.plain).help("Принять правку под курсором")
                    Button {
                        let e = controller.trackChanges
                        if let tv = controller.textView {
                            let caret = tv.selectedRange().location
                            let r = e.listRevisions().first { $0.range.contains(caret) } ?? e.nextRevision()
                            if let r { e.rejectOne(r) }
                        }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }.buttonStyle(.plain).help("Отклонить правку под курсором")
                }
                .padding(.horizontal, 6).padding(.vertical, 1)
                Divider().frame(height: 12)
            }
            // v0.4.3 (R06): в режиме чтения — «баннер» с выходом (ribbon скрыт,
            // напоминаем пользователю о состоянии + даём быстрый выход).
            if controller.isReadingMode {
                Button {
                    controller.toggleReadingMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                        Text("Выйти из режима чтения")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)  // Esc
                Divider().frame(height: 12)
            }
            // Переключатель вида (как в мейнстрим-редакторов — в строке состояния).
            // v1.4.1 (ADR-049): в MD-режиме страниц нет — вид/раскладки скрыты.
            if session.mode == .docx {
            viewModeButton(systemName: "doc.richtext", on: controller.isPageView,
                           help: "Вид страницы") {
                if !controller.isPageView { controller.togglePageView() }
            }
            viewModeButton(systemName: "doc.plaintext", on: !controller.isPageView,
                           help: "Обычный вид") {
                if controller.isPageView { controller.togglePageView() }
            }
            Divider().frame(height: 12)
            }
            // Масштаб (как в мейнстрим-редакторов — справа в строке состояния).
            if session.mode == .docx {
            Button { controller.fitPageWidth() } label: {
                Image(systemName: "arrow.left.and.right.square")
            }
            .buttonStyle(.plain).help("По ширине страницы")
            Button { controller.fitTwoPages() } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.plain).help("Две страницы")
            }
            Button { controller.zoomOut() } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).help("Уменьшить масштаб")
            Button { controller.setZoom(1.0) } label: {
                Text("\(Int((controller.zoomLevel * 100).rounded()))%")
                    .font(.caption).monospacedDigit().frame(width: 40)
            }
            .buttonStyle(.plain).help("Сбросить масштаб (100%)")
            Button { controller.zoomIn() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("Увеличить масштаб")
            Divider().frame(height: 12)
            Text("DocxEdit \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func viewModeButton(systemName: String, on: Bool, help: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(on ? Color.accentColor.opacity(0.2) : .clear))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Индикатор языка в статусбаре (v0.1.99)

/// Показывает определённый язык абзаца в статусбаре с меню быстрого переключения
/// языка проверки орфографии (влияет на подчёркивание ошибок; не сохраняется в модель).
private struct LanguageIndicator: View {
    @ObservedObject var controller: DocumentController

    /// Отображаемое имя языка для BCP-47 кода. Использует Locale для локализации.
    private func displayName(for code: String?) -> String {
        guard let code, !code.isEmpty else { return "—" }
        let loc = Locale.current
        return loc.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    var body: some View {
        Menu {
            Button("Русский")   { controller.setSpellCheckLanguage("ru") }
            Button("Английский") { controller.setSpellCheckLanguage("en") }
            Divider()
            Button("Автоматически") { controller.setSpellCheckLanguage("") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                Text(displayName(for: controller.currentLanguageCode))
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Определённый язык абзаца. Клик — язык проверки орфографии.")
    }
}

// MARK: - Вид Markdown: визуальный / гибрид / исходник (v1.9.0)

private struct MarkdownViewPicker: View {
    @ObservedObject var session: DocumentSession

    private var current: String {
        if session.isMarkdownHybrid { return "Гибрид" }
        return session.isMarkdownSourceMode ? "Исходник" : "Визуальный"
    }

    var body: some View {
        Menu {
            Button(current == "Визуальный" ? "✓ Визуальный" : "Визуальный") {
                if session.isMarkdownSourceMode { session.exitMarkdownSourceMode() }
                if session.isMarkdownSplitMode { session.exitMarkdownSplitMode() }
            }
            Button(current == "Гибрид" ? "✓ Гибрид" : "Гибрид") { session.enterMarkdownHybridMode() }
            Button(current == "Исходник" ? "✓ Исходник" : "Исходник") { session.enterMarkdownSourceMode() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye").font(.system(size: 10))
                Text(current).font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Вид Markdown: визуальный (⌘/), гибрид как в Typora (⌥⌘/), исходник")
    }
}

// MARK: - Индикатор/переключатель режима документа (v1.4.0, ADR-049)

/// Показывает режим документа (DOCX / Markdown) в статусбаре; клик — меню
/// переключения. При переходе DOCX→Markdown на непустом документе предупреждает
/// о потере части форматирования при сохранении в .md.
private struct ModeIndicator: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        Menu {
            ForEach(DocumentMode.allCases) { m in
                Button {
                    switchMode(to: m)
                } label: {
                    Text(m == session.mode ? "✓ \(m.displayName)" : m.displayName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: session.mode == .markdown ? "m.square" : "doc.richtext")
                    .font(.system(size: 10))
                Text(session.mode.displayName)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Формат документа. Клик — переключить режим (DOCX / Markdown).")
    }

    private func switchMode(to m: DocumentMode) {
        guard m != session.mode else { return }
        if m == .markdown, session.attributedText.length > 0 {
            let alert = NSAlert()
            alert.messageText = "Переключить в Markdown?"
            alert.informativeText = "При сохранении в .md часть форматирования (шрифты, цвета, выравнивание, колонтитулы) будет потеряна. Текст, заголовки, списки, таблицы, изображения и ссылки сохранятся."
            alert.addButton(withTitle: "Переключить")
            alert.addButton(withTitle: "Отмена")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // v1.6.0: выходим из исходного режима при смене формата.
        if session.isMarkdownSourceMode { session.exitMarkdownSourceMode() }
        session.mode = m
    }
}

/// v1.7.4: mini-toolbar над выделением — Word/Notion-паттерн. Плавающая
/// панелька с частыми командами: B / I / U / S / Highlight / ⌘K.
/// Постит те же Notification'ы, что меню/ribbon, — key window фильтр в шине
/// доставит команду именно этой сессии.
private struct MiniToolbarView: View {
    @ObservedObject var controller: DocumentController

    var body: some View {
        HStack(spacing: 2) {
            btn("Ж", tip: "Полужирный (⌘B)", on: controller.isBold) {
                NotificationCenter.default.post(name: .docxEditToggleBold, object: nil)
            }
            .font(.system(size: 12, weight: .bold))
            btn("К", tip: "Курсив (⌘I)", on: controller.isItalic) {
                NotificationCenter.default.post(name: .docxEditToggleItalic, object: nil)
            }
            .font(.system(size: 12, weight: .regular).italic())
            btn("Ч", tip: "Подчёркнутый (⌘U)", on: controller.isUnderline) {
                NotificationCenter.default.post(name: .docxEditToggleUnderline, object: nil)
            }
            btn("З", tip: "Зачёркнутый (⌘⇧X)", on: controller.isStrikethrough) {
                NotificationCenter.default.post(name: .docxEditToggleStrikethrough, object: nil)
            }
            Divider().frame(height: 16)
            iconBtn("highlighter", tip: "Подсветка жёлтым (повтор — снять)") {
                // Toggle: если уже подсвечено — снять (nil); иначе жёлтый.
                let color: NSColor? = controller.highlightColor == nil
                    ? NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1) : nil
                NotificationCenter.default.post(name: .docxEditApplyHighlight, object: color)
            }
            iconBtn("link", tip: "Гиперссылка (⌘K)") {
                NotificationCenter.default.post(name: .docxEditShowHyperlink, object: nil)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
    }

    private func btn(_ label: String, tip: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 4).fill(on ? Color.accentColor.opacity(0.2) : .clear))
        }
        .buttonStyle(.plain)
        .help(tip)
    }
    private func iconBtn(_ system: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}

/// v1.7.2: состояние тоста «Сохранено/Экспортировано» с кнопкой Finder.
struct SaveToastState: Equatable {
    let id: UUID = UUID()
    let text: String
    let url: URL?
}

private struct SaveToastView: View {
    let state: SaveToastState
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(state.text)
                .font(.callout)
                .lineLimit(1)
            if state.url != nil {
                Button("Показать в Finder", action: onReveal)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
    }
}

/// v1.7.2: баннер «Шрифт по умолчанию изменён» — предлагает применить к
/// текущему документу. Единственное действие + кнопка закрыть.
private struct DefaultFontChangedBanner: View {
    let fontName: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat")
                .foregroundStyle(.blue)
            Text("Шрифт по умолчанию изменён на «\(fontName)». Применить к этому документу?")
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Применить", action: onApply)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Закрыть баннер")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
    }
}

/// v1.7.1: подсказка в пустом документе — исчезает при первом keystroke.
/// Позиционирование по центру верхней трети — не мешает курсору, читается сразу.
private struct EmptyDocumentHint: View {
    let mode: DocumentMode

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .markdown ? "m.square" : "doc.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(mode == .markdown ? "Начните печатать Markdown" : "Начните печатать")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("⌘V", "вставить текст из буфера (умная вставка Markdown)")
                shortcutRow("⌘O", "открыть существующий документ")
                shortcutRow(mode == .markdown ? "⌘/" : "⌘⌥1", mode == .markdown ? "переключить исходный Markdown" : "заголовок 1")
                shortcutRow("⌘,", "настройки")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 120)
    }

    private func shortcutRow(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.3)))
                .frame(minWidth: 38, alignment: .center)
            Text(text)
        }
    }
}

/// v1.7.1: индикатор сохранения в статусбаре (паттерн Pages/Notion).
/// Три состояния:
/// - несохранённый новый (fileURL == nil, isDirty) — «Не сохранён»
/// - грязный после явного сохранения — «Не сохранено с HH:MM»
/// - чистый и сохранённый — «Сохранено N мин / Сохранено HH:MM».
/// Обновляется раз в 30с общим таймером-тиком (реюзаем autorecover-каденс).
private struct SavedIndicator: View {
    @ObservedObject var session: DocumentSession
    @State private var tick = Date()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(color)
        .help(hint)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { tick = $0 }
    }

    private var iconName: String {
        if session.bridge.isDirty { return "circle.fill" }
        return session.lastSavedAt == nil ? "circle" : "checkmark.circle"
    }
    private var color: Color {
        session.bridge.isDirty ? .orange : .secondary
    }
    private var label: String {
        if session.bridge.fileURL == nil, session.lastSavedAt == nil {
            return session.bridge.isDirty ? "Не сохранён" : "Черновик"
        }
        if let ts = session.lastSavedAt {
            let ago = tick.timeIntervalSince(ts)
            let stamp = savedStamp(ago: ago, at: ts)
            return session.bridge.isDirty ? "Не сохранено, было \(stamp)" : "Сохранено \(stamp)"
        }
        return session.bridge.isDirty ? "Не сохранено" : "Сохранено"
    }
    private var hint: String {
        if session.bridge.isDirty { return "В документе есть несохранённые изменения (⌘S — сохранить)" }
        return "Документ сохранён"
    }
    private func savedStamp(ago: TimeInterval, at date: Date) -> String {
        if ago < 5 { return "только что" }
        if ago < 60 { return "\(Int(ago)) с назад" }
        if ago < 3600 {
            let m = Int(ago / 60)
            let suf = pluralMinutes(m)
            return "\(m) \(suf) назад"
        }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "в \(df.string(from: date))"
    }
    private func pluralMinutes(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1, mod100 != 11 { return "мин" }        // 1 мин
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "мин" }
        return "мин"
    }
}

// MARK: - NSTextView-обёртка с поддержкой page-view и zoom

struct TextEditorRepresentable: NSViewRepresentable {
    @ObservedObject var controller: DocumentController
    @ObservedObject var session: DocumentSession

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 форсируется ручной сборкой стека storage → DocxLayoutManager →
        // container → NSTextView (TextKit 2 авто-рендерил бы маркеры списков, ADR-027;
        // DocxLayoutManager рисует непечатаемые ·/→/¶).
        let storage = NSTextStorage()
        let layoutManager = DocxLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = PaginatedTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = DocxTextView(frame: .zero, textContainer: container)
        textView.docxController = controller
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView
        // v0.1.100: линейка — включается/отключается через контроллер (showsRuler).
        scrollView.hasHorizontalRuler = true
        textView.usesRuler = true

        textView.isRichText    = true
        textView.allowsUndo    = true
        textView.usesFindBar   = true
        // v1.6.4: орфография/грамматика «как в Word» — красное/зелёное
        // подчёркивание прямо в тексте (TextKit 1 рисует нативно).
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        // v0.1.84: полупрозрачное выделение — чтобы highlight (`.backgroundColor`)
        // был виден сквозь селекцию. Дефолтный `selectedTextBackgroundColor`
        // непрозрачный и полностью закрывает подсветку рана.
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45)
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.delegate      = context.coordinator
        textView.textContainerInset = NSSize(width: 32, height: 32)
        // v0.1.54: гиперссылки. Стандартный синий+underline; открытие по **Cmd+клик**
        // (v0.1.55, паттерн Mac-подобных редакторов) — см. `textView(_:clickedOnLink:at:)`.
        // Курсор оставляем IBeam (без .cursor override): pointingHand создавал бы
        // ложное ощущение, что просто клик = открыть, а на деле для этого нужен ⌘.
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.allowsMagnification = true
        scrollView.minMagnification    = 0.25
        scrollView.maxMagnification    = 4.0

        storage.beginEditing()
        storage.setAttributedString(session.attributedText)
        storage.endEditing()

        if storage.length == 0 {
            textView.typingAttributes = DocumentSession.currentDefaultAttributes()
        }

        controller.textView = textView
        // v0.4.4 (R06): движки-компаньоны получают textView после того, как он
        // создан (в attach(session:) он ещё nil, потому что makeNSView вызывается
        // позже). Дублируем присвоение здесь — безопасно (weak, идемпотентно).
        controller.comments.textView = textView
        controller.trackChanges.textView = textView
        context.coordinator.scrollView = scrollView
        controller.syncReviewFlags()  // v0.1.56: подхватить дефолты spelling/substitutions

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnificationChanged(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        DispatchQueue.main.async { controller.refreshSelectionState() }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              let storage  = textView.textStorage else { return }

        if abs(nsView.magnification - CGFloat(controller.zoomLevel)) > 0.001 {
            nsView.magnification = CGFloat(controller.zoomLevel)
        }

        if !context.coordinator.isInternalUpdate,
           !storage.matches(session.attributedText) {
            context.coordinator.isInternalUpdate = true
            let sel = textView.selectedRanges
            storage.beginEditing()
            storage.setAttributedString(session.attributedText)
            storage.endEditing()
            textView.selectedRanges = sel
            if storage.length == 0 {
                textView.typingAttributes = DocumentSession.currentDefaultAttributes()
            }
            context.coordinator.isInternalUpdate = false
            // v1.8.7: НЕ взводим pendingInitialFit здесь. Ветка re-sync может
            // сработать не только при open/new/reset, но и при любом расхождении
            // storage↔session.attributedText (например, побочные эффекты
            // updateFloatingImages / applyPageViewStyle на 155.docx). Если
            // autofit срабатывает повторно, он «отматывает» пользовательский
            // зум обратно к 75% → мерцание 100%↔160% (баг 2, v1.8.6 не закрыл
            // до конца). Fit взводится только явно — в attach(session:) и в
            // DocumentSession.replace(...) / reset().
        }

        // v1.6.9: смена режима MD↔DOCX сбрасывает масштаб к дефолту режима.
        // Иначе авто-фит DOCX (v1.6.7) уносит zoom (например, 191%), и MD-«лента»
        // при переключении в MD рисуется в масштабе, при котором колонка не
        // помещается и уезжает за край окна.
        if context.coordinator.lastRenderedMode != session.mode {
            let prev = context.coordinator.lastRenderedMode
            context.coordinator.lastRenderedMode = session.mode
            if prev != nil {
                switch session.mode {
                case .markdown:
                    controller.pendingInitialFit = false
                    nsView.magnification = 1.0
                    controller.zoomLevel = 1.0
                case .docx:
                    controller.pendingInitialFit = true
                }
            }
        }

        // v1.2.4: applyPageViewStyle читает usedRect() для расчёта pageCount и
        // высоты textView. Если вызвать ДО синка storage, при открытии многостраничного
        // документа usedRect ещё пустой (storage только что был очищен/пуст),
        // pageCount=1 → фрейм высотой в одну страницу → нельзя прокрутить. Ввод любого
        // символа триггерил повторный updateNSView с уже наполненным storage —
        // пересчёт «оживлял» скролл. Фикс: считать после синка.
        applyPageViewStyle(nsView, textView: textView)
        // v1.5.12: плавающие картинки — после раскладки/синка.
        context.coordinator.updateFloatingImages()
    }

    private func applyPageViewStyle(_ scroll: NSScrollView, textView: NSTextView) {
        let ps = session.bridge.model.pageSettings
        let container = textView.textContainer as? PaginatedTextContainer
        // v1.4.1 (ADR-049): в MD-режиме вид страницы отключён — у Markdown
        // нет страниц/полей/колонтитулов, всегда обычный вид.
        if controller.isPageView, session.mode == .docx {
            let size = ps.pageSizeInPoints
            let margins = ps.margins
            let usableW = max(1, size.width - margins.left - margins.right)
            let usableH = max(1, size.height - margins.top - margins.bottom)
            let gap = DocxTextView.sheetGap
            scroll.backgroundColor = DocxTextView.sheetField
            textView.drawsBackground = true
            textView.autoresizingMask = [.width]
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // v1.8.6: устанавливаем свойства контейнера/frame ТОЛЬКО при реальном
            // изменении. Прежняя безусловная запись containerSize/pageStride/
            // pageContentHeight/frame.size инвалидировала layout NSTextContainer,
            // каскадно триггерила SwiftUI updateNSView заново → бесконечный loop
            // на документах с богатой раскладкой (155.docx с 32 плавающими +
            // таблицами держал 99% CPU и вызывал видимое мерцание).
            if container?.widthTracksTextView != false {
                container?.widthTracksTextView = false
            }
            let newContainerSize = NSSize(width: usableW, height: CGFloat.greatestFiniteMagnitude)
            if let c = container, c.containerSize != newContainerSize {
                c.containerSize = newContainerSize
            }
            if container?.paged != true { container?.paged = true }
            let newPageStride = size.height + gap
            if let c = container, abs(c.pageStride - newPageStride) > 0.01 {
                c.pageStride = newPageStride
            }
            if let c = container, abs(c.pageContentHeight - usableH) > 0.01 {
                c.pageContentHeight = usableH
            }

            let viewW = max(size.width + 80, scroll.contentSize.width)
            if textView.frame.origin.x != 0 { textView.frame.origin.x = 0 }
            if abs(textView.frame.size.width - viewW) > 0.5 {
                textView.frame.size.width = viewW
            }

            // v1.6.7: авто-подгонка масштаба при первом открытии — лист должен
            // занимать ~75% ширины окна. Учитываем текущий magnification: viewport
            // в неотмасштабированных координатах = clipView.frame.width / magn.
            if controller.pendingInitialFit,
               scroll.contentSize.width > 40, size.width > 0 {
                let currentMagn = max(scroll.magnification, 0.01)
                let unscaledViewportW = scroll.contentSize.width / currentMagn
                let target = DocumentController.initialFitFraction * unscaledViewportW / size.width
                let clamped = max(0.25, min(4.0, Double(target)))
                controller.pendingInitialFit = false
                DispatchQueue.main.async {
                    controller.setZoom(clamped)
                }
            }
            if let dt = textView as? DocxTextView {
                dt.showsPageSheet = true
                dt.pageSheetWidth = size.width
                dt.sheetUsableWidth = usableW
                dt.sheetTopInset = margins.top
                dt.sheetPageHeight = size.height
                dt.sheetMarginLeft = margins.left
                dt.sheetMarginRight = margins.right
                dt.sheetMarginBottom = margins.bottom
                let hf = session.bridge.model.headerFooter
                dt.headerText = hf.headerText
                dt.footerText = hf.footerText
                dt.headerAlign = hf.headerAlignment.nsAlignment
                dt.footerAlign = hf.footerAlignment.nsAlignment
                dt.differentFirstPage = hf.differentFirstPage
                dt.firstHeaderText = hf.firstHeaderText
                dt.firstFooterText = hf.firstFooterText
                dt.firstHeaderAlign = hf.firstHeaderAlignment.nsAlignment
                dt.firstFooterAlign = hf.firstFooterAlignment.nsAlignment
                dt.differentOddEven = hf.differentOddEven
                dt.evenHeaderText = hf.evenHeaderText
                dt.evenFooterText = hf.evenFooterText
                dt.evenHeaderAlign = hf.evenHeaderAlignment.nsAlignment
                dt.evenFooterAlign = hf.evenFooterAlignment.nsAlignment
                // v1.5.3: плавающие изображения колонтитулов из passthrough-
                // частей (только если колонтитул не редактировался — тогда
                // части регенерируются без графики).
                dt.hfImages = [:]
                dt.hfWatermarks = [:]
                if !session.bridge.model.headerFooterEdited {
                    for (slot, part) in session.bridge.model.preservedHeaderFooter {
                        for img in part.images {
                            guard let data = part.media[img.mediaName],
                                  let ns = NSImage(data: data) else { continue }
                            dt.hfImages[slot, default: []].append((
                                image: ns,
                                x: CGFloat(img.xEMU) / 12700.0,
                                y: CGFloat(img.yEMU) / 12700.0,
                                w: CGFloat(img.cxEMU) / 12700.0,
                                h: CGFloat(img.cyEMU) / 12700.0))
                        }
                        // v1.5.14: водяные знаки слота (VML).
                        for wm in part.watermarks {
                            var ns: NSImage? = nil
                            if let mn = wm.mediaName, let data = part.media[mn] {
                                ns = NSImage(data: data)
                            }
                            dt.hfWatermarks[slot, default: []].append((wm, ns))
                        }
                    }
                }
                dt.updateSheetInset()
                // Число листов — из фактической раскладки.
                if let lm = textView.layoutManager, let c = textView.textContainer {
                    lm.ensureLayout(for: c)
                    let usedMaxY = lm.usedRect(for: c).maxY
                    let stride = size.height + gap
                    dt.pageCount = max(1, Int(floor(max(0, usedMaxY - 0.5) / stride)) + 1)
                }
                // Высота вью = все листы + промежутки (последний лист виден целиком).
                let totalH = gap + CGFloat(dt.pageCount) * (size.height + gap)
                // v1.8.6: guard от лишних setFrameSize → updateSheetInset →
                // layout-invalidate каскада (см. ADR-060, комментарий выше).
                if abs(textView.frame.size.height - totalH) > 0.5 {
                    textView.frame.size.height = totalH
                }
                dt.needsDisplay = true
            }
        } else {
            // v1.5.8: читаемая колонка в MD-режиме (iA Writer/Typora-паттерн) —
            // ограниченная ширина текста, центрированная в окне. Настройка
            // Preferences → Основные; full — во всю ширину (поведение до v1.5.8).
            let mdColW: CGFloat? = (session.mode == .markdown)
                ? AppPreferences.shared.markdownColumnWidth.points : nil
            // v1.6.8: если активна MD-«лента» — серое поле окна + белая колонка
            // (границы редактируемой области). Фон textView отключаем: его
            // рисует DocxTextView.drawBackground.
            if mdColW != nil {
                scroll.backgroundColor = DocxTextView.sheetField
                textView.drawsBackground = false
            } else {
                scroll.backgroundColor = .textBackgroundColor
                textView.drawsBackground = true
                textView.backgroundColor = .textBackgroundColor
            }
            textView.autoresizingMask = [.width]
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            container?.paged = false
            if let colW = mdColW {
                container?.widthTracksTextView = false
                container?.containerSize = NSSize(width: colW, height: CGFloat.greatestFiniteMagnitude)
            } else {
                container?.widthTracksTextView = true
                let w = max(1, scroll.contentSize.width - 2)
                container?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
            }
            textView.frame.origin.x = 0
            textView.frame.size.width = max(1, scroll.contentSize.width)
            if let dt = textView as? DocxTextView {
                dt.showsPageSheet = false
                dt.mdColumnWidth = mdColW ?? 0
                if mdColW != nil { dt.updateMdColumnInset() }
                else { textView.textContainerInset = NSSize(width: 32, height: 32) }
                dt.needsDisplay = true
            } else {
                textView.textContainerInset = NSSize(width: 32, height: 32)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let controller: DocumentController
        var isInternalUpdate = false
        weak var scrollView: NSScrollView?
        /// v1.6.9: последний режим, для которого выполнялся applyPageViewStyle.
        /// При переключении MD↔DOCX сбрасываем масштаб к дефолту режима
        /// (иначе авто-фит DOCX уносит zoom, и MD-«лента» уезжает за край окна).
        var lastRenderedMode: DocumentMode?

        /// v1.3.0 multi-doc: уведомления форматирования обрабатывает только Coordinator
        /// текущего key window. Иначе ⌘B из одного окна применил бы жирный во всех окнах.
        fileprivate var isKeyForNotifications: Bool {
            scrollView?.window?.isKeyWindow == true
        }

        /// Подписка на уведомление форматирования с фильтром «моё окно ключевое?».
        /// Селекторы БЕЗ аргумента.
        private func observeKeyZero(_ name: Notification.Name, _ selector: Selector) {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isKeyForNotifications else { return }
                _ = self.perform(selector)
            }
        }
        /// То же для селекторов с параметром `Notification`.
        private func observeKeyNote(_ name: Notification.Name, _ selector: Selector) {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, self.isKeyForNotifications else { return }
                _ = self.perform(selector, with: note)
            }
        }

        init(controller: DocumentController) {
            self.controller = controller
            super.init()
            observeKeyZero(.docxEditToggleBold, #selector(onToggleBold))
            observeKeyZero(.docxEditToggleItalic, #selector(onToggleItalic))
            observeKeyZero(.docxEditToggleUnderline, #selector(onToggleUnderline))
            observeKeyZero(.docxEditToggleStrikethrough, #selector(onToggleStrikethrough))
            observeKeyZero(.docxEditToggleSuperscript, #selector(onToggleSuperscript))
            observeKeyZero(.docxEditToggleSubscript, #selector(onToggleSubscript))
            observeKeyNote(.docxEditChangeCase, #selector(onChangeCase(_:)))
            observeKeyZero(.docxEditCopyFormatting, #selector(onCopyFormatting))
            observeKeyZero(.docxEditPasteFormatting, #selector(onPasteFormatting))
            observeKeyNote(.docxEditApplyHighlight, #selector(onApplyHighlight(_:)))
            observeKeyZero(.docxEditShowRowHeight, #selector(onShowRowHeight))
            observeKeyZero(.docxEditShowParagraphIndents, #selector(onShowParagraphIndents))
            observeKeyZero(.docxEditShowFindReplace, #selector(onShowFindReplace))
            observeKeyZero(.docxEditShowImageCrop, #selector(onShowImageCrop))
            observeKeyZero(.docxEditShowDocumentProperties, #selector(onShowDocumentProperties))
            observeKeyZero(.docxEditShowBookmarks, #selector(onShowBookmarks))
            observeKeyZero(.docxEditShowCustomDictionary, #selector(onShowCustomDictionary))
            observeKeyZero(.docxEditClearAutorecover, #selector(onClearAutorecover))
            observeKeyZero(.docxEditClearFormatting, #selector(onClearFormatting))
            observeKeyNote(.docxEditApplyFont, #selector(onApplyFont(_:)))
            observeKeyNote(.docxEditApplyFontSize, #selector(onApplyFontSize(_:)))
            observeKeyNote(.docxEditApplyAlignment, #selector(onApplyAlignment(_:)))
            observeKeyZero(.docxEditZoomIn, #selector(onZoomIn))
            observeKeyZero(.docxEditZoomOut, #selector(onZoomOut))
            observeKeyZero(.docxEditZoomReset, #selector(onZoomReset))
            observeKeyZero(.docxEditFitPageWidth, #selector(onFitPageWidth))
            observeKeyZero(.docxEditFitTwoPages, #selector(onFitTwoPages))
            observeKeyZero(.docxEditTogglePageView, #selector(onTogglePageView))
            observeKeyZero(.docxEditPageSettingsChanged, #selector(onPageSettingsChanged))
            observeKeyZero(.docxEditPageSettingsApplied, #selector(onPageSettingsApplied))
            observeKeyZero(.docxEditCheckSpelling, #selector(onCheckSpelling))
            observeKeyZero(.docxEditShowImportReport, #selector(onShowImportReport))
            observeKeyNote(.docxEditApplyLineSpacing, #selector(onApplyLineSpacing(_:)))
            observeKeyZero(.docxEditIncreaseIndent, #selector(onIncreaseIndent))
            observeKeyZero(.docxEditDecreaseIndent, #selector(onDecreaseIndent))
            observeKeyNote(.docxEditToggleList, #selector(onToggleList(_:)))
            observeKeyNote(.docxEditApplyListVariant, #selector(onApplyListVariant(_:)))
            observeKeyZero(.docxEditPasteAsPlainText, #selector(onPasteAsPlainText))
            observeKeyZero(.docxEditCopyAsMarkdown, #selector(onCopyAsMarkdown))
            observeKeyZero(.docxEditPasteAsMarkdown, #selector(onPasteAsMarkdown))
            observeKeyNote(.docxEditApplyParagraphStyle, #selector(onApplyParagraphStyle(_:)))
            observeKeyNote(.docxEditApplyCharacterStyle, #selector(onApplyCharacterStyle(_:)))
            observeKeyZero(.docxEditToggleInvisibles, #selector(onToggleInvisibles))
            observeKeyZero(.docxEditToggleRuler, #selector(onToggleRuler))
            observeKeyZero(.docxEditToggleStylesSidebar, #selector(onToggleStylesSidebar))
            observeKeyZero(.docxEditToggleNavigatorSidebar, #selector(onToggleNavigatorSidebar))
            observeKeyZero(.docxEditToggleReadingMode, #selector(onToggleReadingMode))
            observeKeyZero(.docxEditToggleCommentsSidebar, #selector(onToggleCommentsSidebar))
            observeKeyZero(.docxEditToggleFootnotesSidebar, #selector(onToggleFootnotesSidebar))
            observeKeyZero(.docxEditInsertComment, #selector(onInsertComment))
            observeKeyZero(.docxEditToggleTrackChanges, #selector(onToggleTrackChanges))
            observeKeyZero(.docxEditAcceptAllChanges, #selector(onAcceptAllChanges))
            observeKeyZero(.docxEditRejectAllChanges, #selector(onRejectAllChanges))
            observeKeyZero(.docxEditGoToNextRevision, #selector(onGoToNextRevision))
            observeKeyZero(.docxEditAcceptCurrentRev, #selector(onAcceptCurrentRev))
            observeKeyZero(.docxEditRejectCurrentRev, #selector(onRejectCurrentRev))
            observeKeyZero(.docxEditShowStatistics, #selector(onShowStatistics))
            observeKeyZero(.docxEditShowFind, #selector(onShowFind))
            observeKeyZero(.docxEditShowReplace, #selector(onShowReplace))
            observeKeyZero(.docxEditPrint, #selector(onPrint))
            observeKeyZero(.docxEditShowFontReplace, #selector(onShowFontReplace))
            observeKeyZero(.docxEditShowGoTo, #selector(onShowGoTo))
            observeKeyZero(.docxEditShowStyles, #selector(onShowStyles))
            observeKeyZero(.docxEditInsertPageBreak, #selector(onInsertPageBreak))
            observeKeyZero(.docxEditTogglePageNumbers, #selector(onTogglePageNumbers))
            observeKeyZero(.docxEditShowHeaderFooter, #selector(onShowHeaderFooter))
            observeKeyZero(.docxEditShowInsertTable, #selector(onShowInsertTable))
            observeKeyNote(.docxEditTableEdit, #selector(onTableEdit(_:)))
            observeKeyZero(.docxEditShowTableProperties, #selector(onShowTableProperties))
            observeKeyZero(.docxEditInsertImage, #selector(onInsertImage))
            observeKeyZero(.docxEditShowHyperlink, #selector(onShowHyperlink))
            observeKeyZero(.docxEditInsertFootnote, #selector(onInsertFootnote))
            observeKeyZero(.docxEditInsertEndnote, #selector(onInsertEndnote))
            observeKeyZero(.docxEditInsertTOC, #selector(onInsertTOC))
            observeKeyZero(.docxEditUpdateTOC, #selector(onUpdateTOC))
            observeKeyZero(.docxEditShowCrossReference, #selector(onShowCrossReference))
            observeKeyZero(.docxEditShowImageProperties, #selector(onShowImageProperties))
            observeKeyZero(.docxEditShowMergeCells, #selector(onShowMergeCells))
            observeKeyZero(.docxEditShowSymbol, #selector(onShowSymbol))
            observeKeyNote(.docxEditInsertDateTime, #selector(onInsertDateTime(_:)))
            observeKeyNote(.docxEditInsertText, #selector(onInsertText(_:)))

            // Универсальный фикс клавиатурных шорткатов на кириллической (РУ) и других
            // нелатинских раскладках (v1.5.13; развитие ADR-027). SwiftUI .keyboardShortcut
            // молча не срабатывает для буквенных клавиш: charactersIgnoringModifiers на РУ
            // даёт кириллицу («и» вместо «b»). Решение — сопоставление по физическому
            // keyCode (layout-independent). Для пунктуационных клавиш ([ ] { } | :)
            // charactersIgnoringModifiers отдаёт латинский символ корректно (ADR-027),
            // поэтому они сопоставляются по chars. Событие гасим (return nil), чтобы не
            // дублировать на раскладках, где сработал бы и штатный SwiftUI-шорткат
            // (монитор отрабатывает раньше).
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.scrollView?.window, window.isKeyWindow else { return event }
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers ?? ""

                // Буквенные шорткаты — по физическому keyCode (US-позиции клавиш).
                // v1.6.4: в MD source-режиме ⌘B/⌘I оборачивают выделение в **…** / *…*.
                if appDelegate.currentSession?.isMarkdownSourceMode == true {
                    switch (mods, event.keyCode) {
                    case (.command, 11): Self.wrapMarkdownSelection("**"); return nil   // ⌘B
                    case (.command, 34): Self.wrapMarkdownSelection("*"); return nil    // ⌘I
                    default: break
                    }
                }
                switch (mods, event.keyCode) {
                case (.command, 11): appDelegate.toggleBold(); return nil            // ⌘B
                case (.command, 34): appDelegate.toggleItalic(); return nil          // ⌘I
                case (.command, 32): appDelegate.toggleUnderline(); return nil       // ⌘U
                case ([.command, .shift], 7): appDelegate.toggleStrikethrough(); return nil  // ⇧⌘X
                case (.command, 45): appDelegate.newDocument(); return nil           // ⌘N
                case ([.command, .shift], 45): appDelegate.newMarkdownDocument(); return nil // ⇧⌘N
                case (.command, 31): appDelegate.openDocument(); return nil          // ⌘O
                case (.command, 1): appDelegate.saveDocument(); return nil           // ⌘S
                case ([.command, .shift], 1): appDelegate.saveDocumentAs(); return nil       // ⇧⌘S
                case ([.command, .option, .shift], 1): appDelegate.showStyles(); return nil  // ⇧⌥⌘S
                case ([.command, .shift], 14): appDelegate.toggleTrackChanges(); return nil  // ⇧⌘E
                case ([.command, .option], 14): appDelegate.exportPDF(); return nil          // ⌥⌘E
                case (.command, 35): appDelegate.printDocument(); return nil         // ⌘P
                case ([.command, .option], 35): appDelegate.togglePageView(); return nil     // ⌥⌘P
                case ([.command, .shift, .option], 9): self.controller.pasteAsPlainText(); return nil // ⇧⌥⌘V
                case ([.command, .shift], 9): appDelegate.pasteFormatting(); return nil      // ⇧⌘V (paste format)
                case ([.command, .shift], 8): appDelegate.copyFormatting(); return nil       // ⇧⌘C (copy format)
                case (.command, 3): appDelegate.findInDocument(); return nil         // ⌘F
                case ([.command, .option], 3): appDelegate.insertFootnote(); return nil      // ⌥⌘F (сноска, Word)
                case ([.command, .shift], 3): appDelegate.showFindReplace(); return nil      // ⇧⌘F
                case ([.command, .shift], 4): appDelegate.replaceInDocument(); return nil    // ⇧⌘H (Replace, Word)
                case ([.command, .option], 5): self.controller.showGoToDialog(); return nil  // ⌥⌘G
                case (.command, 40): appDelegate.showBookmarks(); return nil         // ⌘K
                case ([.command, .option], 17): appDelegate.insertTable(); return nil        // ⌥⌘T
                case ([.command, .option], 46): appDelegate.insertCommentAtSelection(); return nil // ⌥⌘M
                case ([.command, .option], 15): appDelegate.toggleRuler(); return nil        // ⌥⌘R
                case ([.command, .shift], 15): appDelegate.toggleReadingMode(); return nil   // ⇧⌘R
                case (.command, 47): appDelegate.toggleMarkdownSourceMode(); return nil      // ⌘/ (MD source)
                case ([.command, .option], 47): appDelegate.toggleMarkdownHybridMode(); return nil // ⌥⌘/ (MD гибрид)
                default: break
                }

                // Пунктуационные шорткаты — по charactersIgnoringModifiers (на РУ
                // отдаёт латинский символ корректно, см. ADR-027). { } | : на US-
                // раскладке набираются с Shift, поэтому модификаторы включают shift.
                switch (mods, chars) {
                case (.command, "]"): self.controller.increaseIndent(); return nil
                case (.command, "["): self.controller.decreaseIndent(); return nil
                case ([.command, .shift], "{"): appDelegate.applyAlignment(.left); return nil
                case ([.command, .shift], "}"): appDelegate.applyAlignment(.right); return nil
                case ([.command, .shift], "|"): appDelegate.applyAlignment(.center); return nil
                case ([.command, .option, .shift], "}"): appDelegate.applyAlignment(.justified); return nil
                case ([.command, .shift], "]"): appDelegate.goToNextRevision(); return nil
                case ([.command, .shift], ":"): appDelegate.reviewCheckSpelling(); return nil
                default: break
                }
                return event
            }
        }
        deinit {
            NotificationCenter.default.removeObserver(self)
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }

        private var keyMonitor: Any?

        /// v1.6.4: обёртка выделения в Markdown-разметку в source-режиме
        /// (⌘B → **…**, ⌘I → *…*). Работает с first-responder NSTextView
        /// исходника. Без выделения — вставляет пару маркеров и ставит курсор
        /// между ними.
        static func wrapMarkdownSelection(_ marker: String) {
            guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            let sel = tv.selectedRange()
            let storage = tv.textStorage
            if sel.length > 0, let storage {
                let text = storage.attributedSubstring(from: sel).string
                // Снятие: выделение уже обёрнуто — развернуть.
                if text.hasPrefix(marker), text.hasSuffix(marker),
                   text.count > marker.count * 2 {
                    let inner = String(text.dropFirst(marker.count).dropLast(marker.count))
                    tv.insertText(inner, replacementRange: sel)
                    return
                }
                tv.insertText(marker + text + marker, replacementRange: sel)
                tv.setSelectedRange(NSRange(location: sel.location + marker.count,
                                            length: (text as NSString).length))
            } else {
                tv.insertText(marker + marker, replacementRange: sel)
                tv.setSelectedRange(NSRange(location: sel.location + marker.count, length: 0))
            }
        }
        var fontReplaceWindow: NSWindow?
        var headerFooterWindow: NSWindow?
        var insertTableWindow: NSWindow?
        var tablePropertiesWindow: NSWindow?
        var hyperlinkWindow: NSWindow?
        var symbolWindow: NSWindow?
        var imagePropertiesWindow: NSWindow?
        var mergeCellsWindow: NSWindow?
        var importReportWindow: NSWindow?
        var rowHeightWindow: NSWindow?
        var paragraphIndentsWindow: NSWindow?
        var findReplaceWindow: NSWindow?
        var imageCropWindow: NSWindow?
        var documentPropertiesWindow: NSWindow?
        var bookmarksWindow: NSWindow?
        var customDictionaryWindow: NSWindow?
        var goToWindow: NSWindow?
        var stylesWindow: NSWindow?
        var statisticsWindow: NSWindow?
        // v0.1.67: overlay-view с угловыми ручками ресайза выделенного изображения.
        var imageResizeOverlay: ImageResizeOverlay?

        @objc func magnificationChanged(_ n: Notification) {
            if let sv = scrollView { controller.zoomLevel = Double(sv.magnification) }
        }

        @objc private func onToggleBold()          { controller.toggleBold() }
        @objc private func onToggleItalic()        { controller.toggleItalic() }
        @objc private func onToggleUnderline()     { controller.toggleUnderline() }
        @objc private func onToggleStrikethrough() { controller.toggleStrikethrough() }
        @objc private func onToggleSuperscript()   { controller.toggleSuperscript() }
        @objc private func onToggleSubscript()     { controller.toggleSubscriptStyle() }
        @objc private func onChangeCase(_ n: Notification) {
            let raw = (n.object as? NSString) as String? ?? ""
            let mode: DocumentController.ChangeCaseMode
            switch raw {
            case "upper":    mode = .upper
            case "lower":    mode = .lower
            case "title":    mode = .title
            case "sentence": mode = .sentence
            case "toggle":   mode = .toggleCase
            default: return
            }
            controller.applyChangeCase(mode)
        }
        @objc private func onCopyFormatting()      { controller.copyFormatting() }
        @objc private func onPasteFormatting()     { controller.pasteFormatting() }
        @objc private func onApplyHighlight(_ n: Notification) {
            controller.applyHighlightColor(n.object as? NSColor)
        }
        @objc private func onClearFormatting()     { controller.clearFormatting() }
        @objc private func onZoomIn()              { controller.zoomIn() }
        @objc private func onZoomOut()             { controller.zoomOut() }
        @objc private func onZoomReset()           { controller.resetZoom() }
        @objc private func onFitPageWidth()        { controller.fitPageWidth() }
        @objc private func onFitTwoPages()         { controller.fitTwoPages() }
        @objc private func onTogglePageView()      { controller.togglePageView() }

        /// v0.1.56: настройки страницы поменялись в Preferences → применяем к
        /// открытому документу (не только к новым). Пробрасываем в controller;
        /// он обновляет модель, `session.markDirty()` шлёт objectWillChange —
        /// SwiftUI пересобирает `TextEditorRepresentable`, `updateNSView`
        /// вызывает `applyPageViewStyle` со свежими размерами/полями.
        @objc private func onPageSettingsChanged(_ note: Notification) {
            guard let ps = note.object as? PageSettings else { return }
            controller.setPageSettings(ps)
        }
        @objc private func onPageSettingsApplied() {
            // Дополнительно кикаем isPageView — updateNSView гарантированно
            // перерисует макет с новыми размерами A4 landscape/portrait.
            let cur = controller.isPageView
            controller.isPageView = !cur
            controller.isPageView = cur
        }
        @objc private func onCheckSpelling() { controller.showSpellingChecker() }

        @objc private func onShowImportReport() {
            guard let session = controller.session else { return }
            if let existing = importReportWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = ImportReportView(session: session, onClose: { [weak self] in
                self?.importReportWindow?.close()
            })
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Отчёт об открытии"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            importReportWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        @objc private func onIncreaseIndent()      { controller.increaseIndent() }
        @objc private func onDecreaseIndent()      { controller.decreaseIndent() }
        @objc private func onToggleList(_ n: Notification) {
            guard let raw = n.object as? String, let type = ListType(rawValue: raw) else { return }
            controller.toggleList(type)
        }
        @objc private func onApplyListVariant(_ n: Notification) {
            guard let id = n.object as? String else { return }
            controller.applyListVariant(id: id)
        }
        @objc private func onPasteAsPlainText() { controller.pasteAsPlainText() }
        @objc private func onCopyAsMarkdown() { controller.copyAsMarkdown() }
        @objc private func onPasteAsMarkdown() { controller.pasteAsMarkdown() }
        @objc private func onApplyParagraphStyle(_ n: Notification) {
            guard let id = n.object as? String else { return }
            controller.applyParagraphStyle(id: id)
        }
        @objc private func onApplyCharacterStyle(_ n: Notification) {
            controller.applyCharacterStyle(id: n.object as? String)
        }
        @objc private func onInsertPageBreak() { controller.insertPageBreak() }

        // MARK: NSTextViewDelegate

        /// v0.4.6 (R06): перехват правки при включённом track-changes.
        /// Делегирует движку; если движок вернул false — правка отменена
        /// (например, удаление сохранено как пометка вместо реального delete).
        func textView(_ view: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard controller.trackChanges.isRecording else { return true }
            return controller.trackChanges.interceptChange(range: affectedCharRange,
                                                         replacementString: replacementString)
        }

        /// Клик по ссылке в редакторе — открытие в браузере только при **Cmd+клик**
        /// (v0.1.55, паттерн Mac-подобных редакторов). Обычный клик возвращает false, тогда
        /// NSTextView ставит курсор внутрь ссылки — можно редактировать текст,
        /// вызывать ⌘K для смены URL/удаления, ставить символы рядом. Без Cmd
        /// открывать нельзя — иначе в ссылку не попасть курсором.
        func textView(_ view: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            guard mods.contains(.command) else { return false }
            let urlStr: String
            if let s = link as? String { urlStr = s }
            else if let u = link as? URL { urlStr = u.absoluteString }
            else { return false }
            guard let url = URL(string: urlStr) else { return false }
            NSWorkspace.shared.open(url)
            return true
        }

        /// Tab / Shift+Tab внутри абзаца списка — смена уровня вложенности
        /// (как принято в текстовых редакторах). В обычном тексте пропускаем Tab по умолчанию (табуляция).
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                if controller.currentListType != nil {
                    controller.increaseIndent()
                    return true
                }
            case #selector(NSResponder.insertBacktab(_:)):
                if controller.currentListType != nil {
                    controller.decreaseIndent()
                    return true
                }
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // v1.4.3 (ADR-049): Return на ПУСТОМ элементе списка/пустой
                // цитате в MD-режиме — выход из структуры, а не новый пункт.
                if controller.handleReturnOnEmptyMarkdownStructure() { return true }
                // Return в списке добавляет новый пункт — после вставки абзаца
                // перенумеровываем блок (новый пункт получает свой номер, следующие
                // сдвигаются). Удаление НЕ перехватываем: маркеры — литеральный текст,
                // и Backspace у начала содержимого «съедал» бы символы маркера
                // (числа после удаления пункта обновятся при следующей операции списка).
                if controller.caretInListBlock() { controller.pendingListRenumber = true }
            default: break
            }
            return false
        }

        /// Кастомизация контекстного меню NSTextView (v0.1.55):
        /// - удаляем шумные подменю Правописание/Замены/Ориентация макета (не к месту в редакторе);
        /// - добавляем «Вставить с сохранением стиля» после стандартной «Вставить»;
        /// - добавляем «Гиперссылка… ⌘K» (+ «Удалить ссылку» если курсор внутри ссылки).
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // 1. Убираем подменю/пункты, которых в Mac-подобных редакторов в контекстном
            //    меню нет: они переедут в тулбар/меню в R05 (Проверка правописания).
            //    Матчим по частям и русского и английского названия — macOS локализует
            //    заголовок в зависимости от системной локали.
            let dropSubstrings: [String] = [
                "правопис", "spelling", "grammar",
                "замен",    "substitut",           // «Замены» — Smart Quotes/Dashes/Data Detectors
                "ориентац", "layout orientation",
                "речь",    "speech",              // «Речь» → Начать разговор — тоже лишнее
            ]
            for item in menu.items.reversed() {
                let title = item.title.lowercased()
                if dropSubstrings.contains(where: { title.contains($0) }) {
                    menu.removeItem(item)
                }
            }
            // Схлопываем случайно образовавшиеся подряд-разделители/финальный разделитель.
            var prevWasSeparator = true
            for item in menu.items {
                if item.isSeparatorItem {
                    if prevWasSeparator { menu.removeItem(item) }
                    prevWasSeparator = true
                } else {
                    prevWasSeparator = false
                }
            }
            if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }

            // 2. «Вставить с сохранением стиля» — сразу после «Вставить».
            let pasteIndex = menu.items.firstIndex { $0.action == #selector(NSText.paste(_:)) }
            let hasText = NSPasteboard.general.availableType(from: [.string, .rtf, .html]) != nil
            let pastePlain = NSMenuItem(title: "Вставить с сохранением стиля",
                                        action: #selector(onPasteAsPlainText),
                                        keyEquivalent: "V")
            pastePlain.keyEquivalentModifierMask = [.command, .shift, .option]
            pastePlain.target = self
            pastePlain.isEnabled = hasText
            if let idx = pasteIndex {
                menu.insertItem(pastePlain, at: idx + 1)
            } else {
                menu.addItem(pastePlain)
            }

            // 3. Гиперссылка — в конце меню отдельной группой.
            menu.addItem(.separator())
            let hyperlink = NSMenuItem(title: "Гиперссылка…",
                                       action: #selector(onContextHyperlink),
                                       keyEquivalent: "k")
            hyperlink.keyEquivalentModifierMask = [.command]
            hyperlink.target = self
            menu.addItem(hyperlink)
            if controller.hyperlinkAtCaret() != nil {
                let remove = NSMenuItem(title: "Удалить ссылку",
                                        action: #selector(onContextRemoveHyperlink),
                                        keyEquivalent: "")
                remove.target = self
                menu.addItem(remove)
            }
            // 4. Изображение — если правый клик пришёлся на аттачмент.
            if let storage = view.textStorage, charIndex >= 0, charIndex < storage.length,
               storage.attribute(.attachment, at: charIndex, effectiveRange: nil) is NSTextAttachment {
                // Ставим курсор на изображение, чтобы imageRangeAtCaret его нашёл.
                view.setSelectedRange(NSRange(location: charIndex, length: 1))
                menu.addItem(.separator())
                let props = NSMenuItem(title: "Свойства изображения…",
                                       action: #selector(onContextImageProperties),
                                       keyEquivalent: "")
                props.target = self
                menu.addItem(props)
                let del = NSMenuItem(title: "Удалить изображение",
                                     action: #selector(onContextDeleteImage),
                                     keyEquivalent: "")
                del.target = self
                menu.addItem(del)
                // Выравнивание изображения (v0.1.69) — действует на абзац с U+FFFC.
                let alignSub = NSMenu(title: "Выравнивание")
                let alignItems: [(String, Selector)] = [
                    ("Слева",     #selector(onCtxImageAlignLeft)),
                    ("По центру", #selector(onCtxImageAlignCenter)),
                    ("Справа",    #selector(onCtxImageAlignRight)),
                ]
                for (title, sel) in alignItems {
                    let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                    it.target = self
                    alignSub.addItem(it)
                }
                let alignHead = NSMenuItem(title: "Выравнивание", action: nil, keyEquivalent: "")
                alignHead.submenu = alignSub
                menu.addItem(alignHead)
            }
            // 5. Таблица — если курсор в таблице, добавляем подменю «Изменить таблицу»
            // как в меню Вставка (v0.1.62).
            if controller.isCaretInTable {
                menu.addItem(.separator())
                let submenu = NSMenu(title: "Изменить таблицу")
                let items: [(String, Selector)] = [
                    ("Добавить строку выше",      #selector(onCtxTableAddRowAbove)),
                    ("Добавить строку ниже",      #selector(onCtxTableAddRowBelow)),
                    ("SEP", Selector("")),
                    ("Добавить столбец слева",    #selector(onCtxTableAddColumnLeft)),
                    ("Добавить столбец справа",   #selector(onCtxTableAddColumnRight)),
                    ("SEP", Selector("")),
                    ("Объединить ячейки…",        #selector(onCtxTableMergeCells)),
                    ("Разделить ячейку",          #selector(onCtxTableSplitCell)),
                    ("SEP", Selector("")),
                    (controller.isCurrentRowHeader
                        ? "✓ Строка-заголовок таблицы"
                        : "Строка-заголовок таблицы", #selector(onCtxTableToggleHeaderRow)),
                    ("Высота строки…",           #selector(onCtxTableRowHeight)),
                    ("SEP", Selector("")),
                    ("Удалить строку",            #selector(onCtxTableDeleteRow)),
                    ("Удалить столбец",           #selector(onCtxTableDeleteColumn)),
                    ("Удалить таблицу",           #selector(onCtxTableDeleteTable)),
                    ("SEP", Selector("")),
                    ("Свойства таблицы…",         #selector(onCtxTableProperties)),
                ]
                for (title, sel) in items {
                    if title == "SEP" { submenu.addItem(.separator()); continue }
                    let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                    it.target = self
                    submenu.addItem(it)
                }
                let head = NSMenuItem(title: "Изменить таблицу", action: nil, keyEquivalent: "")
                head.submenu = submenu
                menu.addItem(head)
            }
            return menu
        }
        @objc private func onCtxTableToggleHeaderRow() { controller.applyTableEdit(.toggleHeaderRow) }
        @objc private func onCtxTableRowHeight() { onShowRowHeight() }
        @objc private func onCtxTableAddRowAbove()    { controller.applyTableEdit(.addRowAbove) }
        @objc private func onCtxTableAddRowBelow()    { controller.applyTableEdit(.addRowBelow) }
        @objc private func onCtxTableAddColumnLeft()  { controller.applyTableEdit(.addColumnLeft) }
        @objc private func onCtxTableAddColumnRight() { controller.applyTableEdit(.addColumnRight) }
        @objc private func onCtxTableMergeCells()     { NotificationCenter.default.post(name: .docxEditShowMergeCells, object: nil) }
        @objc private func onCtxTableSplitCell()      { controller.applyTableEdit(.splitCell) }
        @objc private func onCtxTableDeleteRow()      { controller.applyTableEdit(.deleteRow) }
        @objc private func onCtxTableDeleteColumn()   { controller.applyTableEdit(.deleteColumn) }
        @objc private func onCtxTableDeleteTable()    { controller.applyTableEdit(.deleteTable) }
        @objc private func onCtxTableProperties() {
            NotificationCenter.default.post(name: .docxEditShowTableProperties, object: nil)
        }
        @objc private func onContextHyperlink() {
            NotificationCenter.default.post(name: .docxEditShowHyperlink, object: nil)
        }
        @objc private func onContextRemoveHyperlink() {
            controller.removeHyperlink()
        }
        @objc private func onContextImageProperties() {
            NotificationCenter.default.post(name: .docxEditShowImageProperties, object: nil)
        }
        @objc private func onContextDeleteImage() {
            controller.deleteImageAtCaret()
        }
        @objc private func onCtxImageAlignLeft()   { controller.applyAlignment(.left) }
        @objc private func onCtxImageAlignCenter() { controller.applyAlignment(.center) }
        @objc private func onCtxImageAlignRight()  { controller.applyAlignment(.right) }
        @objc private func onShowFind()            { controller.showFindBar() }
        @objc private func onShowReplace()         { controller.showReplaceBar() }
        @objc private func onPrint() {
            guard let sv = scrollView, let tv = sv.documentView as? NSTextView else { return }
            let page = controller.session?.bridge.model.pageSettings ?? .a4Portrait
            let pi = NSPrintInfo(dictionary: [:])
            pi.paperSize = page.pageSizeInPoints
            pi.orientation = page.orientation == .landscape ? .landscape : .portrait
            // В «Виде страницы» поля и разбивка на страницы уже встроены в раскладку
            // NSTextView (PaginatedTextContainer + DocxTextView.knowsPageRange/
            // rectForPage). Печать должна маппить наш «лист» 1:1 в бумагу, поэтому
            // NSPrintInfo margins = 0 (иначе поля удваиваются — наши + системные).
            // verticalPagination = .automatic оставляем как fallback, но реально
            // печать разбивается через knowsPageRange (по числу листов), а не
            // через слайс по paperSize. В обычном виде (не Page View) фолбэк
            // отработает штатно.
            let isSheetMode = (tv as? DocxTextView)?.showsPageSheet == true
            if isSheetMode {
                pi.topMargin = 0
                pi.bottomMargin = 0
                pi.leftMargin = 0
                pi.rightMargin = 0
                pi.horizontalPagination = .fit
                pi.verticalPagination = .automatic
                pi.isHorizontallyCentered = false
                pi.isVerticallyCentered = false
            } else {
                pi.topMargin = page.margins.top
                pi.bottomMargin = page.margins.bottom
                pi.leftMargin = page.margins.left
                pi.rightMargin = page.margins.right
                pi.horizontalPagination = .fit
                pi.verticalPagination = .automatic
                pi.isHorizontallyCentered = true
                pi.isVerticallyCentered = false
            }
            let op = NSPrintOperation(view: tv, printInfo: pi)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }

        @objc private func onToggleInvisibles() { controller.toggleInvisibleCharacters() }
        @objc private func onToggleRuler()      { controller.toggleRuler() }
        @objc private func onToggleStylesSidebar() { controller.toggleStylesSidebar() }
        @objc private func onToggleNavigatorSidebar() { controller.toggleNavigatorSidebar() }
        @objc private func onToggleReadingMode()   { controller.toggleReadingMode() }
        @objc private func onToggleCommentsSidebar() {
            controller.toggleCommentsSidebar()
        }
        @objc private func onToggleFootnotesSidebar() {
            controller.toggleFootnotesSidebar()
        }
        @objc private func onToggleTrackChanges() { controller.trackChanges.toggle() }
        @objc private func onAcceptAllChanges()   { controller.trackChanges.acceptAll() }
        @objc private func onRejectAllChanges()   { controller.trackChanges.rejectAll() }
        @objc private func onGoToNextRevision()   { controller.trackChanges.goToNextRevision() }
        @objc private func onAcceptCurrentRev() {
            // Правка «под курсором» = та, чей range содержит caret; иначе — nextRevision.
            let engine = controller.trackChanges
            guard let tv = controller.textView else { return }
            let caret = tv.selectedRange().location
            let rev = engine.listRevisions().first { $0.range.contains(caret) }
                   ?? engine.nextRevision()
            if let r = rev { engine.acceptOne(r) }
        }
        @objc private func onRejectCurrentRev() {
            let engine = controller.trackChanges
            guard let tv = controller.textView else { return }
            let caret = tv.selectedRange().location
            let rev = engine.listRevisions().first { $0.range.contains(caret) }
                   ?? engine.nextRevision()
            if let r = rev { engine.rejectOne(r) }
        }

        @objc private func onInsertComment() {
            // Открываем панель, чтобы поле «Новый комментарий» получило фокус,
            // и подсказываем пользователю действие. Само создание — по кнопке
            // «+» в панели (после ввода текста); мы не создаём пустой тред.
            if !controller.showsCommentsSidebar { controller.toggleCommentsSidebar() }
        }

        @objc private func onShowStatistics() {
            if let existing = statisticsWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Статистика документа"
            window.isReleasedWhenClosed = false
            window.center()
            statisticsWindow = window

            let owner = self
            func stats() -> FullStatistics { owner.computeFullStatistics() }
            func rebuild() {
                let view = StatisticsView(
                    stats: stats(),
                    onRefresh: { rebuild() },
                    onClose:   { owner.statisticsWindow?.close() }
                )
                window.contentView = NSHostingView(rootView: view)
            }
            rebuild()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        /// Полная статистика: базовые счётчики + строки/страницы из живого layout.
        fileprivate func computeFullStatistics() -> FullStatistics {
            let model = controller.session?.bridge.model
            let base = model.map { DocumentStatisticsCalculator.calculate($0) } ?? .empty

            // Строки — количество line fragments в NSLayoutManager (реальные строки в редакторе).
            var lineCount = 0
            if let tv = controller.textView, let lm = tv.layoutManager {
                let glyphs = lm.numberOfGlyphs
                var idx = 0
                while idx < glyphs {
                    var lineRange = NSRange()
                    lm.lineFragmentRect(forGlyphAt: idx, effectiveRange: &lineRange)
                    idx = NSMaxRange(lineRange)
                    lineCount += 1
                }
                // AppKit не считает финальный пустой параграф — если документ заканчивается на \n,
                // добавляем строку от последнего перевода до конца.
                if let s = tv.textStorage?.string, s.hasSuffix("\n") {
                    lineCount += 1
                }
                if lineCount == 0, glyphs == 0 { lineCount = 1 }
            }

            // Страницы — оценка из размеров pageSettings и высоты используемой раскладки.
            var pageCount = 1
            if let tv = controller.textView, let lm = tv.layoutManager, let tc = tv.textContainer,
               let ps = model?.pageSettings {
                let used = lm.usedRect(for: tc)
                let contentHeight = max(1, ps.pageSizeInPoints.height - ps.margins.top - ps.margins.bottom)
                pageCount = max(1, Int(ceil(used.height / contentHeight)))
            }

            return FullStatistics(stats: base, lines: lineCount, pages: pageCount)
        }

        @objc private func onShowFontReplace() {
            if let existing = fontReplaceWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = FontReplaceView(controller: controller, onClose: { [weak self] in
                self?.fontReplaceWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Замена шрифтов"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            fontReplaceWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        @objc private func onTogglePageNumbers() { controller.togglePageNumbers() }
        @objc private func onInsertImage() {
            controller.insertImageInteractive()
        }

        @objc private func onInsertFootnote() {
            // MVP UI (v0.5.3, R07): NSAlert с TextField для ввода текста сноски.
            // Диалоговое окно на отдельной view — задача v0.5.4 вместе с панелью
            // редактирования всех сносок.
            let alert = NSAlert()
            alert.messageText = "Вставить сноску"
            alert.informativeText = "Текст сноски"
            alert.addButton(withTitle: "Вставить")
            alert.addButton(withTitle: "Отмена")
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
            input.placeholderString = "Например: см. Иванов И., 2024, с. 42"
            input.usesSingleLineMode = false
            alert.accessoryView = input
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            controller.insertFootnote(text: text.isEmpty ? "Текст сноски" : text)
        }

        /// v1.6.2: концевая сноска — тот же паттерн NSAlert с полем ввода.
        @objc private func onInsertEndnote() {
            let alert = NSAlert()
            alert.messageText = "Вставить концевую сноску"
            alert.informativeText = "Текст концевой сноски"
            alert.addButton(withTitle: "Вставить")
            alert.addButton(withTitle: "Отмена")
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
            input.placeholderString = "Например: Полный список литературы — в конце документа"
            input.usesSingleLineMode = false
            alert.accessoryView = input
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            controller.insertEndnote(text: text.isEmpty ? "Текст концевой сноски" : text)
        }

        @objc private func onInsertTOC() { controller.insertTableOfContents() }
        @objc private func onUpdateTOC() { controller.updateTableOfContents() }

        private var crossRefWindow: NSWindow?
        @objc private func onShowCrossReference() {
            if let w = crossRefWindow, w.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKeyAndOrderFront(nil)
                return
            }
            // По правилу проекта (table_properties_crash.md): диалоги через
            // NSWindow(contentRect:) + NSHostingView, а не через NSHostingController.
            let root = CrossReferenceView(controller: controller,
                                          onClose: { [weak self] in self?.crossRefWindow?.close() })
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Перекрёстная ссылка"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            crossRefWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowHyperlink() {
            if let existing = hyperlinkWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = HyperlinkView(controller: controller, onClose: { [weak self] in
                self?.hyperlinkWindow?.close()
            })
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Гиперссылка"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            hyperlinkWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowImageProperties() {
            guard controller.isCaretOnImage else {
                NSSound.beep()
                return
            }
            if let existing = imagePropertiesWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = ImagePropertiesView(controller: controller, onClose: { [weak self] in
                self?.imagePropertiesWindow?.close()
            })
            // ADR-039 п.7: только NSWindow(contentRect:) + NSHostingView(sizingOptions:[]).
            // Прошлый паттерн NSWindow(contentViewController:) сдвигал окно и мог падать.
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Свойства изображения"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            imagePropertiesWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowMergeCells() {
            guard controller.isCaretInTable else {
                NSSound.beep()
                return
            }
            if let existing = mergeCellsWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = MergeCellsView(controller: controller, onClose: { [weak self] in
                self?.mergeCellsWindow?.close()
            })
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Объединить ячейки"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            mergeCellsWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowSymbol() {
            if let existing = symbolWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = SymbolPickerView(controller: controller, onClose: { [weak self] in
                self?.symbolWindow?.close()
            })
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Символ"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            symbolWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onInsertDateTime(_ note: Notification) {
            let kind = (note.object as? NSString) as String? ?? "date"
            switch kind {
            case "time":     controller.insertDateTime(includeDate: false, includeTime: true)
            case "datetime": controller.insertDateTime(includeDate: true,  includeTime: true)
            default:         controller.insertDateTime(includeDate: true,  includeTime: false)
            }
        }

        @objc private func onInsertText(_ note: Notification) {
            guard let s = (note.object as? NSString) as String? else { return }
            controller.insertTextAtCaret(s)
        }

        @objc private func onShowTableProperties() {
            if let existing = tablePropertiesWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = TablePropertiesView(controller: controller, onClose: { [weak self] in
                self?.tablePropertiesWindow?.close()
            })
            // v0.1.91, ФИКС КРАША (v0.1.70–0.1.76): NSWindow(contentViewController:
            // NSHostingController) включает авторесайз окна хостинг-вью —
            // NSHostingView.updateAnimatedWindowSize вызывается из windowDidLayout
            // (т.е. ВНУТРИ display-цикла), меняет frame окна → каскад
            // setNeedsUpdateConstraints во время layout → NSException → abort().
            // Это единственный диалог, использовавший этот паттерн, — потому падал
            // только он. Переведён на паттерн остальных диалогов: явный NSWindow +
            // contentView = NSHostingView (окно не ресайзится хостом), плюс
            // sizingOptions = [] отключает путь updateAnimatedWindowSize полностью.
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            let contentSize = hosting.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Свойства таблицы"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            tablePropertiesWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onTableEdit(_ note: Notification) {
            guard let raw = note.object as? String else { return }
            let edit: DocumentController.TableEdit
            switch raw {
            case "addRowAbove":    edit = .addRowAbove
            case "addRowBelow":    edit = .addRowBelow
            case "addColumnLeft":  edit = .addColumnLeft
            case "addColumnRight": edit = .addColumnRight
            case "deleteRow":      edit = .deleteRow
            case "deleteColumn":   edit = .deleteColumn
            case "deleteTable":    edit = .deleteTable
            case "mergeCells":     edit = .mergeCells
            case "splitCell":      edit = .splitCell
            case "toggleHeaderRow": edit = .toggleHeaderRow
            default: return
            }
            controller.applyTableEdit(edit)
        }
        @objc private func onShowRowHeight() {
            if let existing = rowHeightWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = RowHeightView(controller: controller, onClose: { [weak self] in
                self?.rowHeightWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Высота строки"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            rowHeightWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onClearAutorecover() { controller.clearAutorecoverBackup() }

        @objc private func onShowCustomDictionary() {
            if let existing = customDictionaryWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = CustomDictionaryView(controller: controller)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Пользовательский словарь"
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            customDictionaryWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowBookmarks() {
            if let existing = bookmarksWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = BookmarksView(controller: controller, onClose: { [weak self] in
                self?.bookmarksWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Закладки"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            bookmarksWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowDocumentProperties() {
            if let existing = documentPropertiesWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = DocumentPropertiesView(controller: controller, onClose: { [weak self] in
                self?.documentPropertiesWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Свойства документа"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            documentPropertiesWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowImageCrop() {
            if let existing = imageCropWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            guard controller.isCaretOnImage else {
                NSSound.beep()
                return
            }
            let view = ImageCropView(controller: controller, onClose: { [weak self] in
                self?.imageCropWindow?.close()
            })
            // v1.2.4: визуальный кроп — размеры под новую вёрстку с превью 420×400.
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Обрезать изображение"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            imageCropWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowFindReplace() {
            if let existing = findReplaceWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = FindReplaceView(controller: controller, onClose: { [weak self] in
                self?.findReplaceWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Найти и заменить"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            findReplaceWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowParagraphIndents() {
            if let existing = paragraphIndentsWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = ParagraphIndentsView(controller: controller, onClose: { [weak self] in
                self?.paragraphIndentsWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Абзац"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            paragraphIndentsWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowInsertTable() {
            if let existing = insertTableWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = InsertTableView(controller: controller, onClose: { [weak self] in
                self?.insertTableWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Вставить таблицу"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            insertTableWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        @objc private func onShowHeaderFooter() {
            if let existing = headerFooterWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = HeaderFooterView(controller: controller, onClose: { [weak self] in
                self?.headerFooterWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Колонтитулы"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            headerFooterWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        @objc private func onShowStyles() {
            if let existing = stylesWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            guard let session = controller.session else { return }
            let view = StylesView(controller: controller, session: session, onClose: { [weak self] in
                self?.stylesWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Стили"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            stylesWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onShowGoTo() {
            if let existing = goToWindow, existing.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                existing.makeKeyAndOrderFront(nil)
                return
            }
            let view = GoToView(controller: controller, onClose: { [weak self] in
                self?.goToWindow?.close()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Перейти к"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            goToWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        @objc private func onApplyLineSpacing(_ n: Notification) {
            if let num = n.object as? NSNumber { controller.applyLineSpacing(CGFloat(num.doubleValue)) }
        }

        @objc private func onApplyFont(_ n: Notification) {
            if let name = n.object as? String { controller.applyFont(name: name) }
        }
        @objc private func onApplyFontSize(_ n: Notification) {
            if let num = n.object as? NSNumber { controller.applyFontSize(points: CGFloat(num.doubleValue)) }
        }
        @objc private func onApplyAlignment(_ n: Notification) {
            if let raw = n.object as? Int, let a = NSTextAlignment(rawValue: raw) {
                controller.applyAlignment(a)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isInternalUpdate, let tv = notification.object as? NSTextView else { return }
            // v0.4.6 (R06): при включённом track-changes — пометить вставку.
            // Ставим ДО userDidEdit, чтобы атрибут попал в пересчёт модели.
            controller.trackChanges.finalizeInsertionIfPending()
            // v0.1.57: автопревращение URL/email в ссылку по завершающему пробелу/переводу
            // строки. Делаем ДО пересчёта модели, чтобы .link уже присутствовал в atext.
            controller.autoLinkifyIfNeeded()
            controller.userDidEdit(text: tv.attributedString())
            // Структурная правка в списке (Return/Delete) — перенумеровать блок.
            if controller.consumePendingListRenumber() {
                controller.renumberCurrentListBlock()
            }
            // v0.1.67: положение изображения могло сдвинуться при правке текста.
            updateImageResizeOverlay()
            // v1.5.12: плавающие картинки — пересчёт позиций/обтекания.
            updateFloatingImages()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInternalUpdate else { return }
            controller.refreshSelectionState()
            updateImageResizeOverlay()
            // v1.7.4: mini-toolbar над выделением (Word/Notion-паттерн).
            updateSelectionMiniToolbar()
        }

        // v1.7.4: NSPopover с mini-toolbar. Ленивая инициализация — окно
        // создаётся при первом непустом выделении.
        private var miniToolbarPopover: NSPopover?
        /// Показывает/скрывает mini-toolbar в зависимости от текущего выделения.
        /// Debounce не нужен: NSPopover.show при уже показанном молча обновляет position.
        func updateSelectionMiniToolbar() {
            guard let sv = scrollView, let tv = sv.documentView as? NSTextView else { return }
            let sel = tv.selectedRange()
            // Скрываем: пустое выделение, режим чтения, source-режим, поповер уже закрыт.
            if sel.length == 0 || controller.isReadingMode {
                miniToolbarPopover?.performClose(nil)
                return
            }
            // Не показывать над изображением (там своя overlay-панель ресайза).
            if sel.length == 1, let storage = tv.textStorage,
               (storage.attribute(.attachment, at: sel.location, effectiveRange: nil) as? NSTextAttachment) != nil {
                miniToolbarPopover?.performClose(nil)
                return
            }
            // Anchor rect в координатах textView.
            guard let lm = tv.layoutManager, let container = tv.textContainer else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
            let origin = tv.textContainerOrigin
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            // Anchor — небольшой прямоугольник по центру верхнего края выделения.
            let anchor = NSRect(x: rect.midX - 1, y: rect.minY - 2, width: 2, height: 2)
            let popover = miniToolbarPopover ?? {
                let p = NSPopover()
                p.behavior = .applicationDefined
                p.animates = false
                let hosting = NSHostingController(rootView: MiniToolbarView(controller: controller))
                hosting.view.frame = NSRect(x: 0, y: 0, width: 240, height: 34)
                p.contentViewController = hosting
                miniToolbarPopover = p
                return p
            }()
            popover.show(relativeTo: anchor, of: tv, preferredEdge: .minY)
        }
        func closeMiniToolbar() { miniToolbarPopover?.performClose(nil) }

        /// Показывает overlay с ручками, если выделен ровно один символ-attachment
        /// (inline-изображение); иначе — прячет. v0.1.67.
        func updateImageResizeOverlay() {
            guard let sv = scrollView, let tv = sv.documentView as? NSTextView,
                  let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            // v1.5.12: у плавающих картинок якорь 1×1pt — overlay на него
            // не вешаем (ресайз/драг — на самом NSImageView).
            let wrapRaw = sel.length > 0 && sel.location < storage.length
                ? storage.attribute(.docxEditImageWrap, at: sel.location, effectiveRange: nil) as? String
                : nil
            let isFloating = wrapRaw.flatMap { InlineImageWrap(rawValue: $0) }.map { $0 != .inline } ?? false
            let isImage = !isFloating && sel.length == 1 && sel.location < storage.length &&
                (storage.attribute(.attachment, at: sel.location, effectiveRange: nil) as? NSTextAttachment) != nil
            if isImage {
                let overlay = imageResizeOverlay ?? {
                    let o = ImageResizeOverlay(frame: .zero)
                    o.textView = tv
                    tv.addSubview(o)
                    imageResizeOverlay = o
                    return o
                }()
                if !overlay.attach(to: sel) {
                    overlay.removeFromSuperview()
                    imageResizeOverlay = nil
                }
            } else {
                imageResizeOverlay?.removeFromSuperview()
                imageResizeOverlay = nil
            }
        }

        // MARK: - Плавающие изображения (v1.5.12)

        /// Живые NSImageView поверх текста для wrap != .inline. Ключ — позиция
        /// символа-якоря (U+FFFC) в textStorage. behindText рисуется отдельно —
        /// в DocxTextView.drawBackground (под текстом).
        private var floatingImageViews: [Int: FloatingImageNSView] = [:]
        private var lastExclusionSignature = ""

        /// Сканирует storage на плавающие картинки и синхронизирует субвьюхи
        /// и exclusionPaths. Вызывается после синка storage, правок и смены вида.
        func updateFloatingImages() {
            guard let sv = scrollView, let tv = sv.documentView as? NSTextView,
                  let storage = tv.textStorage,
                  let lm = tv.layoutManager, let container = tv.textContainer else { return }
            lm.ensureLayout(for: container)
            var seen: Set<Int> = []
            var behind: [(image: NSImage, rect: NSRect)] = []
            var exclusionRects: [NSRect] = []

            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { val, range, _ in
                guard let att = val as? NSTextAttachment,
                      let raw = storage.attribute(.docxEditImageWrap, at: range.location, effectiveRange: nil) as? String,
                      let wrap = InlineImageWrap(rawValue: raw), wrap != .inline,
                      let img = att.image else { return }
                seen.insert(range.location)

                // Размеры и смещения — из якорного атрибута "x,y,w,h" (EMU→pt).
                var xPt: CGFloat = 0, yPt: CGFloat = 0
                var wPt = img.size.width, hPt = img.size.height
                if let anchor = storage.attribute(.docxEditImageAnchor, at: range.location, effectiveRange: nil) as? String {
                    let parts = anchor.split(separator: ",").compactMap { Int($0) }
                    if parts.count >= 2 {
                        xPt = CGFloat(parts[0]) / 12700.0
                        yPt = CGFloat(parts[1]) / 12700.0
                    }
                    if parts.count >= 4, parts[2] > 0, parts[3] > 0 {
                        wPt = CGFloat(parts[2]) / 12700.0
                        hPt = CGFloat(parts[3]) / 12700.0
                    }
                }

                // Якорь по вертикали — верх строки, где стоит символ U+FFFC;
                // по горизонтали — левый край колонки текста (x=0 контейнера).
                let gr = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard gr.location != NSNotFound, gr.location < lm.numberOfGlyphs else { return }
                let lineRect = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
                let rectTV = NSRect(x: tv.textContainerOrigin.x + xPt,
                                    y: lineRect.minY + yPt,
                                    width: wPt, height: hPt)

                if wrap == .behindText {
                    behind.append((img, rectTV))
                } else {
                    let view: FloatingImageNSView
                    if let existing = floatingImageViews[range.location] {
                        view = existing
                    } else {
                        view = FloatingImageNSView(frame: rectTV)
                        view.charIndex = range.location
                        view.onDragCommit = { [weak self, weak tv] newOrigin in
                            guard let self, let tv else { return }
                            self.commitFloatingImageDrag(charIndex: range.location,
                                                         newOrigin: newOrigin, in: tv)
                        }
                        tv.addSubview(view)
                        floatingImageViews[range.location] = view
                    }
                    view.image = img
                    // v1.8.7: guard на равенство. Присвоение frame subview'а
                    // NSTextView даже тем же значением может триггерить layout()
                    // scrollView → magnification сбрасывается / SwiftUI дёргает
                    // updateNSView заново → цикл на 155.docx (32 плавающих),
                    // усугубляемый повторным autofit'ом. Тот же паттерн, что
                    // ADR-060/v1.8.6 закрыл для контейнера/frame textView.
                    if view.frame != rectTV { view.frame = rectTV }
                    view.isHidden = false
                }

                // Обтекание: square/tight/topAndBottom — текст огибает рамку.
                if wrap == .square || wrap == .tight || wrap == .topAndBottom {
                    exclusionRects.append(rectTV.offsetBy(dx: -tv.textContainerOrigin.x,
                                                          dy: -tv.textContainerOrigin.y))
                }
            }

            // Удалить вьюхи чужих/удалённых якорей.
            for (idx, view) in floatingImageViews where !seen.contains(idx) {
                view.removeFromSuperview()
                floatingImageViews.removeValue(forKey: idx)
            }

            // v1.8.5: округляем exclusionRects до 0.5pt перед сравнением/применением.
            // Причина (155.docx, 32 плавающих изображения): установка exclusionPaths
            // инвалидирует layout, lineFragmentRect якорных глифов на следующем цикле
            // сдвигается на микро-величины (~0.001pt), full-precision "\($0)"-сигнатура
            // всегда различалась → exclusionPaths переустанавливались бесконечно →
            // экран мерцал. Округление обрывает feedback-loop, точность 0.5pt для
            // обтекания незаметна.
            let rounded = exclusionRects.map {
                NSRect(x: (($0.origin.x * 2).rounded() / 2),
                       y: (($0.origin.y * 2).rounded() / 2),
                       width: (($0.width * 2).rounded() / 2),
                       height: (($0.height * 2).rounded() / 2))
            }
            let signature = rounded.map { "\($0)" }.joined(separator: "|")
            if signature != lastExclusionSignature {
                lastExclusionSignature = signature
                container.exclusionPaths = rounded.map { NSBezierPath(rect: $0) }
            }

            if let dt = tv as? DocxTextView {
                dt.floatingBehindImages = behind
                dt.needsDisplay = true
            }
        }

        /// Фиксация драга плавающей картинки: новые смещения (pt от колонки/
        /// строки-якоря) пишем обратно в атрибут на U+FFFC с регистрацией undo.
        private func commitFloatingImageDrag(charIndex: Int, newOrigin: NSPoint, in tv: NSTextView) {
            guard let storage = tv.textStorage, charIndex < storage.length else { return }
            // Верх строки-якоря — из текущего layout.
            guard let lm = tv.layoutManager, charIndex < storage.length else { return }
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1),
                                   actualCharacterRange: nil)
            let lineRect = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
            let xPt = newOrigin.x - tv.textContainerOrigin.x
            let yPt = newOrigin.y - lineRect.minY
            let xEmu = Int((xPt * 12700).rounded())
            let yEmu = Int((yPt * 12700).rounded())
            // Размеры сохраняем из старого атрибута.
            var wEmu = 0, hEmu = 0
            if let old = storage.attribute(.docxEditImageAnchor, at: charIndex, effectiveRange: nil) as? String {
                let parts = old.split(separator: ",").compactMap { Int($0) }
                if parts.count >= 4 { wEmu = parts[2]; hEmu = parts[3] }
            }
            if wEmu <= 0, let att = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
               let img = att.image {
                wEmu = Int(img.size.width * 12700); hEmu = Int(img.size.height * 12700)
            }
            let range = NSRange(location: charIndex, length: 1)
            guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.addAttribute(.docxEditImageAnchor,
                                 value: "\(xEmu),\(yEmu),\(wEmu),\(hEmu)", range: range)
            tv.didChangeText()
            updateFloatingImages()
        }
    }
}

// MARK: - Плавающая картинка (v1.5.12)

/// NSImageView с драгом: тянем мышью — картинка едет, отпускаем — новые
/// смещения коммитятся в модель (один шаг undo через shouldChangeText).
final class FloatingImageNSView: NSImageView {
    var charIndex: Int = 0
    var onDragCommit: ((NSPoint) -> Void)?
    private var dragStartWindow: NSPoint = .zero
    private var startOrigin: NSPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleAxesIndependently
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        dragStartWindow = event.locationInWindow
        startOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        let d = convert(NSPoint(x: event.locationInWindow.x - dragStartWindow.x,
                                y: event.locationInWindow.y - dragStartWindow.y),
                        from: nil)
        frame.origin = NSPoint(x: startOrigin.x + d.x, y: startOrigin.y + d.y)
    }

    override func mouseUp(with event: NSEvent) {
        if frame.origin != startOrigin {
            onDragCommit?(frame.origin)
        }
    }
}

// MARK: - NSTextStorage.matches

private extension NSTextStorage {
    func matches(_ other: NSAttributedString) -> Bool {
        guard length == other.length, string == other.string else { return false }
        let fullRange = NSRange(location: 0, length: length)
        var equal = true
        enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            guard equal else { return }
            let oa = other.attributes(at: range.location, effectiveRange: nil)
            if !fontMatches(attrs, oa) || !paraMatches(attrs, oa) { equal = false }
        }
        return equal
    }

    private func fontMatches(_ a: [NSAttributedString.Key: Any], _ b: [NSAttributedString.Key: Any]) -> Bool {
        guard let fa = a[.font] as? NSFont, let fb = b[.font] as? NSFont else {
            return (a[.font] == nil) == (b[.font] == nil)
        }
        return fa.fontName == fb.fontName && fa.pointSize == fb.pointSize
    }

    private func paraMatches(_ a: [NSAttributedString.Key: Any], _ b: [NSAttributedString.Key: Any]) -> Bool {
        let pa = a[.paragraphStyle] as? NSParagraphStyle
        let pb = b[.paragraphStyle] as? NSParagraphStyle
        return pa?.alignment == pb?.alignment
    }
}

// MARK: - NSTextView с рисованием разрывов страниц
//
// В режиме page-view рисует горизонтальную пунктирную линию каждые
// `pageHeight` pt по вертикали текстового вида — визуальный индикатор границ
// страниц. Реальной пагинации (перетекания текста между страницами) нет —
// это осознанное упрощение R02: даёт пользователю ориентир при вёрстке под A4
// без переработки TextKit-стека на multi-container. Печать (⌘P) идёт своим
// путём через NSPrintOperation и использует настоящую пагинацию.
final class DocxTextView: NSTextView {
    // Вид страницы (пагинация подходом №1): отдельные белые листы A4 на сером поле
    // с промежутками и тенью. Раскладка с разрывами — в PaginatedTextContainer;
    // здесь рисуются сами листы. Единый NSTextView → выделение/формат нативны.
    var showsPageSheet: Bool = false
    var pageSheetWidth: CGFloat = 0      // ширина листа (A4)
    var sheetUsableWidth: CGFloat = 0    // ширина колонки текста (лист − поля)
    var sheetTopInset: CGFloat = 0       // верхнее поле
    var sheetPageHeight: CGFloat = 0     // высота листа (A4)
    var pageCount: Int = 1               // число листов (вычисляется из раскладки)

    // Колонтитулы (рисуются в полях каждого листа); плейсхолдеры {page}/{pages}/{date}.
    var headerText: String = ""
    var footerText: String = ""
    var headerAlign: NSTextAlignment = .center
    var footerAlign: NSTextAlignment = .center
    // v0.2.3: варианты для первой страницы и чётных.
    var differentFirstPage: Bool = false
    var firstHeaderText: String = ""
    var firstFooterText: String = ""
    var firstHeaderAlign: NSTextAlignment = .center
    var firstFooterAlign: NSTextAlignment = .center
    var differentOddEven: Bool = false
    var evenHeaderText: String = ""
    var evenFooterText: String = ""
    var evenHeaderAlign: NSTextAlignment = .center
    var evenFooterAlign: NSTextAlignment = .center
    var sheetMarginLeft: CGFloat = 0
    var sheetMarginRight: CGFloat = 0
    var sheetMarginBottom: CGFloat = 0

    /// v1.5.3: плавающие изображения колонтитулов (из passthrough-частей,
    /// DESIGN_HEADER_FOOTER.md). Ключ — слот ("headerDefault", "footerEven", …);
    /// значения — картинка + смещение от колонки текста/абзаца колонтитула (pt).
    var hfImages: [String: [(image: NSImage, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)]] = [:]

    /// v1.5.12: плавающие картинки «за текстом» (wrap=behindDoc) — рисуются в
    /// drawBackground (под глифами). Координаты — в системе textView.
    var floatingBehindImages: [(image: NSImage, rect: NSRect)] = []

    /// v1.5.14: водяные знаки колонтитулов (VML WordArt/картинка) по слотам.
    /// Координаты — pt от верхнего левого угла ЛИСТА. Рисуются под текстом.
    var hfWatermarks: [String: [(wm: HFWatermark, image: NSImage?)]] = [:]

    /// v1.5.8: ширина читаемой колонки в MD-режиме (0 = во всю ширину).
    /// Колонка центрируется симметричным textContainerInset (пересчёт на ресайз).
    var mdColumnWidth: CGFloat = 0

    /// Серый зазор сверху и между листами (как в мейнстрим-редакторов).
    static let sheetGap: CGFloat = 24
    static let sheetField = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

    /// v1.5.13: лист адаптируется к тёмной теме — иначе дефолтный текст
    /// (labelColor, белый в dark mode) был бы белым по белому. Печать всегда
    /// с белым листом (isDrawingToScreen проверяется в drawBackground).
    static let sheetPaper = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(white: 0.13, alpha: 1) : NSColor.white
    }

    /// v0.5.5 (R07): ссылка на контроллер — нужна для Cmd+клик по cross-ref.
    weak var docxController: DocumentController?

    /// v1.6.6: умная вставка Markdown (Typora-поведение). Если plain-text
    /// буфера похож на MD-исходник — вставляется уже отформатированным;
    /// иначе и во всех не-MD случаях работает обычный путь super.paste().
    /// Принудительно просто: ⇧⌥⌘V (вставить без форматирования) или
    /// настройка «Умная вставка Markdown» = выкл.
    override func paste(_ sender: Any?) {
        if docxController?.trySmartMarkdownPaste() == true { return }
        super.paste(sender)
    }

    // MARK: - Drag-and-drop файла документа (v1.2.1)

    /// Расширения, которые открываем как документ (совпадают с CFBundleDocumentTypes).
    private static let openableExtensions: Set<String> = ["docx", "doc", "rtf", "odt", "md", "markdown", "txt"]

    /// URL документа в drag-пастборде (nil — не наш файл, отдаём NSTextView:
    /// изображения тот вставляет как attachment штатно).
    private func documentURLInDrag(_ sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let url = urls.first else { return nil }
        return Self.openableExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if documentURLInDrag(sender) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = documentURLInDrag(sender) {
            (NSApp.delegate as? AppDelegate)?.loadFromURL(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if showsPageSheet { updateSheetInset() }
        else if mdColumnWidth > 0 { updateMdColumnInset() }
    }

    /// v1.5.8: центрирование читаемой колонки в MD-режиме — симметричный
    /// горизонтальный inset (окно уже колонки — текст у левого края с минимальным
    /// отступом 16pt, как в обычном виде).
    func updateMdColumnInset() {
        guard mdColumnWidth > 0, !showsPageSheet else { return }
        let side = max(16, (bounds.width - mdColumnWidth) / 2)
        textContainerInset = NSSize(width: side, height: 32)
    }

    /// v0.1.68: клик по inline-изображению выделяет его как один символ (иначе
    /// NSTextView просто ставит курсор рядом, и overlay с ручками ресайза не
    /// появляется). Работает и для одиночного клика, и для двойного (даёт то же
    /// поведение — 1-символьное выделение).
    override func mouseDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plainClick = !mods.contains(.shift) && !mods.contains(.command)
        // v0.5.5 (R07): Cmd+клик по перекрёстной ссылке — прыжок к закладке.
        if mods.contains(.command),
           let lm = layoutManager, let container = textContainer, let storage = textStorage,
           let controller = self.docxController {
            let point = convert(event.locationInWindow, from: nil)
            let cp = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let gi = lm.glyphIndex(for: cp, in: container)
            let ci = lm.characterIndexForGlyph(at: gi)
            if ci < storage.length,
               storage.attribute(.docxEditCrossRef, at: ci, effectiveRange: nil) is String {
                if controller.goToCrossReference(at: ci) { return }
            }
        }
        if plainClick,
           let lm = layoutManager, let container = textContainer, let storage = textStorage {
            let point = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y
            )
            let glyphIndex = lm.glyphIndex(for: containerPoint, in: container)
            let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
            if charIndex < storage.length,
               storage.attribute(.attachment, at: charIndex, effectiveRange: nil) is NSTextAttachment {
                // Проверяем, что клик действительно ПО глифу картинки (не мимо
                // в хвостовой пустоте строки, где glyphIndex(for:) вернёт ближайший).
                let glyphRect = lm.boundingRect(
                    forGlyphRange: NSRange(location: glyphIndex, length: 1),
                    in: container
                ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                if glyphRect.contains(point) {
                    setSelectedRange(NSRange(location: charIndex, length: 1))
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    /// Горизонтальный inset центрирует колонку текста внутри листа; вертикальный =
    /// зазор сверху + верхнее поле (container-Y=0 = верх содержимого первого листа).
    func updateSheetInset() {
        guard showsPageSheet, sheetUsableWidth > 0 else { return }
        let side = max(sheetTopInset, (bounds.width - sheetUsableWidth) / 2)
        textContainerInset = NSSize(width: side, height: Self.sheetGap + sheetTopInset)
    }

    override func drawBackground(in rect: NSRect) {
        // v1.6.8: MD-«лента» — серое поле + центрированная белая колонка
        // (визуальные границы редактируемой области, как в Typora/iA Writer).
        if !showsPageSheet, mdColumnWidth > 0 {
            let isPrinting = !(NSGraphicsContext.current?.isDrawingToScreen ?? true)
            if !isPrinting {
                Self.sheetField.setFill()
                rect.fill()
                let colLeft = max(4, (bounds.width - mdColumnWidth) / 2)
                let colRect = NSRect(x: colLeft, y: rect.minY,
                                     width: mdColumnWidth, height: rect.height)
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
                    shadow.shadowBlurRadius = 8
                    shadow.shadowOffset = NSSize(width: 0, height: -2)
                    shadow.set()
                    DocxTextView.sheetPaper.setFill()
                    colRect.fill()
                    ctx.restoreGState()
                }
            }
            drawFloatingBehind(in: rect)
            return
        }
        guard showsPageSheet, pageSheetWidth > 0, sheetPageHeight > 0 else {
            super.drawBackground(in: rect)
            drawFloatingBehind(in: rect)
            return
        }
        // При печати серое поле и белый лист+тень НЕ рисуем (бумага сама белая,
        // серый на печати даст мусор). Колонтитулы — рисуем, они должны идти в
        // распечатке (в т.ч. {page}/{pages}).
        let isPrinting = !(NSGraphicsContext.current?.isDrawingToScreen ?? true)
        if !isPrinting {
            Self.sheetField.setFill()
            rect.fill()
        }
        let pageLeft = max(4, (bounds.width - pageSheetWidth) / 2)
        let gap = Self.sheetGap
        let stride = sheetPageHeight + gap
        let total = max(1, pageCount)
        for i in 0..<total {
            let y = gap + CGFloat(i) * stride
            let sheet = NSRect(x: pageLeft, y: y, width: pageSheetWidth, height: sheetPageHeight)
            guard sheet.intersects(rect) else { continue }
            if !isPrinting, let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = 14
                shadow.shadowOffset = NSSize(width: 0, height: -4)
                shadow.set()
                // v1.5.13: при печати лист всегда белый (бумага), на экране —
                // адаптивный (dark mode → тёмный лист).
                DocxTextView.sheetPaper.setFill()
                sheet.fill()
                ctx.restoreGState()
            }
            // Колонтитулы в полях листа. v0.2.3: разные варианты по типу страницы.
            let x0 = pageLeft + sheetMarginLeft
            let x1 = pageLeft + pageSheetWidth - sheetMarginRight
            let pageNumber = i + 1
            let variant = pageVariant(for: pageNumber)
            let (hText, hAlign) = headerFor(variant: variant)
            let (fText, fAlign) = footerFor(variant: variant)
            let hy = sheet.minY + max(4, sheetTopInset / 2 - 7)
            if !hText.isEmpty {
                drawMarginText(resolvedField(hText, page: pageNumber, pages: total),
                               x0: x0, x1: x1, y: hy, align: hAlign)
            }
            let fy = sheet.maxY - max(4, sheetMarginBottom / 2 + 7)
            if !fText.isEmpty {
                drawMarginText(resolvedField(fText, page: pageNumber, pages: total),
                               x0: x0, x1: x1, y: fy, align: fAlign)
            }
            // v1.5.3: плавающие картинки колонтитула (логотипы и т.п.) —
            // из passthrough-частей, смещения от колонки/абзаца.
            // v1.5.14: водяные знаки — под картинками колонтитула (координаты
            // от угла листа, а не от абзаца).
            switch variant {
            case .firstPage:
                drawHFWatermarks("headerFirst", sheet: sheet)
                drawHFWatermarks("footerFirst", sheet: sheet)
                drawHFImages("headerFirst", baseX: x0, baseY: hy)
                drawHFImages("footerFirst", baseX: x0, baseY: fy)
            case .evenPage:
                drawHFWatermarks("headerEven", sheet: sheet)
                drawHFWatermarks("footerEven", sheet: sheet)
                drawHFImages("headerEven", baseX: x0, baseY: hy)
                drawHFImages("footerEven", baseX: x0, baseY: fy)
            case .defaultOdd:
                drawHFWatermarks("headerDefault", sheet: sheet)
                drawHFWatermarks("footerDefault", sheet: sheet)
                drawHFImages("headerDefault", baseX: x0, baseY: hy)
                drawHFImages("footerDefault", baseX: x0, baseY: fy)
            }
        }
        // v1.5.12: картинки «за текстом» — поверх листов, под глифами.
        drawFloatingBehind(in: rect)
    }

    /// v1.5.12: плавающие картинки wrap=behindDoc (под текстом, поверх фона/листа).
    private func drawFloatingBehind(in rect: NSRect) {
        guard !floatingBehindImages.isEmpty else { return }
        for item in floatingBehindImages where item.rect.intersects(rect) {
            item.image.draw(in: item.rect, from: .zero, operation: .sourceOver,
                            fraction: 1.0, respectFlipped: true, hints: nil)
        }
    }

    /// v1.5.3: отрисовка плавающих изображений колонтитула для слота.
    private func drawHFImages(_ slot: String, baseX: CGFloat, baseY: CGFloat) {
        for img in hfImages[slot] ?? [] {
            img.image.draw(
                in: NSRect(x: baseX + img.x, y: baseY + img.y,
                           width: max(1, img.w), height: max(1, img.h)),
                from: .zero, operation: .sourceOver, fraction: 1.0,
                respectFlipped: true, hints: nil)
        }
    }

    private enum PageVariant { case defaultOdd, firstPage, evenPage }

    /// v1.5.14: водяные знаки слота. Текст — WordArt-подобный (полупрозрачный,
    /// повёрнутый, размер подгоняется под рамку шейпа), картинка — с прозрачностью.
    private func drawHFWatermarks(_ slot: String, sheet: NSRect) {
        guard let items = hfWatermarks[slot], !items.isEmpty else { return }
        for (wm, img) in items {
            let frame = NSRect(x: sheet.minX + wm.xPt, y: sheet.minY + wm.yPt,
                               width: max(1, wm.wPt), height: max(1, wm.hPt))
            guard frame.intersects(sheet) else { continue }
            if let image = img {
                image.draw(in: frame, from: .zero, operation: .sourceOver,
                           fraction: 0.5, respectFlipped: true, hints: nil)
            } else if let text = wm.text, !text.isEmpty {
                let color: NSColor
                if let hex = wm.colorHex, let c = CodableColor.fromHex(hex) {
                    color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
                } else {
                    color = NSColor.lightGray
                }
                // Размер шрифта — под рамку (WordArt масштабирует под шейп;
                // приближаем: шрифт ~45% высоты рамки, но не крупнее ширины/длины).
                var fontSize = max(10, frame.height * 0.45)
                var font = NSFont.boldSystemFont(ofSize: fontSize)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color.withAlphaComponent(0.45),
                ]
                var textSize = (text as NSString).size(withAttributes: attrs)
                if textSize.width > frame.width, textSize.width > 0 {
                    fontSize = max(8, fontSize * frame.width / textSize.width)
                    font = NSFont.boldSystemFont(ofSize: fontSize)
                    attrs[.font] = font
                    textSize = (text as NSString).size(withAttributes: attrs)
                }
                NSGraphicsContext.current?.saveGraphicsState()
                if wm.rotation != 0 {
                    let t = NSAffineTransform()
                    t.translateX(by: frame.midX, yBy: frame.midY)
                    t.rotate(byDegrees: -wm.rotation)  // координаты NSTextView — перевёрнутые
                    t.concat()
                    (text as NSString).draw(
                        at: NSPoint(x: -textSize.width / 2, y: -textSize.height / 2),
                        withAttributes: attrs)
                } else {
                    (text as NSString).draw(
                        at: NSPoint(x: frame.midX - textSize.width / 2,
                                    y: frame.midY - textSize.height / 2),
                        withAttributes: attrs)
                }
                NSGraphicsContext.current?.restoreGraphicsState()
            }
        }
    }

    private func pageVariant(for pageNumber: Int) -> PageVariant {
        if differentFirstPage, pageNumber == 1 { return .firstPage }
        if differentOddEven, pageNumber % 2 == 0 { return .evenPage }
        return .defaultOdd
    }

    private func headerFor(variant: PageVariant) -> (String, NSTextAlignment) {
        switch variant {
        case .firstPage:  return (firstHeaderText, firstHeaderAlign)
        case .evenPage:   return (evenHeaderText, evenHeaderAlign)
        case .defaultOdd: return (headerText, headerAlign)
        }
    }

    private func footerFor(variant: PageVariant) -> (String, NSTextAlignment) {
        switch variant {
        case .firstPage:  return (firstFooterText, firstFooterAlign)
        case .evenPage:   return (evenFooterText, evenFooterAlign)
        case .defaultOdd: return (footerText, footerAlign)
        }
    }

    // MARK: - Печать: один печатный лист = один виртуальный лист

    /// В «Виде страницы» отдаём число страниц через knowsPageRange, чтобы принтер
    /// не резал на слайсы по paperSize (иначе слайс попадает на промежуток между
    /// нашими листами → всё пытается уложиться на 1 бумажный лист). При этом
    /// пересчитываем pageCount по фактической раскладке — снапшот в applyPageViewStyle
    /// может устареть между правками.
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        guard showsPageSheet, sheetPageHeight > 0 else { return super.knowsPageRange(range) }
        let stride = sheetPageHeight + Self.sheetGap
        var pc = pageCount
        if let lm = layoutManager, let c = textContainer {
            lm.ensureLayout(for: c)
            let usedMaxY = lm.usedRect(for: c).maxY
            pc = max(1, Int(floor(max(0, usedMaxY - 0.5) / stride)) + 1)
        }
        pageCount = pc
        range.pointee = NSRange(location: 1, length: pc)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        guard showsPageSheet, pageSheetWidth > 0, sheetPageHeight > 0 else {
            return super.rectForPage(page)
        }
        let i = max(0, page - 1)
        let pageLeft = max(4, (bounds.width - pageSheetWidth) / 2)
        let y = Self.sheetGap + CGFloat(i) * (sheetPageHeight + Self.sheetGap)
        return NSRect(x: pageLeft, y: y, width: pageSheetWidth, height: sheetPageHeight)
    }

    private func resolvedField(_ template: String, page: Int, pages: Int) -> String {
        var s = template.replacingOccurrences(of: "{page}", with: "\(page)")
        s = s.replacingOccurrences(of: "{pages}", with: "\(pages)")
        if s.contains("{date}") {
            let df = DateFormatter()
            df.dateStyle = .long
            df.locale = Locale(identifier: "ru_RU")
            s = s.replacingOccurrences(of: "{date}", with: df.string(from: Date()))
        }
        return s
    }

    private func drawMarginText(_ text: String, x0: CGFloat, x1: CGFloat,
                                y: CGFloat, align: NSTextAlignment) {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para
        ]
        let r = NSRect(x: x0, y: y, width: max(1, x1 - x0), height: 14)
        (text as NSString).draw(in: r, withAttributes: attrs)
    }
}

// MARK: - Отрисовка непечатаемых символов
//
// Штатный `NSLayoutManager.showsInvisibleCharacters` в TextKit 1 подставляет
// U+00B7 (·) для пробела, но если у текущего шрифта нет глифа — рендерится
// тофу/подстановка (у пользователя видно как «0»). Табы и `\n` он отрисовывает
// ненадёжно. Рисуем сами: обычный `super.drawGlyphs` рисует настоящий текст,
// сверху накладываем маркеры системным шрифтом (у него точно есть все нужные
// глифы). Флаг `showsInvisibleCharacters` NSLayoutManager используется как
// переключатель (устанавливается в `DocumentController.toggleInvisibleCharacters`).
final class DocxLayoutManager: NSLayoutManager {
    private static let markerColor = NSColor.tertiaryLabelColor
    private static let markerFont  = NSFont.systemFont(ofSize: 11)

    /// Собственный флаг — не подменяет `NSLayoutManager.showsInvisibleCharacters`,
    /// потому что родной флаг заставляет `super.drawGlyphs` рисовать системные
    /// метки-подстановки для пробелов (у Roboto/др. пользовательских шрифтов —
    /// тофу/«0»), и наши маркеры оказывались поверх системных.
    var showsCustomInvisibles: Bool = false

    /// v1.5.18: подсветка всех вхождений поиска — char-диапазоны в storage.
    /// Рисуется ПОД текстом (до super.drawGlyphs), storage не мутируется —
    /// в модель ничего не «запекается» (в отличие от временного backgroundColor).
    var findHighlights: [NSRange] = []

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Подсветка поиска — под глифами.
        if !findHighlights.isEmpty, let storage = textStorage,
           let container = textContainers.first {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            NSColor.systemYellow.withAlphaComponent(0.4).setFill()
            for hl in findHighlights {
                let inter = NSIntersectionRange(hl, charRange)
                guard inter.length > 0, inter.location < storage.length else { continue }
                let gr = glyphRange(forCharacterRange: inter, actualCharacterRange: nil)
                let box = boundingRect(forGlyphRange: gr, in: container)
                    .offsetBy(dx: origin.x, dy: origin.y)
                if !box.isNull, !box.isEmpty {
                    NSBezierPath(roundedRect: box.insetBy(dx: -1, dy: 0),
                                 xRadius: 2, yRadius: 2).fill()
                }
            }
        }
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // v1.4.2 (ADR-049): горизонтальная линия — рисуем hairline поперёк
        // строки для абзацев со стилем HorizontalRule (независимо от флага
        // непечатаемых символов).
        var scanLoc = charRange.location
        let scanEnd = min(charRange.location + charRange.length, storage.length)
        while scanLoc < scanEnd {
            var eff = NSRange()
            let sid = storage.attribute(.docxEditStyleId, at: scanLoc, effectiveRange: &eff) as? String
            if sid == "HorizontalRule", eff.length > 0 {
                let glyphIdx = glyphIndexForCharacter(at: eff.location)
                let lineRect = lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                if !lineRect.isNull {
                    let y = origin.y + lineRect.origin.y + lineRect.height / 2
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: origin.x + lineRect.minX, y: y))
                    path.line(to: NSPoint(x: origin.x + lineRect.maxX, y: y))
                    path.lineWidth = 1
                    NSColor.tertiaryLabelColor.setStroke()
                    path.stroke()
                }
            }
            // v1.5.5: границы абзаца (w:pBdr) — рамка вокруг bounding-rect
            // абзаца (стороны по флагам). TextKit 1 pBdr не умеет.
            if let border = storage.attribute(.docxEditParagraphBorder, at: scanLoc, effectiveRange: &eff) as? ParagraphBorder,
               eff.length > 0, !border.isEmpty {
                let text = storage.string as NSString
                let paraRange = text.paragraphRange(for: eff)
                let glyphRange = glyphRange(forCharacterRange: paraRange, actualCharacterRange: nil)
                let box = boundingRect(forGlyphRange: glyphRange, in: textContainers[0])
                    .offsetBy(dx: origin.x, dy: origin.y)
                if !box.isNull, !box.isEmpty {
                    let color: NSColor = border.color.map {
                        NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                    } ?? .labelColor
                    color.setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = max(0.5, border.width)
                    if border.top {
                        path.move(to: NSPoint(x: box.minX, y: box.minY))
                        path.line(to: NSPoint(x: box.maxX, y: box.minY))
                    }
                    if border.bottom {
                        path.move(to: NSPoint(x: box.minX, y: box.maxY))
                        path.line(to: NSPoint(x: box.maxX, y: box.maxY))
                    }
                    if border.left {
                        path.move(to: NSPoint(x: box.minX, y: box.minY))
                        path.line(to: NSPoint(x: box.minX, y: box.maxY))
                    }
                    if border.right {
                        path.move(to: NSPoint(x: box.maxX, y: box.minY))
                        path.line(to: NSPoint(x: box.maxX, y: box.maxY))
                    }
                    path.stroke()
                }
            }
            scanLoc = max(eff.location + max(eff.length, 1), scanLoc + 1)
        }
        guard showsCustomInvisibles else { return }

        let text = storage.string as NSString
        let end = min(charRange.location + charRange.length, text.length)
        guard charRange.location >= 0, end > charRange.location else { return }

        let markerAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.markerFont,
            .foregroundColor: Self.markerColor
        ]

        for charIdx in charRange.location..<end {
            let ch = text.character(at: charIdx)
            let marker: String
            switch ch {
            case 0x20:  marker = "·"    // space (middle dot)
            case 0x09:  marker = "→"    // tab
            case 0x0A:  marker = "¶"    // LF
            case 0x0D:  marker = "¶"    // CR
            case 0xA0:  marker = "°"    // NBSP
            case 0x0C:  marker = "══ Разрыв страницы ══"   // Form Feed (⌘⏎)
            case 0x2028: marker = "↵"   // line separator
            default:    continue
            }
            let glyphIdx = glyphIndexForCharacter(at: charIdx)
            let lineRect = lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            let glyphLoc = location(forGlyphAt: glyphIdx)
            let point = NSPoint(x: origin.x + lineRect.origin.x + glyphLoc.x,
                                y: origin.y + lineRect.origin.y + glyphLoc.y - Self.markerFont.ascender)
            (marker as NSString).draw(at: point, withAttributes: markerAttrs)
        }
    }
}
