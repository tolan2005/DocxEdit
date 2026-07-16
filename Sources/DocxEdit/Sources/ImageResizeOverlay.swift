//
//  ImageResizeOverlay.swift
//  DocxEdit
//
//  Overlay-view с 4 угловыми ручками для ресайза выделенного inline-изображения
//  (v0.1.67, R03). Крепится как subview к NSTextView, позиционируется по glyph-rect
//  выделенного `NSTextAttachment`; тянешь угол — картинка меняет размер с
//  сохранением пропорций. Один шаг undo на весь жест (mouseDown → mouseUp).
//
//  Стратегия — отдельный NSView, а не override mouseDown у NSTextView, чтобы не
//  ломать штатное выделение текста.
//

import AppKit

final class ImageResizeOverlay: NSView {

    weak var textView: NSTextView?
    /// Range символа U+FFFC с `.attachment`, к которому привязан overlay.
    private(set) var attachmentRange: NSRange = NSRange(location: NSNotFound, length: 0)

    private let handleSize: CGFloat = 8
    private let borderInset: CGFloat = 1

    private var resizingCorner: Corner?
    private var startBounds: NSRect = .zero
    private var startMouse: NSPoint = .zero
    private var aspectRatio: CGFloat = 1

    private enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Устанавливает range attachment и обновляет frame по его glyph-rect.
    /// Возвращает false, если рендер ещё не готов (glyph-rect zero) — тогда
    /// вызывающий должен убрать overlay из иерархии.
    @discardableResult
    func attach(to range: NSRange) -> Bool {
        attachmentRange = range
        return updateFrameFromGlyphRect()
    }

    /// Пересчитывает frame overlay по текущей позиции attachment в textView.
    /// Вызывается на textDidChange (правки могли сместить attachment).
    @discardableResult
    func updateFrameFromGlyphRect() -> Bool {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let container = tv.textContainer,
              attachmentRange.location != NSNotFound,
              attachmentRange.location + attachmentRange.length <= (tv.textStorage?.length ?? 0)
        else { return false }
        let glyphRange = lm.glyphRange(forCharacterRange: attachmentRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return false }
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
        // boundingRect — в textContainer-координатах. NSTextView textContainerOrigin
        // сдвигает на padding и textContainerInset.
        let origin = tv.textContainerOrigin
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)
        // Небольшое расширение под ручки/рамку.
        let inset: CGFloat = handleSize / 2 + borderInset
        rect = rect.insetBy(dx: -inset, dy: -inset)
        if rect.width < handleSize * 2 || rect.height < handleSize * 2 { return false }
        frame = rect
        needsDisplay = true
        return true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Рамка вокруг изображения.
        let contentRect = bounds.insetBy(dx: handleSize / 2, dy: handleSize / 2)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: contentRect)
        path.lineWidth = 1
        path.stroke()

        // Четыре угловые ручки.
        NSColor.controlAccentColor.setFill()
        NSColor.white.setStroke()
        for r in cornerRects() {
            let hp = NSBezierPath(ovalIn: r)
            hp.fill()
            hp.lineWidth = 1
            hp.stroke()
        }
    }

    private func cornerRects() -> [NSRect] {
        let s = handleSize
        return [
            NSRect(x: 0, y: 0, width: s, height: s),                            // tl
            NSRect(x: bounds.width - s, y: 0, width: s, height: s),             // tr
            NSRect(x: 0, y: bounds.height - s, width: s, height: s),            // bl
            NSRect(x: bounds.width - s, y: bounds.height - s, width: s, height: s), // br
        ]
    }

    private func cornerAt(point p: NSPoint) -> Corner? {
        let r = cornerRects()
        if r[0].contains(p) { return .topLeft }
        if r[1].contains(p) { return .topRight }
        if r[2].contains(p) { return .bottomLeft }
        if r[3].contains(p) { return .bottomRight }
        return nil
    }

    // MARK: Hit-testing — принимаем только клики по ручкам; всё остальное
    // (в т.ч. клик по центру изображения) пропускаем к textView под нами.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point приходит в координатах суперпредставления; конвертируем к своим.
        let local = convert(point, from: superview)
        return cornerAt(point: local) != nil ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for r in cornerRects() {
            addCursorRect(r, cursor: .crosshair)
        }
    }

    // MARK: - Ресайз

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let corner = cornerAt(point: local),
              let tv = textView,
              let storage = tv.textStorage,
              attachmentRange.location + attachmentRange.length <= storage.length,
              let att = storage.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? NSTextAttachment
        else { return }
        resizingCorner = corner
        startBounds = att.bounds
        startMouse = event.locationInWindow
        aspectRatio = startBounds.height > 0 ? startBounds.width / startBounds.height : 1
    }

    override func mouseDragged(with event: NSEvent) {
        guard let corner = resizingCorner,
              let tv = textView,
              let storage = tv.textStorage,
              attachmentRange.location + attachmentRange.length <= storage.length,
              let att = storage.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? NSTextAttachment
        else { return }
        let dx = event.locationInWindow.x - startMouse.x
        let dy = event.locationInWindow.y - startMouse.y
        // Знак дельты: правый край растёт по +x, левый — по -x; аналогично y (isFlipped).
        // Y в textView не flipped: перевернём знак.
        let signedDW: CGFloat
        switch corner {
        case .topRight, .bottomRight: signedDW = dx
        case .topLeft, .bottomLeft:   signedDW = -dx
        }
        let signedDH: CGFloat
        switch corner {
        // Внутри textView isFlipped=true, но mouseLocation в window-coords не flipped:
        // потащили вниз → dy<0 → нужен рост высоты для нижних углов, сжатие для верхних.
        case .bottomLeft, .bottomRight: signedDH = -dy
        case .topLeft, .topRight:       signedDH = dy
        }
        // Пропорциональный ресайз: доминирующая ось определяет диагональ.
        var newW = max(20, startBounds.width + signedDW)
        var newH = max(20, startBounds.height + signedDH)
        if abs(signedDW) > abs(signedDH) {
            newH = max(20, newW / aspectRatio)
        } else {
            newW = max(20, newH * aspectRatio)
        }
        att.bounds = NSRect(x: 0, y: 0, width: newW, height: newH)
        // Инвалидируем layout вокруг символа, чтобы NSLayoutManager перерисовал глиф.
        if let lm = tv.layoutManager {
            lm.invalidateLayout(forCharacterRange: attachmentRange, actualCharacterRange: nil)
            lm.invalidateDisplay(forCharacterRange: attachmentRange)
        }
        updateFrameFromGlyphRect()
    }

    override func mouseUp(with event: NSEvent) {
        guard resizingCorner != nil,
              let tv = textView,
              let storage = tv.textStorage,
              attachmentRange.location + attachmentRange.length <= storage.length,
              let att = storage.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? NSTextAttachment
        else { resizingCorner = nil; return }
        resizingCorner = nil
        // Живой драг менял att.bounds напрямую (без undo). Регистрируем ОДИН шаг undo:
        // (1) откатываем bounds в стартовое; (2) делаем один replaceCharacters
        // (тот же символ + новые атрибуты — attachment) под shouldChangeText/didChangeText.
        let finalBounds = att.bounds
        att.bounds = startBounds
        // Пересобираем attributed для одного символа с обновлённым attachment.
        let attrs = storage.attributes(at: attachmentRange.location, effectiveRange: nil)
        let newAtt = NSTextAttachment()
        newAtt.image = att.image
        newAtt.bounds = finalBounds
        var newAttrs = attrs
        newAttrs[.attachment] = newAtt
        let piece = NSAttributedString(string: "\u{FFFC}", attributes: newAttrs)
        guard tv.shouldChangeText(in: attachmentRange, replacementString: piece.string) else {
            // Восстановим финальный размер даже если undo-шаг не удался.
            att.bounds = finalBounds
            return
        }
        storage.beginEditing()
        storage.replaceCharacters(in: attachmentRange, with: piece)
        storage.endEditing()
        tv.didChangeText()
        // После replaceCharacters attachment новый — перепривязываемся:
        updateFrameFromGlyphRect()
    }
}
