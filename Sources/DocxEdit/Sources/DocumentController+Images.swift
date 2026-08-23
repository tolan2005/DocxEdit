//
//  DocumentController+Images.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Вставка изображений и гиперссылки — v0.1.52+
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore
import UniformTypeIdentifiers

extension DocumentController {
    // MARK: - Вставка изображения (v0.1.52, R03)

    /// Показывает NSOpenPanel для выбора изображения (PNG/JPEG/GIF/TIFF) и вставляет
    /// его в позицию курсора как inline-attachment. Размер отображения — clamp по
    /// доступной ширине контейнера (`textContainer.containerSize.width`), с сохранением
    /// пропорций.
    func insertImageInteractive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.png, .jpeg, .gif, .tiff, .heic]
        if let svg = UTType("public.svg-image") { types.append(svg) }
        panel.allowedContentTypes = types
        panel.title = "Вставить изображение"
        panel.prompt = "Вставить"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        insertImage(from: url)
    }

    /// Читает файл изображения по URL, создаёт `InlineImage` и вставляет через
    /// `NSTextAttachment` одним атомарным `replaceCharacters` под `shouldChangeText`
    /// (один шаг undo, паттерн ADR-027).
    func insertImage(from url: URL) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard var data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        // Модель/DOCX хранят только PNG/JPEG/GIF/TIFF (форматы, поддерживаемые OOXML).
        // HEIC/SVG (v0.1.97) — конвертируем в PNG на этапе импорта: NSImage читает
        // оба формата нативно (macOS 14+), рендерим через NSBitmapImageRep→PNG.
        // SVG рендерится в растр — векторное качество теряется (для DOCX неизбежно
        // всё равно, т.к. встраивание SVG в OOXML стало распространено недавно).
        var format: InlineImageFormat
        switch ext {
        case "png": format = .png
        case "jpg", "jpeg": format = .jpeg
        case "gif": format = .gif
        case "tif", "tiff": format = .tiff
        case "heic", "heif", "svg":
            guard let src = NSImage(data: data),
                  let tiff = src.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            data = png
            format = .png
        default: format = .png
        }
        guard let ns = NSImage(data: data) else { return }
        // Ужимаем ширину до доступной, если картинка шире.
        let containerW: CGFloat = {
            if let c = tv.textContainer, c.containerSize.width > 0, c.containerSize.width < .infinity {
                return c.containerSize.width - 8 // с зазором
            }
            return 400
        }()
        var displayW = ns.size.width
        var displayH = ns.size.height
        if displayW > containerW, displayW > 0 {
            let scale = containerW / displayW
            displayW = containerW
            displayH *= scale
        }
        let img = InlineImage(format: format, data: data,
                              displayWidth: displayW, displayHeight: displayH)
        let att = makeImageAttachment(from: img)
        let attStr = NSAttributedString(attachment: att)
        let m = NSMutableAttributedString(attributedString: attStr)
        // Наследуем параграф-стиль и шрифт от позиции курсора.
        let sel = tv.selectedRange()
        var attrs = tv.typingAttributes
        if sel.location > 0, sel.location <= storage.length {
            let src = min(sel.location - 1, storage.length - 1)
            if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
        }
        // Уберём старый .attachment из наследуемых атрибутов (он бы приклеился
        // как отдельный ключ, ломая рендер новой картинки).
        attrs.removeValue(forKey: .attachment)
        m.addAttributes(attrs, range: NSRange(location: 0, length: m.length))

        guard tv.shouldChangeText(in: sel, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: sel.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    // MARK: - Гиперссылки (v0.1.54, R03)

    /// URL гиперссылки в позиции курсора (или в начале выделения). nil, если
    /// на этой позиции ссылки нет. Используется для prefill диалога ⌘K.
    func hyperlinkAtCaret() -> String? {
        guard let tv = textView, let storage = tv.textStorage else { return nil }
        let sel = tv.selectedRange()
        let idx = min(sel.location, storage.length - 1)
        guard idx >= 0, storage.length > 0 else { return nil }
        if let s = storage.attribute(.link, at: idx, effectiveRange: nil) as? String { return s }
        if let u = storage.attribute(.link, at: idx, effectiveRange: nil) as? URL { return u.absoluteString }
        return nil
    }

    /// Текст выделения (пусто = нет выделения). Для prefill поля «Текст» в диалоге.
    func selectedText() -> String {
        guard let tv = textView, let storage = tv.textStorage else { return "" }
        let sel = tv.selectedRange()
        guard sel.length > 0, NSMaxRange(sel) <= storage.length else { return "" }
        return (storage.string as NSString).substring(with: sel)
    }

    /// Вставляет/применяет гиперссылку. Если выделение не пустое — применяет
    /// URL к нему (текст выделения не заменяется, даже если `text` отличается —
    /// сохраняем исходное форматирование). Если выделения нет — вставляет `text`
    /// с гиперссылкой. Один атомарный `replaceCharacters` под shouldChangeText —
    /// один шаг undo (паттерн ADR-027).
    func insertHyperlink(text: String, url: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }

        if sel.length > 0 {
            // Применить к выделению: перезаписываем содержимое теми же символами
            // + атрибут .link, чтобы получить один связный undo (см. ADR-027).
            let existing = storage.attributedSubstring(from: sel)
            let m = NSMutableAttributedString(attributedString: existing)
            m.addAttribute(.link, value: cleanURL, range: NSRange(location: 0, length: m.length))
            guard tv.shouldChangeText(in: sel, replacementString: m.string) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: sel, with: m)
            storage.endEditing()
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + m.length, length: 0))
        } else {
            // Вставить новый текст с ссылкой; атрибуты — из позиции курсора.
            let insertText = text.isEmpty ? cleanURL : text
            var attrs = tv.typingAttributes
            if sel.location > 0, sel.location <= storage.length {
                let src = min(sel.location - 1, storage.length - 1)
                if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
            }
            attrs[.link] = cleanURL
            let attributed = NSAttributedString(string: insertText, attributes: attrs)
            guard tv.shouldChangeText(in: sel, replacementString: insertText) else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: sel, with: attributed)
            storage.endEditing()
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + attributed.length, length: 0))
        }
        notifyModelChange()
        refreshSelectionState()
    }

}
