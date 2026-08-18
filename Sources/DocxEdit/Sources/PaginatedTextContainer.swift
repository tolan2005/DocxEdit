//
//  PaginatedTextContainer.swift
//  DocxEdit
//
//  Настоящая пагинация подходом №1 (см. DESIGN_pagination.md): ОДИН NSTextView и
//  ОДИН контейнер — выделение/форматирование остаются нативными (в отличие от
//  отклонённого мульти-NSTextView, который ломал выделение). Разрывы страниц
//  создаются переопределением `lineFragmentRect(forProposedRect:…)`: строку, которая
//  вышла бы за нижнюю границу содержимого текущего листа, «перепрыгиваем» на верх
//  содержимого следующего листа. Серые промежутки между листами остаются пустыми,
//  а `DocxTextView.drawBackground` рисует там отдельные белые листы A4 с тенью.
//
//  Координаты — в системе контейнера (textView − textContainerInset). Инсет по
//  вертикали = (зазор сверху + верхнее поле), поэтому container-Y=0 совпадает с
//  верхом содержимого первого листа, а верх содержимого листа i = i * pageStride.
//

import AppKit

final class PaginatedTextContainer: NSTextContainer {
    /// Включён ли режим постраничной раскладки.
    var paged = false
    /// Шаг между листами по вертикали в координатах контейнера = pageHeight + gap.
    var pageStride: CGFloat = 1
    /// Высота области содержимого одного листа = pageHeight − верхнее − нижнее поле.
    var pageContentHeight: CGFloat = 1

    override func lineFragmentRect(forProposedRect proposedRect: NSRect,
                                   at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var rect = super.lineFragmentRect(forProposedRect: proposedRect,
                                          at: characterIndex,
                                          writingDirection: baseWritingDirection,
                                          remaining: remainingRect)
        guard paged, pageStride > 1, pageContentHeight > 1, rect.height > 0 else { return rect }
        let page = floor(rect.minY / pageStride)
        // Разрыв страницы: если прямо перед этой строкой стоит U+000C — переносим
        // строку (и весь следующий текст) на верх содержимого следующего листа.
        if characterIndex > 0,
           let s = layoutManager?.textStorage?.string as NSString?,
           characterIndex <= s.length,
           s.character(at: characterIndex - 1) == 0x0C {
            rect.origin.y = (page + 1) * pageStride
            return rect
        }
        // Иначе — если строка не помещается на текущем листе, на следующий.
        let contentBottom = page * pageStride + pageContentHeight
        if rect.maxY > contentBottom + 0.5 {
            rect.origin.y = (page + 1) * pageStride
        }
        return rect
    }
}
