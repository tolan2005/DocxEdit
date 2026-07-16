//
//  CharacterAttributes+Merger.swift
//  DocxCore
//
//  Утилиты для объединения CharacterAttributes и работы с ними.
//

import Foundation

public extension CharacterAttributes {

    /// Возвращает атрибуты, в которых сохранены все non-nil/non-default значения
    /// из `self` и `other` (other имеет приоритет).
    func merged(with other: CharacterAttributes) -> CharacterAttributes {
        CharacterAttributes(
            fontName: other.fontName ?? self.fontName,
            fontSize: other.fontSize ?? self.fontSize,
            bold: other.bold || self.bold,
            italic: other.italic || self.italic,
            underline: other.underline != .none ? other.underline : self.underline,
            strikethrough: other.strikethrough || self.strikethrough,
            textColor: other.textColor ?? self.textColor,
            highlightColor: other.highlightColor ?? self.highlightColor,
            superscript: other.superscript || self.superscript,
            `subscript`: other.`subscript` || self.`subscript`,
            smallCaps: other.smallCaps || self.smallCaps,
            allCaps: other.allCaps || self.allCaps
        )
    }

    var isEmpty: Bool {
        fontName == nil && fontSize == nil && !bold && !italic && underline == .none
            && !strikethrough && textColor == nil && highlightColor == nil
            && !superscript && !`subscript` && !smallCaps && !allCaps
    }
}

public extension ParagraphAttributes {
    /// Возвращает копию с применёнными изменениями.
    func with(
        alignment: TextAlignment? = nil,
        lineSpacing: LineSpacing? = nil,
        spaceBefore: CGFloat? = nil,
        spaceAfter: CGFloat? = nil,
        leftIndent: CGFloat? = nil,
        rightIndent: CGFloat? = nil,
        firstLineIndent: CGFloat? = nil,
        hangingIndent: CGFloat? = nil,
        listInfo: ListInfo?? = nil,
        styleId: String? = nil
    ) -> ParagraphAttributes {
        ParagraphAttributes(
            alignment: alignment ?? self.alignment,
            lineSpacing: lineSpacing ?? self.lineSpacing,
            spaceBefore: spaceBefore ?? self.spaceBefore,
            spaceAfter: spaceAfter ?? self.spaceAfter,
            leftIndent: leftIndent ?? self.leftIndent,
            rightIndent: rightIndent ?? self.rightIndent,
            firstLineIndent: firstLineIndent ?? self.firstLineIndent,
            hangingIndent: hangingIndent ?? self.hangingIndent,
            listInfo: listInfo ?? self.listInfo,
            styleId: styleId ?? self.styleId
        )
    }
}

public extension DocumentModel {

    /// Текст всего документа одной строкой (для поиска/экспорта).
    var plainText: String {
        var result = ""
        for section in sections {
            for block in section.blocks {
                if case .paragraph(let p) = block {
                    for run in p.runs {
                        result += run.text
                    }
                    result += "\n"
                }
            }
        }
        return result
    }

    /// Количество всех параграфов в документе.
    var paragraphCount: Int {
        var count = 0
        for section in sections {
            for block in section.blocks {
                if case .paragraph = block {
                    count += 1
                }
            }
        }
        return count
    }
}
