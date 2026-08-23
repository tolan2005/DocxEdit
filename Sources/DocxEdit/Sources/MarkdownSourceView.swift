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
    var onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let tv = NSTextView()
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
        // Начальная подсветка.
        if let storage = tv.textStorage {
            MarkdownSyntaxHighlighter.highlight(
                storage, baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        // Внешняя замена (выход/вход в режим, открытие файла) — только если
        // текст реально отличается от того, что в storage (иначе зациклимся).
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.setSelectedRanges(sel, affinity: .downstream, stillSelecting: false)
            if let storage = tv.textStorage {
                MarkdownSyntaxHighlighter.highlight(
                    storage, baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        let onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            // Подсветка с сохранением курсора.
            let sel = tv.selectedRanges
            MarkdownSyntaxHighlighter.highlight(
                storage, baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular))
            tv.setSelectedRanges(sel, affinity: .downstream, stillSelecting: false)
            onChange(tv.string)
        }
    }
}
