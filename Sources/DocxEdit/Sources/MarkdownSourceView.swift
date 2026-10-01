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

/// NSViewRepresentable-обёртка: моноширинный NSTextView с автоподсветкой.
struct MarkdownSourceView: NSViewRepresentable {
    @Binding var text: String
    var hybrid: Bool = false
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        // TextKit 1: гибриду нужна подмена глифов (маркер списка → «•») через NSLayoutManagerDelegate.
        let tv = NSTextView(usingTextLayoutManager: false)
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
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        let modeChanged = context.coordinator.hybrid != hybrid
        context.coordinator.hybrid = hybrid
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
                MarkdownHybridRenderer.render(storage, baseFont: font, active: lastActive)
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
            guard hybrid, let tv = textView else { return }
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
                guard ci < storage.length,
                      let sym = storage.attribute(MarkdownHybridRenderer.glyphKey, at: ci, effectiveRange: nil) as? String
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
            guard (link as? URL)?.scheme == MarkdownHybridRenderer.taskScheme else { return false }
            let r = NSRange(location: charIndex, length: 1)
            let done = (tv.string as NSString).substring(with: r) != " "
            if tv.shouldChangeText(in: r, replacementString: done ? " " : "x") {
                tv.textStorage?.replaceCharacters(in: r, with: done ? " " : "x")
                tv.didChangeText()
            }
            return true
        }

        // MARK: - Typora-поведение (v1.6.4)

        /// Enter в пункте списка — продолжить маркер ("- ", "1. ").
        /// Enter на ПУСТОМ пункте — выйти из списка (маркер удаляется).
        private let markerRegex = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s+"#)

        func textView(_ tv: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSTextView.insertNewline(_:)):
                return handleNewline(tv)
            case #selector(NSTextView.insertTab(_:)):
                return handleTab(tv, backtab: false)
            case #selector(NSTextView.insertBacktab(_:)):
                return handleTab(tv, backtab: true)
            default:
                return false
            }
        }

        private func handleNewline(_ tv: NSTextView) -> Bool {
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let m = markerRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
                return false  // не список — обычный Enter
            }
            let marker = (line as NSString).substring(with: m.range)
            // Пустой пункт (только маркер) — выйти из списка: стереть маркер
            // и вставить обычный перевод строки.
            if line.trimmingCharacters(in: .whitespaces) ==
                  marker.trimmingCharacters(in: .whitespaces) {
                let markerRange = NSRange(location: lineRange.location,
                                          length: (marker as NSString).length)
                tv.insertText("", replacementRange: markerRange)
                tv.insertNewline(nil)
                return true
            }
            // Нумерованный — инкремент числа.
            var nextMarker = marker
            if let num = Int(marker.trimmingCharacters(in: .whitespaces).dropLast()) {
                nextMarker = "\(num + 1). "
            }
            tv.insertText("\n" + nextMarker, replacementRange: sel)
            return true
        }

        /// Tab — вложить строку списка (2 пробела); Shift+Tab — вынуть.
        private func handleTab(_ tv: NSTextView, backtab: Bool) -> Bool {
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = ns.substring(with: lineRange)
            guard markerRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length)) != nil else {
                return false  // не список — обычный таб
            }
            if backtab {
                // Убрать до 2 ведущих пробелов.
                var trimmed = line
                var removed = 0
                while removed < 2, trimmed.hasPrefix(" ") {
                    trimmed.removeFirst(); removed += 1
                }
                guard removed > 0 else { return true }
                tv.insertText(trimmed, replacementRange: lineRange)
            } else {
                tv.insertText("  " + line, replacementRange: lineRange)
            }
            // Вернуть курсор в конец строки.
            let newLineRange = (tv.string as NSString).lineRange(
                for: NSRange(location: lineRange.location, length: 0))
            tv.setSelectedRange(NSRange(location: NSMaxRange(newLineRange) - 1, length: 0))
            return true
        }
    }
}
