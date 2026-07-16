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

// MARK: - Главный вид окна

struct DocumentWindowView: View {
    @EnvironmentObject private var session: DocumentSession
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var controller = DocumentController()
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(spacing: 0) {
            // v0.4.3 (R06): режим «Чтение» скрывает ribbon.
            if !controller.isReadingMode {
                RibbonView(controller: controller, prefs: prefs, appDelegate: appDelegate)
                Divider()
            }

            HStack(spacing: 0) {
                TextEditorRepresentable(controller: controller, session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if controller.showsStylesSidebar {
                    Divider()
                    StylesSidebarView(controller: controller)
                }
                if controller.showsCommentsSidebar {
                    Divider()
                    CommentsSidebarView(engine: controller.comments)
                }
                if controller.showsFootnotesSidebar {
                    Divider()
                    FootnotesSidebarView(controller: controller)
                }
            }

            Divider()

            StatusBar(controller: controller, trackChanges: controller.trackChanges)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(.background)
        }
        .navigationTitle(session.windowTitle)
        .background(WindowCloseGuard(session: session, appDelegate: appDelegate))
        .onAppear { controller.attach(session: session) }
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

    private let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider().frame(height: 12)
            LanguageIndicator(controller: controller)
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
            viewModeButton(systemName: "doc.richtext", on: controller.isPageView,
                           help: "Вид страницы") {
                if !controller.isPageView { controller.togglePageView() }
            }
            viewModeButton(systemName: "doc.plaintext", on: !controller.isPageView,
                           help: "Обычный вид") {
                if controller.isPageView { controller.togglePageView() }
            }
            Divider().frame(height: 12)
            // Масштаб (как в мейнстрим-редакторов — справа в строке состояния).
            Button { controller.fitPageWidth() } label: {
                Image(systemName: "arrow.left.and.right.square")
            }
            .buttonStyle(.plain).help("По ширине страницы")
            Button { controller.fitTwoPages() } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.plain).help("Две страницы")
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
        applyPageViewStyle(nsView, textView: textView)

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
        }
    }

    private func applyPageViewStyle(_ scroll: NSScrollView, textView: NSTextView) {
        let ps = session.bridge.model.pageSettings
        let container = textView.textContainer as? PaginatedTextContainer
        if controller.isPageView {
            let size = ps.pageSizeInPoints
            let margins = ps.margins
            let usableW = max(1, size.width - margins.left - margins.right)
            let usableH = max(1, size.height - margins.top - margins.bottom)
            let gap = DocxTextView.sheetGap
            scroll.backgroundColor = NSColor(calibratedWhite: 0.55, alpha: 1)
            textView.drawsBackground = true
            textView.autoresizingMask = [.width]
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            container?.widthTracksTextView = false
            container?.containerSize = NSSize(width: usableW, height: CGFloat.greatestFiniteMagnitude)
            container?.paged = true
            container?.pageStride = size.height + gap
            container?.pageContentHeight = usableH

            let viewW = max(size.width + 80, scroll.contentSize.width)
            textView.frame.origin.x = 0
            textView.frame.size.width = viewW
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
                textView.frame.size.height = totalH
                dt.needsDisplay = true
            }
        } else {
            scroll.backgroundColor = .textBackgroundColor
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 32, height: 32)
            textView.autoresizingMask = [.width]
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            container?.paged = false
            container?.widthTracksTextView = true
            let w = max(1, scroll.contentSize.width - 2)
            container?.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.origin.x = 0
            textView.frame.size.width = max(1, scroll.contentSize.width)
            if let dt = textView as? DocxTextView {
                dt.showsPageSheet = false
                dt.needsDisplay = true
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

        init(controller: DocumentController) {
            self.controller = controller
            super.init()
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(onToggleBold),           name: .docxEditToggleBold,           object: nil)
            nc.addObserver(self, selector: #selector(onToggleItalic),         name: .docxEditToggleItalic,         object: nil)
            nc.addObserver(self, selector: #selector(onToggleUnderline),      name: .docxEditToggleUnderline,      object: nil)
            nc.addObserver(self, selector: #selector(onToggleStrikethrough),  name: .docxEditToggleStrikethrough,  object: nil)
            nc.addObserver(self, selector: #selector(onToggleSuperscript),    name: .docxEditToggleSuperscript,    object: nil)
            nc.addObserver(self, selector: #selector(onToggleSubscript),      name: .docxEditToggleSubscript,      object: nil)
            nc.addObserver(self, selector: #selector(onChangeCase(_:)),       name: .docxEditChangeCase,           object: nil)
            nc.addObserver(self, selector: #selector(onCopyFormatting),       name: .docxEditCopyFormatting,       object: nil)
            nc.addObserver(self, selector: #selector(onPasteFormatting),      name: .docxEditPasteFormatting,      object: nil)
            nc.addObserver(self, selector: #selector(onApplyHighlight(_:)),   name: .docxEditApplyHighlight,       object: nil)
            nc.addObserver(self, selector: #selector(onShowRowHeight),        name: .docxEditShowRowHeight,        object: nil)
            nc.addObserver(self, selector: #selector(onShowParagraphIndents), name: .docxEditShowParagraphIndents, object: nil)
            nc.addObserver(self, selector: #selector(onShowFindReplace),      name: .docxEditShowFindReplace,      object: nil)
            nc.addObserver(self, selector: #selector(onShowImageCrop),        name: .docxEditShowImageCrop,        object: nil)
            nc.addObserver(self, selector: #selector(onShowDocumentProperties), name: .docxEditShowDocumentProperties, object: nil)
            nc.addObserver(self, selector: #selector(onShowBookmarks),        name: .docxEditShowBookmarks,        object: nil)
            nc.addObserver(self, selector: #selector(onShowCustomDictionary), name: .docxEditShowCustomDictionary, object: nil)
            nc.addObserver(self, selector: #selector(onClearAutorecover),     name: .docxEditClearAutorecover,     object: nil)
            nc.addObserver(self, selector: #selector(onClearFormatting),      name: .docxEditClearFormatting,      object: nil)
            nc.addObserver(self, selector: #selector(onApplyFont(_:)),        name: .docxEditApplyFont,            object: nil)
            nc.addObserver(self, selector: #selector(onApplyFontSize(_:)),    name: .docxEditApplyFontSize,        object: nil)
            nc.addObserver(self, selector: #selector(onApplyAlignment(_:)),   name: .docxEditApplyAlignment,       object: nil)
            nc.addObserver(self, selector: #selector(onZoomIn),               name: .docxEditZoomIn,               object: nil)
            nc.addObserver(self, selector: #selector(onZoomOut),              name: .docxEditZoomOut,              object: nil)
            nc.addObserver(self, selector: #selector(onZoomReset),            name: .docxEditZoomReset,            object: nil)
            nc.addObserver(self, selector: #selector(onFitPageWidth),         name: .docxEditFitPageWidth,         object: nil)
            nc.addObserver(self, selector: #selector(onFitTwoPages),          name: .docxEditFitTwoPages,          object: nil)
            nc.addObserver(self, selector: #selector(onTogglePageView),       name: .docxEditTogglePageView,       object: nil)
            nc.addObserver(self, selector: #selector(onPageSettingsChanged),  name: .docxEditPageSettingsChanged,  object: nil)
            nc.addObserver(self, selector: #selector(onPageSettingsApplied),  name: .docxEditPageSettingsApplied,  object: nil)
            nc.addObserver(self, selector: #selector(onCheckSpelling),        name: .docxEditCheckSpelling,        object: nil)
            nc.addObserver(self, selector: #selector(onShowImportReport),     name: .docxEditShowImportReport,     object: nil)
            nc.addObserver(self, selector: #selector(onApplyLineSpacing(_:)), name: .docxEditApplyLineSpacing,     object: nil)
            nc.addObserver(self, selector: #selector(onIncreaseIndent),       name: .docxEditIncreaseIndent,       object: nil)
            nc.addObserver(self, selector: #selector(onDecreaseIndent),       name: .docxEditDecreaseIndent,       object: nil)
            nc.addObserver(self, selector: #selector(onToggleList(_:)),       name: .docxEditToggleList,           object: nil)
            nc.addObserver(self, selector: #selector(onApplyListVariant(_:)), name: .docxEditApplyListVariant,     object: nil)
            nc.addObserver(self, selector: #selector(onPasteAsPlainText),     name: .docxEditPasteAsPlainText,     object: nil)
            nc.addObserver(self, selector: #selector(onApplyParagraphStyle(_:)), name: .docxEditApplyParagraphStyle, object: nil)
            nc.addObserver(self, selector: #selector(onApplyCharacterStyle(_:)), name: .docxEditApplyCharacterStyle, object: nil)
            nc.addObserver(self, selector: #selector(onToggleInvisibles),     name: .docxEditToggleInvisibles,     object: nil)
            nc.addObserver(self, selector: #selector(onToggleRuler),          name: .docxEditToggleRuler,          object: nil)
            nc.addObserver(self, selector: #selector(onToggleStylesSidebar),  name: .docxEditToggleStylesSidebar,  object: nil)
            nc.addObserver(self, selector: #selector(onToggleReadingMode),    name: .docxEditToggleReadingMode,    object: nil)
            nc.addObserver(self, selector: #selector(onToggleCommentsSidebar), name: .docxEditToggleCommentsSidebar, object: nil)
            nc.addObserver(self, selector: #selector(onToggleFootnotesSidebar), name: .docxEditToggleFootnotesSidebar, object: nil)
            nc.addObserver(self, selector: #selector(onInsertComment),        name: .docxEditInsertComment,        object: nil)
            nc.addObserver(self, selector: #selector(onToggleTrackChanges),   name: .docxEditToggleTrackChanges,   object: nil)
            nc.addObserver(self, selector: #selector(onAcceptAllChanges),     name: .docxEditAcceptAllChanges,     object: nil)
            nc.addObserver(self, selector: #selector(onRejectAllChanges),     name: .docxEditRejectAllChanges,     object: nil)
            nc.addObserver(self, selector: #selector(onGoToNextRevision),     name: .docxEditGoToNextRevision,     object: nil)
            nc.addObserver(self, selector: #selector(onAcceptCurrentRev),     name: .docxEditAcceptCurrentRev,     object: nil)
            nc.addObserver(self, selector: #selector(onRejectCurrentRev),     name: .docxEditRejectCurrentRev,     object: nil)
            nc.addObserver(self, selector: #selector(onShowStatistics),       name: .docxEditShowStatistics,       object: nil)
            nc.addObserver(self, selector: #selector(onShowFind),             name: .docxEditShowFind,             object: nil)
            nc.addObserver(self, selector: #selector(onShowReplace),          name: .docxEditShowReplace,          object: nil)
            nc.addObserver(self, selector: #selector(onPrint),                name: .docxEditPrint,                object: nil)
            nc.addObserver(self, selector: #selector(onShowFontReplace),      name: .docxEditShowFontReplace,      object: nil)
            nc.addObserver(self, selector: #selector(onShowGoTo),             name: .docxEditShowGoTo,             object: nil)
            nc.addObserver(self, selector: #selector(onShowStyles),           name: .docxEditShowStyles,           object: nil)
            nc.addObserver(self, selector: #selector(onInsertPageBreak),      name: .docxEditInsertPageBreak,      object: nil)
            nc.addObserver(self, selector: #selector(onTogglePageNumbers),    name: .docxEditTogglePageNumbers,    object: nil)
            nc.addObserver(self, selector: #selector(onShowHeaderFooter),     name: .docxEditShowHeaderFooter,     object: nil)
            nc.addObserver(self, selector: #selector(onShowInsertTable),      name: .docxEditShowInsertTable,      object: nil)
            nc.addObserver(self, selector: #selector(onTableEdit(_:)),        name: .docxEditTableEdit,            object: nil)
            nc.addObserver(self, selector: #selector(onShowTableProperties), name: .docxEditShowTableProperties, object: nil)
            nc.addObserver(self, selector: #selector(onInsertImage),          name: .docxEditInsertImage,          object: nil)
            nc.addObserver(self, selector: #selector(onShowHyperlink),        name: .docxEditShowHyperlink,        object: nil)
            nc.addObserver(self, selector: #selector(onInsertFootnote),       name: .docxEditInsertFootnote,       object: nil)
            nc.addObserver(self, selector: #selector(onInsertTOC),            name: .docxEditInsertTOC,            object: nil)
            nc.addObserver(self, selector: #selector(onUpdateTOC),            name: .docxEditUpdateTOC,            object: nil)
            nc.addObserver(self, selector: #selector(onShowCrossReference),   name: .docxEditShowCrossReference,   object: nil)
            nc.addObserver(self, selector: #selector(onShowImageProperties),  name: .docxEditShowImageProperties,  object: nil)
            nc.addObserver(self, selector: #selector(onShowMergeCells),        name: .docxEditShowMergeCells,       object: nil)
            nc.addObserver(self, selector: #selector(onShowSymbol),           name: .docxEditShowSymbol,           object: nil)
            nc.addObserver(self, selector: #selector(onInsertDateTime(_:)),   name: .docxEditInsertDateTime,       object: nil)
            nc.addObserver(self, selector: #selector(onInsertText(_:)),       name: .docxEditInsertText,           object: nil)

            // ⌘]/⌘[ на кириллической (РУ) раскладке: SwiftUI .keyboardShortcut молча не
            // срабатывает (обнаружено по жалобе «многоуровневые списки не включаются» —
            // toggleList и кнопки в тулбаре работали, а именно ⌘] не долетал). Причина —
            // не физическая позиция клавиши (keyCode тоже отличается от US-раскладки,
            // физической клавиши "]" в ЙЦУКЕН попросту нет на том же месте), а то, что
            // под Cmd-модификатором RU-раскладка отображает эту клавишу в "`", а не в "]"
            // (проверено логированием: characters="`", но charactersIgnoringModifiers="]").
            // Поэтому сопоставляем по charactersIgnoringModifiers — то же значение, которое
            // AppKit использует для сопоставления keyEquivalent у NSMenuItem, и оно
            // корректно даёт "]"/"[" независимо от раскладки. Событие гасим (return nil),
            // чтобы не дублировать на раскладках, где совпало бы и через SwiftUI-шорткат.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.scrollView?.window, window.isKeyWindow else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers ?? ""
                // ⇧⌥⌘V — «Вставить с сохранением стиля». SwiftUI-шорткат под РУ-
                // раскладкой не срабатывает (та же причина, что у ⌘]/⌘[ в ADR-027);
                // буквенные клавиши на РУ-раскладке НЕ дают латинского символа даже
                // в charactersIgnoringModifiers (в отличие от скобок), поэтому
                // сопоставляем по физическому keyCode — 9 для клавиши V, независимо
                // от раскладки.
                if mods == [.command, .shift, .option], event.keyCode == 9 {
                    self.controller.pasteAsPlainText()
                    return nil
                }
                // ⌘⌥G — «Перейти к…». Буквенный shortcut, физический keyCode G = 5.
                if mods == [.command, .option], event.keyCode == 5 {
                    self.controller.showGoToDialog()
                    return nil
                }
                if mods == .command {
                    switch chars {
                    case "]": self.controller.increaseIndent(); return nil
                    case "[": self.controller.decreaseIndent(); return nil
                    default: break
                    }
                }
                return event
            }
        }
        deinit {
            NotificationCenter.default.removeObserver(self)
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }

        private var keyMonitor: Any?
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
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Свойства изображения"
            window.styleMask = [.titled, .closable]
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
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Обрезать изображение"
            window.contentView = NSHostingView(rootView: view)
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
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInternalUpdate else { return }
            controller.refreshSelectionState()
            updateImageResizeOverlay()
        }

        /// Показывает overlay с ручками, если выделен ровно один символ-attachment
        /// (inline-изображение); иначе — прячет. v0.1.67.
        func updateImageResizeOverlay() {
            guard let sv = scrollView, let tv = sv.documentView as? NSTextView,
                  let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            let isImage = sel.length == 1 && sel.location < storage.length &&
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

    /// Серый зазор сверху и между листами (как в мейнстрим-редакторов).
    static let sheetGap: CGFloat = 24
    private static let sheetField = NSColor(calibratedWhite: 0.55, alpha: 1)

    /// v0.5.5 (R07): ссылка на контроллер — нужна для Cmd+клик по cross-ref.
    weak var docxController: DocumentController?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if showsPageSheet { updateSheetInset() }
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
        guard showsPageSheet, pageSheetWidth > 0, sheetPageHeight > 0 else {
            super.drawBackground(in: rect)
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
                NSColor.white.setFill()
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
            if !hText.isEmpty {
                let hy = sheet.minY + max(4, sheetTopInset / 2 - 7)
                drawMarginText(resolvedField(hText, page: pageNumber, pages: total),
                               x0: x0, x1: x1, y: hy, align: hAlign)
            }
            if !fText.isEmpty {
                let fy = sheet.maxY - max(4, sheetMarginBottom / 2 + 7)
                drawMarginText(resolvedField(fText, page: pageNumber, pages: total),
                               x0: x0, x1: x1, y: fy, align: fAlign)
            }
        }
    }

    private enum PageVariant { case defaultOdd, firstPage, evenPage }

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

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsCustomInvisibles, let storage = textStorage, storage.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
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
