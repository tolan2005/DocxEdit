//
//  MarkdownSourceView.swift
//  DocxEdit
//
//  v1.6.0: исходный режим Markdown — редактирование сырого .md текста
//  моноширинным шрифтом с подсветкой синтаксиса (заголовки, жирный/курсив,
//  код, ссылки, цитаты, списки, HR). Подсветка — regex-проход по всему
//  storage на каждую правку (документы MD обычно невелики; проход O(n)).
//  Источник истины в этом режиме — текст; модель синхронизируется через
//  session.applyMarkdownSource (best-effort, swift-markdown отказоустойчив).
//

import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Regex-подсветка Markdown: сброс в моно-шрифт + проход по конструкциям.
/// Работает на NSMutableAttributedString целиком (вызывается из textDidChange).
enum MarkdownSyntaxHighlighter {

    static func highlight(_ storage: NSTextStorage, baseFont: NSFont) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString

        storage.beginEditing()
        // База: моноширинный + обычный цвет.
        storage.addAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor],
                              range: full)

        let lineColor = NSColor.secondaryLabelColor
        let codeBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)

        // Заголовки ATX (# … ######).
        apply(#"(?m)^(#{1,6})(\s.*)$"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue,
                                 range: m.range(at: 1))
            storage.addAttribute(.font, value: fontWithTraits(baseFont, [.bold]), range: m.range)
        }

        // Fenced code blocks (```…```) — весь блок.
        apply(#"(?ms)^```[^\n]*\n(.*?)^```\s*$"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: lineColor, range: m.range)
            storage.addAttribute(.backgroundColor, value: codeBg, range: m.range)
        }

        // Цитаты (> …).
        apply(#"(?m)^>\s?.*$"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: m.range)
        }

        // Маркеры списков (-, *, +, 1.) в начале строки.
        apply(#"(?m)^(\s*)([-*+]|\d+\.)\s"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.systemOrange,
                                 range: m.range(at: 2))
        }

        // Горизонтальная линия (--- / ***).
        apply(#"(?m)^\s*(---+|\*\*\*+)\s*$"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range)
        }

        // Inline code (`…`).
        apply(#"`[^`\n]+`"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.backgroundColor, value: codeBg, range: m.range)
            storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: m.range)
        }

        // **жирный** и *курсив*.
        apply(#"\*\*[^*\n]+\*\*"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.font, value: fontWithTraits(baseFont, [.bold]), range: m.range)
        }
        apply(#"(?<!\*)\*[^*\n]+\*(?!\*)"#, in: storage, text: text) { m, _ in
            // У моноширинных шрифтов (SF Mono/Menlo) нет italic-начертания —
            // descriptor-trait молча не применяется. Используем obliqueness
            // (синтетический наклон), как делают редакторы кода.
            storage.addAttribute(.obliqueness, value: 0.18, range: m.range)
        }

        // ~~зачёркнутый~~.
        apply(#"~~[^~\n]+~~"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: m.range)
        }

        // Ссылки [текст](url).
        apply(#"\[[^\]\n]+\]\([^)\n]+\)"#, in: storage, text: text) { m, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: m.range)
        }

        storage.endEditing()
    }

    private static func apply(_ pattern: String,
                              in storage: NSTextStorage,
                              text: NSString,
                              body: (NSTextCheckingResult, NSTextStorage) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let full = NSRange(location: 0, length: text.length)
        for m in re.matches(in: text as String, range: full) {
            body(m, storage)
        }
    }

    /// Применение bold/italic через NSFontDescriptor — NSFontManager.convert
    /// не умеет системные моноширинные шрифты (возвращает nil/тот же шрифт),
    /// из-за чего **жирный** и *курсив* не подсвечивались (обнаружено
    /// оффскрин-рендером).
    private static func fontWithTraits(_ base: NSFont,
                                       _ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        var t = base.fontDescriptor.symbolicTraits
        t.formUnion(traits)
        let desc = base.fontDescriptor.withSymbolicTraits(t)
        return NSFont(descriptor: desc, size: base.pointSize) ?? base
    }
}

/// Текстовый вид MD: в гибриде рисует картинки поверх скрытых строк `![…](…)`.
final class MarkdownTextView: NSTextView {
    var onWidthChange: (() -> Void)?
    /// Папка документа: сюда (в `images/`) сохраняются вставленные картинки.
    var baseURL: URL?

    /// ⌘B/⌘I/⌘K — Markdown-разметка. По физическому keyCode, чтобы работало на РУ-раскладке;
    /// монитор шорткатов визуального редактора в source/гибриде не живёт (его вью нет в окне).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌥⌘T в таблице — выровнять её; вне таблицы — как раньше (вставка таблицы из меню).
        if window?.firstResponder === self, mods == [.command, .option], event.keyCode == 17,
           MarkdownEditing.formatTable(self) { return true }
        guard window?.firstResponder === self, mods == .command
        else { return super.performKeyEquivalent(with: event) }
        switch event.keyCode {
        case 11: MarkdownEditing.wrap(self, "**")   // ⌘B
        case 34: MarkdownEditing.wrap(self, "*")    // ⌘I
        case 40: MarkdownEditing.insertLink(self)   // ⌘K
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// ⌘-клик по ссылке: документ — в DocxEdit, адрес — в браузере, `#якорь` — к заголовку.
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.mouseDown(with: event)
        }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard let raw = MarkdownEditing.link(in: string as NSString, at: index),
              let target = MarkdownEditing.resolveLink(raw, baseURL: baseURL) else {
            return super.mouseDown(with: event)
        }
        switch target {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return NSSound.beep() }
            let docs: Set<String> = ["docx", "doc", "rtf", "odt", "md", "markdown", "txt"]
            if docs.contains(url.pathExtension.lowercased()) {
                AppDelegate.shared?.loadFromURL(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        case .anchor(let name):
            guard let h = MarkdownEditing.headings(string).first(where: { MarkdownEditing.slug($0.text) == name.lowercased() })
            else { return NSSound.beep() }
            setSelectedRange(NSRange(location: h.location, length: 0))
            scrollRangeToVisible(NSRange(location: h.location, length: 0))
        }
    }

    /// ⌘V с картинкой в буфере — файл в `images/` + ссылка `![](…)`.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let url = Self.imageFileURLs(pb).first {
            MarkdownEditing.insertImageFile(self, url, baseURL: baseURL)
        } else if pb.string(forType: .string) == nil, let image = NSImage(pasteboard: pb) {
            guard let baseURL else { return Self.askToSave() }
            MarkdownEditing.insertImageData(self, image, baseURL: baseURL)
        } else if let text = pb.string(forType: .string), MarkdownEditing.linkSelection(self, url: text) {
            return
        } else {
            super.paste(sender)
        }
    }

    /// Перетаскивание файлов картинок из Finder — ссылки на них.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.imageFileURLs(sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        for url in urls { MarkdownEditing.insertImageFile(self, url, baseURL: baseURL) }
        return true
    }

    private static func imageFileURLs(_ pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
    }

    private static func askToSave() {
        let alert = NSAlert()
        alert.messageText = "Сначала сохраните документ"
        alert.informativeText = "Вставленная картинка сохраняется в папку images рядом с файлом .md."
        alert.runModal()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 1
        super.setFrameSize(newSize)
        if changed { onWidthChange?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return }
        storage.enumerateAttribute(MarkdownHybridRenderer.imageKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let img = value as? NSImage else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard line.intersects(dirtyRect), line.height > 0 else { return }
            let width = img.size.width * line.height / img.size.height
            img.draw(in: NSRect(x: line.minX + tc.lineFragmentPadding, y: line.minY, width: width, height: line.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        storage.enumerateAttribute(MarkdownHybridRenderer.ruleKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard line.intersects(dirtyRect) else { return }
            NSColor.separatorColor.setFill()
            NSRect(x: line.minX + tc.lineFragmentPadding, y: line.midY.rounded() - 0.5,
                   width: line.width - 2 * tc.lineFragmentPadding, height: 1).fill()
        }
        storage.enumerateAttribute(MarkdownHybridRenderer.frontMatterKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let label = value as? String else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard line.intersects(dirtyRect) else { return }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                        .foregroundColor: NSColor.secondaryLabelColor]
            let size = (label as NSString).size(withAttributes: attrs)
            let box = NSRect(x: line.minX + tc.lineFragmentPadding, y: line.midY - size.height / 2 - 3,
                             width: min(size.width + 16, line.width - 2 * tc.lineFragmentPadding), height: size.height + 6)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            (label as NSString).draw(in: box.insetBy(dx: 8, dy: 3), withAttributes: attrs)
        }
        storage.enumerateAttribute(MarkdownHybridRenderer.tableKey,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let table = value as? MarkdownHybridRenderer.MarkdownTable else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let origin = NSPoint(x: line.minX + tc.lineFragmentPadding, y: line.minY)
            let bounds = NSRect(origin: origin, size: NSSize(width: tc.size.width - 2 * tc.lineFragmentPadding,
                                                             height: table.rowHeights.reduce(0, +)))
            if bounds.intersects(dirtyRect) { drawTable(table, in: bounds) }
        }
    }

    private func drawTable(_ table: MarkdownHybridRenderer.MarkdownTable, in bounds: NSRect) {
        let pad = MarkdownHybridRenderer.MarkdownTable.padding
        var y = bounds.minY
        for (r, row) in table.rows.enumerated() {
            let rowHeight = table.rowHeights[r]
            var x = bounds.minX
            for (c, width) in table.columnWidths.enumerated() {
                let cell = NSRect(x: x, y: y, width: width, height: rowHeight)
                if r == 0 {
                    NSColor.quaternaryLabelColor.withAlphaComponent(0.3).setFill()
                    cell.fill()
                }
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: cell.insetBy(dx: 0.25, dy: 0.25)).stroke()
                if c < row.count {
                    let ps = NSMutableParagraphStyle()
                    ps.alignment = c < table.alignments.count ? table.alignments[c] : .left
                    ps.lineBreakMode = .byWordWrapping
                    (row[c] as NSString).draw(
                        with: NSRect(x: cell.minX + pad, y: y + 5, width: width - 2 * pad, height: rowHeight - 10),
                        options: .usesLineFragmentOrigin,
                        attributes: [.font: r == 0 ? table.boldFont : table.font,
                                     .foregroundColor: NSColor.labelColor, .paragraphStyle: ps])
                }
                x += width
            }
            y += rowHeight
        }
    }
}

/// NSViewRepresentable-обёртка: моноширинный NSTextView с автоподсветкой.
struct MarkdownSourceView: NSViewRepresentable {
    @Binding var text: String
    var hybrid: Bool = false
    /// Папка документа — относительные пути картинок в гибриде.
    var baseURL: URL? = nil
    var onChange: (String) -> Void
    /// Разметка под курсором (подсветка кнопок ленты в гибриде).
    var onAttach: ((NSTextView) -> Void)? = nil
    /// Текст выделения — счётчик «N из M» в статусбаре.
    var onSelection: ((String, Int) -> Void)? = nil
    var onCaret: ((MarkdownEditing.CaretState) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        // TextKit 1: гибриду нужна подмена глифов (маркер списка → «•») через NSLayoutManagerDelegate.
        let tv = MarkdownTextView(usingTextLayoutManager: false)
        tv.layoutManager?.delegate = context.coordinator
        tv.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = .labelColor
        tv.backgroundColor = .textBackgroundColor
        tv.textContainerInset = NSSize(width: 20, height: 16)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.string = text
        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.hybrid = hybrid
        context.coordinator.baseURL = baseURL
        context.coordinator.onCaret = onCaret
        context.coordinator.onSelection = onSelection
        tv.baseURL = baseURL
        onAttach?(tv)
        tv.onWidthChange = { [weak coordinator = context.coordinator] in
            if coordinator?.hybrid == true { coordinator?.restyle() }
        }
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        let modeChanged = context.coordinator.hybrid != hybrid || context.coordinator.baseURL != baseURL
        context.coordinator.hybrid = hybrid
        context.coordinator.baseURL = baseURL
        (tv as? MarkdownTextView)?.baseURL = baseURL
        context.coordinator.onCaret = onCaret
        // Внешняя замена (выход/вход в режим, открытие файла) — только если
        // текст реально отличается от того, что в storage (иначе зациклимся).
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.setSelectedRanges(sel, affinity: .downstream, stillSelecting: false)
            context.coordinator.restyle()
        } else if modeChanged {
            context.coordinator.restyle()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        weak var textView: NSTextView?
        var hybrid = false
        var baseURL: URL?
        var onCaret: ((MarkdownEditing.CaretState) -> Void)?
        var onSelection: ((String, Int) -> Void)?
        /// Печать в PDF (v1.10.6): скрытые символы не выводятся, треугольников сворачивания нет.
        var printing = false
        /// Свёрнутые разделы гибрида — по тексту строки заголовка.
        var folded: Set<String> = []
        private var lastCaret: MarkdownEditing.CaretState?
        private var lastActive = NSRange(location: NSNotFound, length: 0)
        let onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        private static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        @MainActor private static var hybridFont: NSFont {
            let p = AppPreferences.shared
            let size = max(p.defaultFontSize, 14)
            return NSFont(name: p.defaultFontName, size: size) ?? .systemFont(ofSize: size)
        }

        /// Перерисовка атрибутов с сохранением выделения (текст не меняется).
        @MainActor func restyle() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let sel = tv.selectedRanges
            if hybrid {
                let font = Self.hybridFont
                lastActive = MarkdownHybridRenderer.activeRange(in: tv.string as NSString,
                                                               selection: tv.selectedRange())
                let maxWidth = max(100, (tv.textContainer?.size.width ?? 600) - 2 * (tv.textContainer?.lineFragmentPadding ?? 0))
                MarkdownHybridRenderer.render(storage, baseFont: font, active: lastActive,
                                              baseURL: baseURL, maxImageWidth: maxWidth, folded: folded)
                tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
            } else {
                // Сброс атрибутов гибрида (glyphKey, link, отступы) — подсветка только добавляет свои.
                storage.setAttributes([:], range: NSRange(location: 0, length: storage.length))
                MarkdownSyntaxHighlighter.highlight(storage, baseFont: Self.monoFont)
                tv.typingAttributes = [.font: Self.monoFont, .foregroundColor: NSColor.labelColor]
            }
            tv.setSelectedRanges(sel, affinity: .downstream, stillSelecting: false)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            restyle()
            onChange(tv.string)
        }

        /// Гибрид: при переходе курсора в другой блок раскрываем его разметку.
        func textViewDidChangeSelection(_ notification: Notification) {
            if let tv = textView {
                onSelection?((tv.string as NSString).substring(with: tv.selectedRange()), tv.selectedRange().location)
            }
            guard hybrid, let tv = textView else { return }
            let caret = MarkdownEditing.caretState(tv.string as NSString, at: tv.selectedRange().location)
            if caret != lastCaret { lastCaret = caret; onCaret?(caret) }
            let active = MarkdownHybridRenderer.activeRange(in: tv.string as NSString,
                                                           selection: tv.selectedRange())
            if active != lastActive { restyle() }
        }

        /// Гибрид: глифы знаков с glyphKey рисуются другим символом (текст не меняется).
        func layoutManager(_ layoutManager: NSLayoutManager,
                           shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes charIndexes: UnsafePointer<Int>,
                           font aFont: NSFont,
                           forGlyphRange glyphRange: NSRange) -> Int {
            guard let storage = layoutManager.textStorage else { return 0 }
            var newGlyphs: [CGGlyph]?
            var newProps: [NSLayoutManager.GlyphProperty]?
            for i in 0..<glyphRange.length {
                let ci = charIndexes[i]
                guard ci < storage.length else { continue }
                // Печать: скрытая разметка — нулевые глифы, чтобы не попала в текстовый слой PDF.
                // Строки таблиц/картинок/линий не трогаем: их отрисовка опирается на глифы строки.
                if printing, (storage.string as NSString).character(at: ci) != 10,
                   (storage.attribute(.foregroundColor, at: ci, effectiveRange: nil) as? NSColor) == .clear,
                   ![MarkdownHybridRenderer.tableKey, MarkdownHybridRenderer.imageKey, MarkdownHybridRenderer.ruleKey,
                     MarkdownHybridRenderer.frontMatterKey].contains(where: { storage.attribute($0, at: ci, effectiveRange: nil) != nil }) {
                    if newGlyphs == nil {
                        newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                        newProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
                    }
                    newProps![i] = .null
                    continue
                }
                guard let sym = storage.attribute(MarkdownHybridRenderer.glyphKey, at: ci, effectiveRange: nil) as? String
                else { continue }
                var units = Array(sym.utf16)
                var g: [CGGlyph] = Array(repeating: 0, count: units.count)
                guard CTFontGetGlyphsForCharacters(aFont, &units, &g, units.count), g[0] != 0 else { continue }
                if newGlyphs == nil {
                    newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                    newProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
                }
                newGlyphs![i] = g[0]
                newProps![i] = []
            }
            guard let ng = newGlyphs, let np = newProps else { return 0 }
            layoutManager.setGlyphs(ng, properties: np, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
            return glyphRange.length
        }

        /// Клик по чекбоксу задачи: «[ ]» ⇄ «[x]» обычной правкой текста (с undo).
        func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if (link as? URL)?.scheme == MarkdownHybridRenderer.foldScheme {
                let ns = tv.string as NSString
                let line = ns.substring(with: ns.lineRange(for: NSRange(location: charIndex, length: 0)))
                    .trimmingCharacters(in: .newlines)
                if folded.remove(line) == nil { folded.insert(line) }
                restyle()
                return true
            }
            guard (link as? URL)?.scheme == MarkdownHybridRenderer.taskScheme else { return false }
            let r = NSRange(location: charIndex, length: 1)
            let done = (tv.string as NSString).substring(with: r) != " "
            if tv.shouldChangeText(in: r, replacementString: done ? " " : "x") {
                tv.textStorage?.replaceCharacters(in: r, with: done ? " " : "x")
                tv.didChangeText()
            }
            return true
        }

        // MARK: - Typora-поведение (v1.6.4): Enter/Tab в списках — MarkdownEditing

        func textView(_ tv: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSTextView.insertNewline(_:)):
                return MarkdownEditing.continueList(tv)
            case #selector(NSTextView.insertTab(_:)):
                return MarkdownEditing.indentListLine(tv, increase: true)
            case #selector(NSTextView.insertBacktab(_:)):
                return MarkdownEditing.indentListLine(tv, increase: false)
            default:
                return false
            }
        }
    }
}

extension MarkdownSourceView {
    /// v1.10.6: PDF в гибридном виде (заголовки, «•», таблицы, картинки, без разметки) —
    /// печать скрытой копии редактора: A4, поля 2 см, светлое оформление.
    @MainActor static func exportHybridPDF(_ text: String, baseURL: URL?, to url: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 595, height: 842)
        for margin in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] { info[keyPath: margin] = 57 }
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let width = info.paperSize.width - info.leftMargin - info.rightMargin

        let coordinator = Coordinator(onChange: { _ in })
        let tv = MarkdownTextView(usingTextLayoutManager: false)
        tv.appearance = NSAppearance(named: .aqua)
        tv.backgroundColor = .white
        tv.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.layoutManager?.delegate = coordinator
        // Курсор на пустой последней строке — ни один блок не «активен», разметка скрыта везде.
        tv.string = text.hasSuffix("\n") ? text : text + "\n"
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        coordinator.textView = tv
        coordinator.hybrid = true
        coordinator.printing = true
        coordinator.baseURL = baseURL
        coordinator.restyle()
        // Треугольники сворачивания на бумаге не нужны.
        if let storage = tv.textStorage {
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
                guard (v as? URL)?.scheme == MarkdownHybridRenderer.foldScheme else { return }
                storage.removeAttribute(MarkdownHybridRenderer.glyphKey, range: r)
                storage.addAttributes(MarkdownHybridRenderer.hiddenAttributes, range: r)
            }
        }
        tv.sizeToFit()

        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw CocoaError(.fileWriteUnknown) }
    }
}
