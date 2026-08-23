//
//  DocumentController+ImageProperties.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Свойства изображения (диалог, ресайз, кроп, поворот) — v0.1.60+
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore
import NaturalLanguage
import UniformTypeIdentifiers

extension DocumentController {
    // MARK: - Свойства изображения (v0.1.60, R03)

    /// Диапазон U+FFFC-символа с `.attachment` в позиции курсора (или выделении).
    /// Возвращает nil, если курсор/выделение не на inline-изображении.
    func imageRangeAtCaret() -> NSRange? {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return nil }
        let sel = tv.selectedRange()
        // Если выделен ровно 1 символ и это attachment — берём его.
        if sel.length == 1, sel.location < storage.length,
           storage.attribute(.attachment, at: sel.location, effectiveRange: nil) is NSTextAttachment {
            return sel
        }
        // Иначе — предыдущий символ от курсора (частый случай: клик правой кнопкой ставит курсор ЗА изображением).
        let idx = min(max(sel.location - 1, 0), storage.length - 1)
        if idx >= 0, storage.attribute(.attachment, at: idx, effectiveRange: nil) is NSTextAttachment {
            return NSRange(location: idx, length: 1)
        }
        // И сам символ на позиции курсора — если он есть.
        if sel.location < storage.length,
           storage.attribute(.attachment, at: sel.location, effectiveRange: nil) is NSTextAttachment {
            return NSRange(location: sel.location, length: 1)
        }
        return nil
    }

    /// Метаданные изображения в позиции курсора: ширина в points, alt-text, выравнивание абзаца.
    /// Используется для prefill диалога «Свойства изображения».
    func imagePropertiesAtCaret() -> (widthPt: CGFloat, heightPt: CGFloat, altText: String, alignment: NSTextAlignment)? {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return nil }
        let alt = (storage.attribute(.docxEditImageAltText, at: range.location, effectiveRange: nil) as? String) ?? ""
        let ps = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
        return (att.bounds.width, att.bounds.height, alt, ps.alignment)
    }

    /// Сохраняет режим обтекания изображения (v0.1.102). Записывается в custom
    /// NSAttributedString-ключ; `DocumentModel.from(attributed:)` подхватывает.
    func setImageWrapAtCaret(_ wrap: InlineImageWrap) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret() else { return }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.docxEditImageWrap, value: wrap.rawValue, range: range)
        storage.endEditing()
        tv.didChangeText()
        notifyModelChange()
        refreshSelectionState()
    }

    /// Возвращает текущий режим обтекания изображения под курсором (или .inline если нет).
    func imageWrapAtCaret() -> InlineImageWrap {
        guard let storage = textView?.textStorage,
              let range = imageRangeAtCaret(),
              let raw = storage.attribute(.docxEditImageWrap, at: range.location, effectiveRange: nil) as? String,
              let w = InlineImageWrap(rawValue: raw)
        else { return .inline }
        return w
    }

    /// Обновляет размер и/или alt-text изображения в позиции курсора.
    /// Один атомарный `replaceCharacters` под shouldChangeText — один шаг undo.
    /// `newWidthPt`==0 сохраняет прежнюю ширину; аналогично `newHeightPt`. `newAltText`==nil
    /// не меняет alt-text; пустая строка — сбрасывает.
    func updateImageAtCaret(newWidthPt: CGFloat, newHeightPt: CGFloat, newAltText: String?) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return }
        // Собираем новый attachment: копируем image, ставим bounds.
        let newAtt = NSTextAttachment()
        newAtt.image = att.image
        let curW = att.bounds.width
        let curH = att.bounds.height
        let targetW = newWidthPt > 0 ? newWidthPt : curW
        // Сохраняем пропорции, если задана только ширина.
        let targetH: CGFloat
        if newHeightPt > 0 {
            targetH = newHeightPt
        } else if newWidthPt > 0 && curW > 0 {
            targetH = curH * (newWidthPt / curW)
        } else {
            targetH = curH
        }
        newAtt.bounds = NSRect(x: 0, y: 0, width: targetW, height: targetH)

        // Строим новый одиночный attributed-symbol с прежними атрибутами (paragraph, hyperlink, styleId и т.д.).
        var attrs = storage.attributes(at: range.location, effectiveRange: nil)
        attrs[.attachment] = newAtt
        if let alt = newAltText {
            if alt.isEmpty { attrs.removeValue(forKey: .docxEditImageAltText) }
            else { attrs[.docxEditImageAltText] = alt }
        }
        let m = NSAttributedString(string: "\u{FFFC}", attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Поворачивает изображение под курсором по часовой стрелке на `degreesCW`
    /// градусов (bake в bitmap — angle не хранится отдельно). Один шаг undo.
    /// Для 90°/270° меняет местами width/height у attachment bounds.
    func rotateImageAtCaret(degreesCW: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image,
              let rotated = bakeRotated(src, degreesCW: degreesCW) else { return }
        let normalized = Int((degreesCW.truncatingRemainder(dividingBy: 180)).rounded())
        let swap = normalized != 0
        let curW = att.bounds.width
        let curH = att.bounds.height
        let newW = swap ? curH : curW
        let newH = swap ? curW : curH
        writeRotatedAttachment(rotated, size: NSSize(width: newW, height: newH),
                               at: range, in: storage, tv: tv)
    }

    /// Зеркалит изображение по горизонтали (bake в bitmap). Один шаг undo.
    func flipImageAtCaretHorizontal() {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image,
              let flipped = bakeFlipped(src, horizontal: true) else { return }
        writeRotatedAttachment(flipped, size: att.bounds.size, at: range, in: storage, tv: tv)
    }

    private func writeRotatedAttachment(_ image: NSImage, size: NSSize, at range: NSRange,
                                        in storage: NSTextStorage, tv: NSTextView) {
        let newAtt = NSTextAttachment()
        newAtt.image = image
        newAtt.bounds = NSRect(origin: .zero, size: size)
        var attrs = storage.attributes(at: range.location, effectiveRange: nil)
        attrs[.attachment] = newAtt
        let m = NSAttributedString(string: "\u{FFFC}", attributes: attrs)
        guard tv.shouldChangeText(in: range, replacementString: m.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: m)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + m.length, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    private func bakeRotated(_ src: NSImage, degreesCW: CGFloat) -> NSImage? {
        let origSize = src.size
        guard origSize.width > 0, origSize.height > 0 else { return nil }
        let swap = Int((degreesCW.truncatingRemainder(dividingBy: 180)).rounded()) != 0
        let newSize = swap ? NSSize(width: origSize.height, height: origSize.width) : origSize
        let out = NSImage(size: newSize)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let t = NSAffineTransform()
        t.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        // CW-поворот в системе координат AppKit (y-up) = negative radians.
        t.rotate(byRadians: -degreesCW * .pi / 180)
        t.translateX(by: -origSize.width / 2, yBy: -origSize.height / 2)
        t.concat()
        src.draw(at: .zero, from: NSRect(origin: .zero, size: origSize),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    private func bakeFlipped(_ src: NSImage, horizontal: Bool) -> NSImage? {
        let s = src.size
        guard s.width > 0, s.height > 0 else { return nil }
        let out = NSImage(size: s)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let t = NSAffineTransform()
        if horizontal {
            t.translateX(by: s.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
        } else {
            t.translateX(by: 0, yBy: s.height)
            t.scaleX(by: 1, yBy: -1)
        }
        t.concat()
        src.draw(at: .zero, from: NSRect(origin: .zero, size: s),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        return out
    }

    /// Возвращает NSImage изображения под курсором (для визуального диалога обрезки).
    func imageAtCaret() -> NSImage? {
        guard let storage = textView?.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment
        else { return nil }
        return att.image
    }

    /// Обрезает изображение под курсором. `top`/`right`/`bottom`/`left` — доли [0, 1)
    /// от исходных сторон, обрезаемые с соответствующего края. Bake в bitmap; один шаг undo.
    func cropImageAtCaret(topFrac: CGFloat, rightFrac: CGFloat, bottomFrac: CGFloat, leftFrac: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret(),
              let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let src = att.image else { return }
        let t = max(0, min(0.99, topFrac))
        let r = max(0, min(0.99, rightFrac))
        let b = max(0, min(0.99, bottomFrac))
        let l = max(0, min(0.99, leftFrac))
        guard (l + r) < 1, (t + b) < 1 else { return }
        let origSize = src.size
        guard origSize.width > 0, origSize.height > 0 else { return }
        let newW = origSize.width  * (1 - l - r)
        let newH = origSize.height * (1 - t - b)
        let out = NSImage(size: NSSize(width: newW, height: newH))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        // Источник рисуем со сдвигом: (-l·W, -b·H) (нижний-левый угол исходника ниже
        // нового bounds на bottomFrac, левее на leftFrac).
        src.draw(at: NSPoint(x: -origSize.width * l, y: -origSize.height * b),
                 from: NSRect(origin: .zero, size: origSize),
                 operation: .sourceOver, fraction: 1.0)
        out.unlockFocus()
        // Отобразительные размеры сохраняют пропорции обрезки:
        let curW = att.bounds.width
        let curH = att.bounds.height
        let dispW = curW * (1 - l - r)
        let dispH = curH * (1 - t - b)
        writeRotatedAttachment(out, size: NSSize(width: dispW, height: dispH),
                               at: range, in: storage, tv: tv)
    }

    /// Удаляет изображение в позиции курсора — один шаг undo.
    func deleteImageAtCaret() {
        guard let tv = textView, let storage = tv.textStorage,
              let range = imageRangeAtCaret() else { return }
        guard tv.shouldChangeText(in: range, replacementString: "") else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: "")
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// True, если курсор на inline-изображении (для disabled-state пунктов меню).
    var isCaretOnImage: Bool { imageRangeAtCaret() != nil }

    /// Вставляет разрыв страницы (U+000C, Form Feed) в позиции курсора.
    /// В DOCX сериализуется как `<w:br w:type="page"/>` (см. DocxIO renderRun).
    /// При включённых непечатаемых символах DocxLayoutManager рисует маркер.
    func insertPageBreak() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let breakStr = "\u{000C}"
        guard tv.shouldChangeText(in: range, replacementString: breakStr) else { return }
        var attrs = tv.typingAttributes
        // Наследуем шрифт из позиции курсора; если пусто — из typingAttributes.
        if range.location > 0, range.location <= storage.length {
            let src = min(range.location - 1, storage.length - 1)
            if src >= 0 { attrs = storage.attributes(at: src, effectiveRange: nil) }
        }
        let attributed = NSAttributedString(string: breakStr, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: attributed)
        storage.endEditing()
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
        notifyModelChange()
    }

    /// Переход по номеру страницы/строки/абзаца. Возвращает true, если целевой
    /// объект найден (курсор поставлен и скролл выполнен). Страница оценивается
    /// как в статистике (usedRect / (pageHeight - margins)).
    func goTo(target: GoToTarget, number: Int) -> Bool {
        guard let tv = textView, let storage = tv.textStorage, number >= 1 else { return false }
        let text = storage.string as NSString

        switch target {
        case .paragraph:
            guard let start = paragraphStart(number: number, in: text) else { return false }
            focus(range: NSRange(location: start, length: 0))
            return true

        case .line:
            guard let lm = tv.layoutManager else { return false }
            var count = 0
            var foundGlyphRange: NSRange?
            let glyphRange = lm.glyphRange(for: tv.textContainer!)
            lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, gRange, stop in
                count += 1
                if count == number {
                    foundGlyphRange = gRange
                    stop.pointee = true
                }
            }
            guard let gr = foundGlyphRange else { return false }
            let charRange = lm.characterRange(forGlyphRange: gr, actualGlyphRange: nil)
            focus(range: NSRange(location: charRange.location, length: 0))
            return true

        case .page:
            guard let lm = tv.layoutManager, let tc = tv.textContainer,
                  let storage = tv.textStorage else { return false }
            let pageSettings = session?.bridge.model.pageSettings
            let pageHeight   = pageSettings?.pageSizeInPoints.height ?? 842
            let topMargin    = CGFloat(pageSettings?.margins.top    ?? 72)
            let bottomMargin = CGFloat(pageSettings?.margins.bottom ?? 72)
            let usable = max(1, pageHeight - topMargin - bottomMargin)
            let targetY = usable * CGFloat(number - 1)
            // Форсируем layout до запроса glyphIndex — иначе на «непрогретом» LM
            // (только что открытом документе) glyphIndex(for:in:) может вернуть 0.
            lm.ensureLayout(for: tc)
            let numGlyphs = lm.numberOfGlyphs
            guard numGlyphs > 0 else {
                focus(range: NSRange(location: 0, length: 0))
                return true
            }
            let glyphIdx = lm.glyphIndex(for: NSPoint(x: 0, y: targetY), in: tc)
            // Clamp — glyphIndex может вернуть numGlyphs (за концом) или fractional-адрес.
            let safeGlyphIdx = min(max(0, glyphIdx), numGlyphs - 1)
            let charIdx = lm.characterIndexForGlyph(at: safeGlyphIdx)
            let safeCharIdx: Int
            if charIdx == NSNotFound || charIdx < 0 {
                safeCharIdx = 0
            } else {
                safeCharIdx = min(charIdx, storage.length)
            }
            focus(range: NSRange(location: safeCharIdx, length: 0))
            return true
        }
    }

    private func paragraphStart(number: Int, in text: NSString) -> Int? {
        var idx = 0
        var loc = 0
        let total = text.length
        while true {
            idx += 1
            if idx == number { return loc }
            let paraRange = text.paragraphRange(for: NSRange(location: loc, length: 0))
            let next = paraRange.location + paraRange.length
            if next > total || next <= loc { return nil }
            loc = next
        }
    }

    private func focus(range: NSRange) {
        guard let tv = textView else { return }
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.window?.makeFirstResponder(tv)
    }

    func performFinder(_ action: NSTextFinder.Action) {
        guard let textView else { return }
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        textView.performTextFinderAction(item)
    }

    func setZoom(_ level: Double) { zoomLevel = max(0.25, min(4.0, level)) }
    func zoomIn()    { setZoom(snapZoom(up: true)) }
    func zoomOut()   { setZoom(snapZoom(up: false)) }
    func resetZoom() { setZoom(1.0) }

    /// Подгоняет масштаб так, чтобы ширина ОДНОЙ страницы совпала с шириной вьюпорта.
    /// Считает: newMag = viewportWidth / (pageWidth + внешний зазор).
    func fitPageWidth() {
        guard let sv = textView?.enclosingScrollView else { return }
        let viewportW = sv.contentSize.width
        let pageW = session?.bridge.model.pageSettings.pageSizeInPoints.width ?? 595
        guard pageW > 0, viewportW > 0 else { return }
        // Небольшой запас (16pt) чтобы страница не упиралась в края скролла.
        setZoom(Double((viewportW - 16) / pageW))
    }

    /// Подгоняет масштаб так, чтобы ДВЕ страницы поместились рядом по ширине.
    func fitTwoPages() {
        guard let sv = textView?.enclosingScrollView else { return }
        let viewportW = sv.contentSize.width
        let pageW = session?.bridge.model.pageSettings.pageSizeInPoints.width ?? 595
        guard pageW > 0, viewportW > 0 else { return }
        // 2 страницы + зазор между ними (16pt) + запас по краям (24pt).
        setZoom(Double((viewportW - 24) / (pageW * 2 + 16)))
    }

    private func snapZoom(up: Bool) -> Double {
        if up  { return zoomSteps.first(where: { $0 > zoomLevel + 0.01 }) ?? 4.0 }
        else   { return zoomSteps.last(where:  { $0 < zoomLevel - 0.01 }) ?? 0.25 }
    }

    /// Очистка форматирования в выделении.
    func clearFormatting() {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ]
        } else if textView.shouldChangeText(in: range, replacementString: nil) {
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributes([
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ], range: range)
            textView.textStorage?.endEditing()
            textView.didChangeText()
            notifyModelChange()
        }
        refreshSelectionState()
    }

    /// Обновляет все UI-флаги на основе курсора/выделения.
    /// При смешанном выделении: fontName = "", fontSize = 0, hasMixedFonts/Sizes = true.
    /// Определяет язык текущего абзаца через NLLanguageRecognizer (для отображения
    /// в статусбаре). Использует до 1000 символов вокруг курсора для скорости.
    private func detectLanguageAroundCaret() -> String? {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let loc = min(textView.selectedRange().location, ns.length - 1)
        let start = max(0, loc - 500)
        let end = min(ns.length, loc + 500)
        let sample = ns.substring(with: NSRange(location: start, length: end - start))
        // NLLanguageRecognizer нужен ≥ нескольких слов; пустой/короткий текст → nil.
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Устанавливает язык проверки орфографии для NSTextView. Влияет на
    /// подчёркивание орфографических ошибок; текущее определение языка в
    /// статусбаре — независимая величина.
    func setSpellCheckLanguage(_ code: String) {
        guard let textView else { return }
        textView.setSpellingState(0, range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        NSSpellChecker.shared.setLanguage(code)
        // Пере-запустить проверку — простой способ: re-toggle continuousSpellChecking.
        let was = textView.isContinuousSpellCheckingEnabled
        textView.isContinuousSpellCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = was
    }

    func refreshSelectionState() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()

        // v1.6.5: текущий раздел для подсветки в навигаторе — последний
        // заголовок с location <= начала выделения.
        do {
            var current: Int? = nil
            let ns = storage.string as NSString
            var pos = 0
            let len = ns.length
            while pos < len {
                let pr = ns.paragraphRange(for: NSRange(location: pos, length: 0))
                if pr.location > range.location { break }
                if let sid = storage.attribute(.docxEditStyleId, at: pr.location, effectiveRange: nil) as? String,
                   sid.hasPrefix("Heading"),
                   Int(sid.dropFirst("Heading".count)) != nil {
                    current = pr.location
                }
                pos = NSMaxRange(pr)
            }
            if current != currentHeadingLocation { currentHeadingLocation = current }
        }

        if range.length > 0 {
            // Анализируем все шрифты/размеры в выделении
            var fontNames = Set<String>()
            var fontSizes = Set<CGFloat>()
            storage.enumerateAttribute(.font, in: range, options: []) { val, _, _ in
                if let f = val as? NSFont {
                    fontNames.insert(f.familyName ?? f.fontName)
                    fontSizes.insert(f.pointSize)
                }
            }
            hasMixedFonts = fontNames.count > 1
            hasMixedSizes = fontSizes.count > 1
            fontName = hasMixedFonts ? "" : (fontNames.first ?? fontName)
            fontSize  = hasMixedSizes ? 0 : (fontSizes.first ?? fontSize)

            // B/I/U — по первому символу выделения
            let first = storage.attributes(at: range.location, effectiveRange: nil)
            if let f = first[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                isBold   = t.contains(.bold)
                isItalic = t.contains(.italic)
            }
            isUnderline     = ((first[.underlineStyle]     as? Int) ?? 0) != 0
            isStrikethrough = ((first[.strikethroughStyle] as? Int) ?? 0) != 0
            let firstOffset = (first[.baselineOffset] as? CGFloat) ?? 0
            isSuperscript = firstOffset > 0.5
            isSubscript   = firstOffset < -0.5
            if let c = first[.foregroundColor] as? NSColor { textColor = c }
            highlightColor = first[.backgroundColor] as? NSColor
            if let ps = first[.paragraphStyle] as? NSParagraphStyle {
                textAlignment = ps.alignment
                lineSpacingMultiple = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1.0
                updateListState(from: ps)
            }
            currentStyleId = (first[.docxEditStyleId] as? String) ?? "Normal"
            currentCharStyleId = first[.docxEditCharStyleId] as? String
        } else {
            // Позиция курсора — typingAttributes
            hasMixedFonts = false
            hasMixedSizes = false
            let attrs = textView.typingAttributes
            if let f = attrs[.font] as? NSFont {
                let t = f.fontDescriptor.symbolicTraits
                isBold    = t.contains(.bold)
                isItalic  = t.contains(.italic)
                fontName  = f.familyName ?? f.fontName
                fontSize  = f.pointSize
            }
            isUnderline     = ((attrs[.underlineStyle]     as? Int) ?? 0) != 0
            isStrikethrough = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0
            let attrsOffset = (attrs[.baselineOffset] as? CGFloat) ?? 0
            isSuperscript = attrsOffset > 0.5
            isSubscript   = attrsOffset < -0.5
            if let c = attrs[.foregroundColor] as? NSColor { textColor = c }
            highlightColor = attrs[.backgroundColor] as? NSColor
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
                textAlignment = ps.alignment
                lineSpacingMultiple = ps.lineHeightMultiple > 0 ? ps.lineHeightMultiple : 1.0
                updateListState(from: ps)
            }
            currentStyleId = (attrs[.docxEditStyleId] as? String) ?? "Normal"
            currentCharStyleId = attrs[.docxEditCharStyleId] as? String
        }
        // Курсор в таблице? — читаем NSTextTableBlock из paragraphStyle позиции.
        isCaretInTable = tableSpanAtCaret() != nil
        if storage.length > 0 {
            let probe = min(max(0, textView.selectedRange().location), storage.length - 1)
            isCurrentRowHeader = (storage.attribute(.docxEditRowHeader, at: probe, effectiveRange: nil) as? Bool) ?? false
            // v0.1.90: источник истины — `.height` самого NSTextTableBlock (его пишет
            // и ресайз мышью, и appendTable). Кастомный ключ — фолбэк для случаев,
            // когда блок недоступен.
            var rowH: CGFloat? = nil
            if let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
               let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
               cb.valueType(for: .height) == .absoluteValueType, cb.value(for: .height) > 0 {
                rowH = cb.value(for: .height)
            } else {
                let raw = storage.attribute(.docxEditRowHeight, at: probe, effectiveRange: nil)
                if let v = raw as? CGFloat { rowH = v }
                else if let v = raw as? Double { rowH = CGFloat(v) }
                else if let v = raw as? NSNumber { rowH = CGFloat(truncating: v) }
            }
            currentRowHeight = rowH
        } else {
            isCurrentRowHeader = false
            currentRowHeight = nil
        }
        currentLanguageCode = detectLanguageAroundCaret()
        // v0.3.1: авто-переключение спелчек-языка на определённый язык абзаца.
        if AppPreferences.shared.autoDetectSpellLanguage,
           let lang = currentLanguageCode,
           lang != lastAppliedSpellLanguage,
           ["ru", "en"].contains(lang) {
            let bcp = lang == "ru" ? "ru_RU" : "en_US"
            setSpellCheckLanguage(bcp)
            lastAppliedSpellLanguage = lang
        }
    }

    /// Обновляет published-состояние списка (тип + вариант галереи) по стилю абзаца
    /// и запоминает распознанный вариант как «последний» для будущих ⌘]/⌘[.
    private func updateListState(from ps: NSParagraphStyle) {
        let info = ParagraphAttributes.from(nsParagraphStyle: ps).listInfo
        currentListType = info?.listType
        if let info {
            let variant = detectVariant(for: info)
            if variant.format(at: info.level) == info.formatStyle {
                currentListVariantId = variant.id
                lastVariant[info.listType] = variant
            } else {
                currentListVariantId = nil
            }
        } else {
            currentListVariantId = nil
        }
    }

    func refreshStatus() {
        guard let session else { return }
        let stats = DocumentStatisticsCalculator.calculate(session.bridge.model)
        statusText = "Слов: \(stats.words) · Символов: \(stats.characters) · \(session.bridge.model.metadata.language)"
    }

    /// Уведомление от NSTextView: пользователь изменил текст.
    func userDidEdit(text: NSAttributedString) {
        session?.applyAttributed(text)
        textRevision &+= 1
        // v1.5.18: правка сдвигает позиции — снимаем подсветку поиска.
        if findHighlightsActive { clearFindHighlights() }
        refreshStatus()
        maybeAutoRefreshToc()
    }

    /// v0.5.6 (R07): если в документе есть TOC-блок и последняя правка задела
    /// заголовок (paragraph.styleId начинается на "Heading"), пересобираем
    /// оглавление. Дешёвая эвристика — проверяем СУЩЕСТВОВАНИЕ хоть одного
    /// TOC-блока в текущем storage; если нет — сразу выходим. При наличии
    /// сверяем список заголовков (`collectHeadings`) с последним снэпшотом;
    /// перерисовываем только при отличии — избегаем лишних правок при обычной
    /// печати в теле абзацев.
    private func maybeAutoRefreshToc() {
        guard !isRefreshingToc, let tv = textView, let storage = tv.textStorage else { return }
        var hasToc = false
        storage.enumerateAttribute(.docxEditTocBlock,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { val, _, stop in
            if val != nil { hasToc = true; stop.pointee = true }
        }
        guard hasToc else { return }
        let key = collectHeadings().map { "\($0.level)|\($0.text)" }.joined(separator: "\n")
        guard key != lastTocHeadingsSnapshot else { return }
        lastTocHeadingsSnapshot = key
        isRefreshingToc = true
        updateTableOfContents()
        isRefreshingToc = false
    }

}
