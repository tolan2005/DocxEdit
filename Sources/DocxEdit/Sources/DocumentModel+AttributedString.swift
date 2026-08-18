//
//  DocumentModel+AttributedString.swift
//  DocxEdit
//
//  Мост между DocumentModel (DocxCore) и NSAttributedString (AppKit).
//  В R01: только CharacterAttributes; ParagraphAttributes упрощены.
//

import AppKit
import DocxCore

// MARK: - Custom-атрибут: id стиля абзаца

extension NSAttributedString.Key {
    /// Хранится на каждом символе абзаца — читается при обратном разборе, чтобы
    /// восстановить `ParagraphAttributes.styleId` без отдельного места хранения.
    static let docxEditStyleId = NSAttributedString.Key("docxEditStyleId")
    /// v1.5.5: границы абзаца (значение — `ParagraphBorder` из DocxCore).
    /// Рисуется DocxLayoutManager (TextKit 1 не имеет pBdr).
    static let docxEditParagraphBorder = NSAttributedString.Key("docxEditParagraphBorder")
    /// v1.5.6: инструкция сложного поля (String) на первом ране результата.
    static let docxEditFieldInstr = NSAttributedString.Key("docxEditFieldInstr")
    /// Хранится на символах, к которым применён символьный стиль (Strong/Emphasis/CodeChar).
    /// Читается при обратном разборе → `CharacterAttributes.styleId`.
    static let docxEditCharStyleId = NSAttributedString.Key("docxEditCharStyleId")
    /// Замещающий текст (alt-text) inline-изображения (v0.1.60). Хранится на U+FFFC-
    /// символе рядом с `.attachment` — `NSTextAttachment` не имеет поля для alt-text.
    static let docxEditImageAltText = NSAttributedString.Key("docxEditImageAltText")
    /// Горизонтальное выравнивание таблицы на странице (v0.1.72). Хранится на первом
    /// абзаце таблицы (raw value TableAlignment: "left"/"center"/"right").
    /// NSTextTable своего alignment API не имеет, поэтому используем кастомный ключ.
    static let docxEditTableAlignment = NSAttributedString.Key("docxEditTableAlignment")
    /// v0.1.85: строка-заголовок таблицы (Bool). Проставляется на всех символах ячеек
    /// строки при рендере, читается при обратном разборе.
    static let docxEditRowHeader = NSAttributedString.Key("docxEditRowHeader")
    /// v0.1.86: минимальная высота строки таблицы (CGFloat, pt).
    static let docxEditRowHeight = NSAttributedString.Key("docxEditRowHeight")
    /// v0.1.102: режим обтекания изображения (rawValue InlineImageWrap).
    /// Проставляется на U+FFFC вместе с `.attachment`.
    static let docxEditImageWrap = NSAttributedString.Key("docxEditImageWrap")
    /// v1.5.12: позиция плавающего якоря — строка "xEMU,yEMU,wEMU,hEMU" (Int, EMU
    /// от колонки/абзаца; размер — отображаемый). На U+FFFC рядом с
    /// `.attachment` (при wrap != .inline). Размер дублируется, потому что
    /// у плавающего аттачмента cell 1×1pt (реальный размер — у NSImageView).
    static let docxEditImageAnchor = NSAttributedString.Key("docxEditImageAnchor")
    /// v0.2.4: имя закладки (String) на диапазоне (или 0-длина в позиции курсора).
    /// DOCX round-trip: `<w:bookmarkStart w:name="…"/>` перед и `<w:bookmarkEnd/>` после.
    static let docxEditBookmark = NSAttributedString.Key("docxEditBookmark")
    /// v0.4.4 (R06): id треда комментария (`CommentThread.id`). Живёт на
    /// диапазоне текста в NSAttributedString; переживает пересборку модели
    /// `from(attributed:)`. Содержимое треда — в `DocumentModel.comments`.
    static let docxEditCommentId = NSAttributedString.Key("docxEditCommentId")
    /// v0.4.6 (R06): маркер вставки при включённом track-changes. Значение —
    /// строка вида "\(author)|\(iso-date)|\(revId)". Живёт на диапазоне.
    static let docxEditInsertion = NSAttributedString.Key("docxEditInsertion")
    /// v0.4.6 (R06): маркер удаления (текст остаётся в storage, но помечен —
    /// визуально strikethrough). Значение того же вида.
    static let docxEditDeletion = NSAttributedString.Key("docxEditDeletion")
    /// v0.5.3 (R07): id сноски на якорной позиции (superscript-маркер в тексте).
    /// Содержимое сноски — в `DocumentModel.footnotes[id]`.
    static let docxEditFootnoteId = NSAttributedString.Key("docxEditFootnoteId")
    /// v1.5.15: id концевой сноски. Содержимое — в `DocumentModel.endnotes[id]`.
    static let docxEditEndnoteId = NSAttributedString.Key("docxEditEndnoteId")
    /// v0.5.5 (R07): маркер блока оглавления. Значение = String с фиксированным
    /// id блока (пока поддерживается один TOC на документ, id = "toc"). Атрибут
    /// стоит на всех символах сгенерированных абзацев оглавления, чтобы можно
    /// было найти и заменить блок при обновлении.
    static let docxEditTocBlock = NSAttributedString.Key("docxEditTocBlock")
    /// v0.5.6 (R07): id закладки-цели для перекрёстной ссылки. Значение =
    /// имя закладки. При Cmd+клике по ссылке — прыжок к её позиции.
    static let docxEditCrossRef = NSAttributedString.Key("docxEditCrossRef")
    /// v0.5.8 (R08): track-changes ревизия атрибутов рана. Формат — "author|date|id".
    static let docxEditAttributeRevision = NSAttributedString.Key("docxEditAttributeRevision")
}

// MARK: - Inline-изображение через NSTextAttachment (v0.1.52, R03)

/// v1.5.15: римская запись номера концевой сноски ("3" → "iii"). Нечисловой
/// id возвращаем как есть.
func romanNumeral(for id: String) -> String {
    guard let n = Int(id), n > 0, n < 4000 else { return id }
    let table: [(Int, String)] = [(1000,"m"),(900,"cm"),(500,"d"),(400,"cd"),
                                  (100,"c"),(90,"xc"),(50,"l"),(40,"xl"),
                                  (10,"x"),(9,"ix"),(5,"v"),(4,"iv"),(1,"i")]
    var rest = n, out = ""
    for (v, s) in table { while rest >= v { out += s; rest -= v } }
    return out
}

/// Собирает `NSTextAttachment` из `InlineImage`. Размер вычисляется так:
/// если `displayWidth`/`displayHeight` заданы — используются они; иначе — натуральный
/// размер NSImage (clamp по ширине контейнера при рендере — на TextKit-слое).
func makeImageAttachment(from img: InlineImage) -> NSTextAttachment {
    let att = NSTextAttachment()
    if let ns = NSImage(data: img.data) {
        att.image = ns
        // v1.5.12: плавающая картинка (wrap != .inline) не занимает места
        // в тексте — рендерится отдельным NSImageView поверх/под текстом,
        // а текст обтекает через exclusionPaths. Ячейка-якорь — 1pt.
        if img.wrap != .inline {
            att.bounds = NSRect(x: 0, y: 0, width: 1, height: 1)
        } else {
            let w = img.displayWidth > 0 ? img.displayWidth : ns.size.width
            let h = img.displayHeight > 0 ? img.displayHeight : ns.size.height
            att.bounds = NSRect(x: 0, y: 0, width: w, height: h)
        }
    }
    return att
}

/// Извлекает `InlineImage` из `NSTextAttachment`. Возвращает nil, если у аттачмента
/// нет пригодного изображения. Формат подбирается по данным (первым делом пробуем PNG,
/// как безопасный fallback без потерь).
func inlineImage(from att: NSTextAttachment) -> InlineImage? {
    guard let image = att.image ?? att.attachmentCell?.attachment?.image else { return nil }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return InlineImage(
        format: .png,
        data: png,
        displayWidth: att.bounds.width,
        displayHeight: att.bounds.height
    )
}

/// Применяет символьный стиль к диапазону (bold/italic/шрифт), сохраняя цвет,
/// подчёркивание, зачёркивание и другие атрибуты неизменными.
func applyStandardCharacterStyle(_ style: StandardCharacterStyle,
                                 to storage: NSMutableAttributedString,
                                 range: NSRange) {
    guard range.length > 0 else { return }
    let mgr = NSFontManager.shared
    storage.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
        let old = (val as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        var f = old
        if let family = style.def.fontName {
            f = mgr.convert(f, toFamily: family)
        }
        if let size = style.def.fontSize {
            f = mgr.convert(f, toSize: size)
        }
        var traits = f.fontDescriptor.symbolicTraits
        if style.def.bold   { traits.insert(.bold) }
        if style.def.italic { traits.insert(.italic) }
        if let d = f.fontDescriptor.withSymbolicTraits(traits) as NSFontDescriptor? {
            f = NSFont(descriptor: d, size: f.pointSize) ?? f
        }
        storage.addAttribute(.font, value: f, range: subRange)
    }
    storage.addAttribute(.docxEditCharStyleId, value: style.id, range: range)
}

/// Снимает символьный стиль с диапазона: удаляет ключ `.docxEditCharStyleId`
/// (визуальные атрибуты остаются как есть — пользователь может их дополнительно
/// «сбросить» через «Очистить форматирование»).
func removeCharacterStyle(from storage: NSMutableAttributedString, range: NSRange) {
    guard range.length > 0 else { return }
    storage.removeAttribute(.docxEditCharStyleId, range: range)
}

/// Применяет визуальные атрибуты стандартного стиля (шрифт/размер/начертание/интервалы)
/// к диапазону абзаца. Оба параметра — `Normal` (basedOn база) и целевой стиль —
/// нужны, чтобы «Обычный» сбрасывал накопленные заголовочные атрибуты.
/// `fontFamily` — целевое семейство шрифта (nil = не менять семейство, оставить
/// как было; обычно вызывающий передаёт AppPreferences.defaultFontName для Normal
/// и AppPreferences.headingFontName ?? defaultFontName для заголовков).
extension DocxCore.TextAlignment {
    /// Конвертация в AppKit-выравнивание (для колонтитулов и пр.).
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left:    return .left
        case .center:  return .center
        case .right:   return .right
        case .justify: return .justified
        }
    }
}

func applyStandardStyle(_ style: StandardParagraphStyle,
                        base: StandardParagraphStyle = .normal,
                        fontFamily: String? = nil,
                        to storage: NSMutableAttributedString,
                        range: NSRange) {
    guard range.length > 0 else { return }
    // Character attrs — идём под-ранами, чтобы не терять цвета/подчёркивания.
    storage.enumerateAttribute(.font, in: range, options: []) { val, subRange, _ in
        let old = (val as? NSFont) ?? NSFont.systemFont(ofSize: base.def.fontSize ?? 12)
        let mgr = NSFontManager.shared
        // Целевые характеристики — сначала фолбэк на base (Normal), потом override стиля.
        let targetSize = style.def.fontSize ?? base.def.fontSize ?? old.pointSize
        let wantBold = style.def.bold ?? base.def.bold ?? false
        let wantItalic = style.def.italic ?? base.def.italic ?? false
        var f = mgr.convert(old, toSize: targetSize)
        // Семейство: если у самого стиля задано fontName — используем его; иначе
        // — переданное вызывающим fontFamily (обычно из настроек).
        let effectiveFamily = style.def.fontName ?? fontFamily
        if let family = effectiveFamily {
            f = mgr.convert(f, toFamily: family)
        }
        var traits = f.fontDescriptor.symbolicTraits
        if wantBold { traits.insert(.bold) } else { traits.remove(.bold) }
        if wantItalic { traits.insert(.italic) } else { traits.remove(.italic) }
        if let d = f.fontDescriptor.withSymbolicTraits(traits) as NSFontDescriptor? {
            f = NSFont(descriptor: d, size: targetSize) ?? f
        }
        storage.addAttribute(.font, value: f, range: subRange)
    }
    // Цвет текста стиля (если задан) — применяется поверх текущего.
    if let c = style.def.textColor {
        let nsc = NSColor(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        storage.addAttribute(.foregroundColor, value: nsc, range: range)
    }
    // Цвет фона (highlight). Если nil — снимаем предыдущий (иначе сброс стиля не
    // очистит заливку).
    if let bg = style.def.backgroundColor {
        let nsc = NSColor(calibratedRed: bg.red, green: bg.green, blue: bg.blue, alpha: bg.alpha)
        storage.addAttribute(.backgroundColor, value: nsc, range: range)
    } else {
        storage.removeAttribute(.backgroundColor, range: range)
    }
    // paragraphStyle — новый spacing.
    storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { val, subRange, _ in
        let ps = (val as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        if let sp = style.def.spaceBefore { ps.paragraphSpacingBefore = sp }
        if let sp = style.def.spaceAfter  { ps.paragraphSpacing = sp }
        if let al = style.def.alignment {
            switch al {
            case .left:    ps.alignment = .left
            case .center:  ps.alignment = .center
            case .right:   ps.alignment = .right
            case .justify: ps.alignment = .justified
            }
        }
        storage.addAttribute(.paragraphStyle, value: ps, range: subRange)
    }
    storage.addAttribute(.docxEditStyleId, value: style.id, range: range)
}

// MARK: - CharacterAttributes → [NSAttributedString.Key: Any]

extension CharacterAttributes {
    /// Преобразует атрибуты символа в словарь для NSAttributedString.
    /// `defaultFont` используется для подстановки недостающих параметров.
    /// `fallbackFontName` подставляется, если `fontName` указан, но отсутствует в системе
    /// (обычно — первый избранный шрифт из настроек).
    func nsAttributes(defaultFont: NSFont, fallbackFontName: String? = nil) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]

        // Шрифт.
        let baseSize = fontSize ?? defaultFont.pointSize
        var font: NSFont
        if let name = fontName {
            if let f = NSFont(name: name, size: baseSize) {
                font = f
            } else if let fbName = fallbackFontName, let f = NSFont(name: fbName, size: baseSize) {
                // Шрифт документа отсутствует в системе — подставляем избранный.
                font = f
            } else if let f = NSFont(descriptor: defaultFont.fontDescriptor, size: baseSize) {
                font = f
            } else {
                font = defaultFont
            }
        } else if let f = NSFont(descriptor: defaultFont.fontDescriptor, size: baseSize) {
            font = f
        } else {
            font = defaultFont
        }
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) as NSFontDescriptor? {
            font = NSFont(descriptor: descriptor, size: baseSize) ?? font
        }
        result[.font] = font

        // Цвет текста.
        // Пишем в sRGB (не calibratedRed) — иначе при чтении обратно через
        // usingColorSpace(.sRGB) значения дрейфуют (#FF0000 → #FF2600).
        if let color = textColor {
            result[.foregroundColor] = NSColor(
                srgbRed: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        } else {
            result[.foregroundColor] = NSColor.labelColor
        }

        // Подчёркивание. Раньше все варианты (double/dotted/dashed) писались как
        // .single — теряли стиль при round-trip. Теперь мапим на реальный
        // NSUnderlineStyle.
        switch underline {
        case .none:
            break
        case .single:
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case .double:
            result[.underlineStyle] = NSUnderlineStyle.double.rawValue
        case .dotted:
            result[.underlineStyle] = (NSUnderlineStyle.single.rawValue |
                                       NSUnderlineStyle.patternDot.rawValue)
        case .dashed:
            result[.underlineStyle] = (NSUnderlineStyle.single.rawValue |
                                       NSUnderlineStyle.patternDash.rawValue)
        }

        // Зачёркивание.
        if strikethrough {
            result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        // Цвет подсветки (highlight, v0.1.82).
        // sRGB (не calibrated) — иначе дрейф при round-trip (см. текст).
        if let hc = highlightColor {
            result[.backgroundColor] = NSColor(
                srgbRed: hc.red, green: hc.green, blue: hc.blue, alpha: hc.alpha
            )
        }

        // Над/подстрочный (v0.1.77): baselineOffset + уменьшенный шрифт (0.7×), как принято в текстовых редакторах.
        if superscript || `subscript` {
            let smallSize = baseSize * 0.7
            if let font = result[.font] as? NSFont {
                result[.font] = NSFontManager.shared.convert(font, toSize: smallSize)
            }
            result[.baselineOffset] = superscript ? baseSize * 0.35 : -baseSize * 0.2
        }

        return result
    }

    /// Извлекает CharacterAttributes из словаря NSAttributedString.
    static func from(
        nsAttributes attrs: [NSAttributedString.Key: Any],
        defaultFont: NSFont
    ) -> CharacterAttributes {
        var result = CharacterAttributes()

        if let font = attrs[.font] as? NSFont {
            result.fontSize = font.pointSize
            result.fontName = font.fontName
            let traits = font.fontDescriptor.symbolicTraits
            result.bold = traits.contains(.bold)
            result.italic = traits.contains(.italic)
        } else {
            result.fontSize = defaultFont.pointSize
        }

        if let color = attrs[.foregroundColor] as? NSColor {
            // Приведение к цветовому пространству sRGB для стабильности.
            let c = color.usingColorSpace(.sRGB) ?? color
            result.textColor = CodableColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        }

        if let raw = attrs[.underlineStyle] as? Int {
            let style = NSUnderlineStyle(rawValue: raw)
            if style.contains(.double) {
                result.underline = .double
            } else if style.contains(.patternDot) {
                result.underline = .dotted
            } else if style.contains(.patternDash) {
                result.underline = .dashed
            } else if style.contains(.single) {
                result.underline = .single
            }
        }

        if let raw = attrs[.strikethroughStyle] as? Int, NSUnderlineStyle(rawValue: raw).contains(.single) {
            result.strikethrough = true
        }

        if let bg = attrs[.backgroundColor] as? NSColor {
            let c = bg.usingColorSpace(.sRGB) ?? bg
            result.highlightColor = CodableColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        }

        if let csid = attrs[.docxEditCharStyleId] as? String {
            result.styleId = csid
        }

        // v0.1.77: над/подстрочный — по знаку baselineOffset.
        if let raw = attrs[.baselineOffset] as? CGFloat {
            if raw > 0.5 { result.superscript = true }
            else if raw < -0.5 { result.subscript = true }
        } else if let raw = attrs[.baselineOffset] as? Double {
            if raw > 0.5 { result.superscript = true }
            else if raw < -0.5 { result.subscript = true }
        }
        // При super/sub мост уменьшил fontSize в 0.7 раза — восстанавливаем «логический» размер,
        // чтобы модель хранила исходный (не «маленький») размер шрифта.
        if result.superscript || result.subscript, let sz = result.fontSize {
            result.fontSize = sz / 0.7
        }

        return result
    }
}

// MARK: - Списки: ListFormatStyle ↔ NSTextList.MarkerFormat

/// Шаг отступа на один уровень вложенности списка (как increaseIndent/decreaseIndent).
let listIndentStep: CGFloat = 36
/// Зазор между маркером (первая строка) и текстом (последующие строки при переносе).
private let listHangGap: CGFloat = 18

/// Отступы (head, firstLine) для заданного уровня вложенности списка (0-8).
func listIndent(forLevel level: Int) -> (head: CGFloat, firstLine: CGFloat) {
    let head = listIndentStep * CGFloat(level + 1)
    return (head, max(0, head - listHangGap))
}

/// Уровень вложенности, восстановленный из headIndent (обратный к listIndent(forLevel:)).
func listLevel(fromHeadIndent headIndent: CGFloat) -> Int {
    max(0, Int((headIndent / listIndentStep).rounded()) - 1)
}

func listMarkerFormat(for style: DocxCore.ListFormatStyle) -> NSTextList.MarkerFormat {
    switch style {
    case .bullet(let ch):        return NSTextList.MarkerFormat(rawValue: ch)
    case .decimal:                return NSTextList.MarkerFormat(rawValue: "{decimal}.")
    case .lowerLetter:            return NSTextList.MarkerFormat(rawValue: "{lower-alpha}.")
    case .upperLetter:            return NSTextList.MarkerFormat(rawValue: "{upper-alpha}.")
    case .lowerRoman:             return NSTextList.MarkerFormat(rawValue: "{lower-roman}.")
    case .upperRoman:             return NSTextList.MarkerFormat(rawValue: "{upper-roman}.")
    case .decimalEnclosedParen:   return NSTextList.MarkerFormat(rawValue: "{decimal})")
    case .lowerLetterParen:       return NSTextList.MarkerFormat(rawValue: "{lower-alpha})")
    case .lowerRomanParen:        return NSTextList.MarkerFormat(rawValue: "{lower-roman})")
    case .decimalNested:          return NSTextList.MarkerFormat(rawValue: "{decimal-nested}.")
    }
}

/// Обратное преобразование: по markerFormat восстанавливает ListFormatStyle.
/// `literalCharacter` — маркер буллита, если формат не шаблонный (bullet character).
func listFormatStyle(from markerFormat: NSTextList.MarkerFormat) -> DocxCore.ListFormatStyle {
    let raw = markerFormat.rawValue
    switch raw {
    case "{decimal}.":      return .decimal
    case "{lower-alpha}.":  return .lowerLetter
    case "{upper-alpha}.":  return .upperLetter
    case "{lower-roman}.":  return .lowerRoman
    case "{upper-roman}.":  return .upperRoman
    case "{decimal})":      return .decimalEnclosedParen
    case "{lower-alpha})":  return .lowerLetterParen
    case "{lower-roman})":  return .lowerRomanParen
    case "{decimal-nested}.": return .decimalNested
    default:                return .bullet(character: raw)
    }
}

/// Буквальный текст маркера для вставки в содержимое ("• ", "1. ", "a. ", "1.2.1. "…).
/// `counters` — стек счётчиков по уровням (индекс = уровень), последний элемент —
/// номер текущего элемента; составной формат (.decimalNested) использует весь стек.
func listMarkerText(for style: DocxCore.ListFormatStyle, counters: [Int]) -> String {
    let itemNumber = counters.last ?? 1
    switch style {
    case .bullet(let ch):       return "\(ch) "
    case .decimal:               return "\(itemNumber). "
    case .lowerLetter:           return "\(listLetterSequence(itemNumber, upper: false)). "
    case .upperLetter:           return "\(listLetterSequence(itemNumber, upper: true)). "
    case .lowerRoman:            return "\(listRomanNumeral(itemNumber).lowercased()). "
    case .upperRoman:            return "\(listRomanNumeral(itemNumber)). "
    case .decimalEnclosedParen:  return "\(itemNumber)) "
    case .lowerLetterParen:      return "\(listLetterSequence(itemNumber, upper: false))) "
    case .lowerRomanParen:       return "\(listRomanNumeral(itemNumber).lowercased())) "
    case .decimalNested:         return counters.map(String.init).joined(separator: ".") + ". "
    }
}

/// Длина префикса `text`, если он соответствует маркеру формата `style` (для распознавания
/// при обратном разборе NSAttributedString → DocumentModel). Возвращает nil, если не похоже.
func listMarkerPrefixLength(in text: String, for style: DocxCore.ListFormatStyle) -> Int? {
    switch style {
    case .bullet(let ch):
        let prefix = "\(ch) "
        return text.hasPrefix(prefix) ? prefix.count : nil
    case .decimalNested:
        // Составной номер: (цифры ".")+ пробел, например "1.2.10. ".
        var idx = text.startIndex
        var groups = 0
        while idx < text.endIndex {
            var digits = 0
            while idx < text.endIndex, text[idx].isNumber { digits += 1; idx = text.index(after: idx) }
            guard digits > 0, idx < text.endIndex, text[idx] == "." else { break }
            groups += 1
            idx = text.index(after: idx)
            if idx < text.endIndex, text[idx] == " " {
                return groups > 0 ? text.distance(from: text.startIndex, to: idx) + 1 : nil
            }
        }
        return nil
    case .decimal, .lowerLetter, .upperLetter, .lowerRoman, .upperRoman,
         .decimalEnclosedParen, .lowerLetterParen, .lowerRomanParen:
        guard let sepIndex = text.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let afterSep = text.index(after: sepIndex)
        guard afterSep < text.endIndex, text[afterSep] == " " else { return nil }
        let candidate = text[text.startIndex..<sepIndex]
        guard !candidate.isEmpty, candidate.count <= 6 else { return nil }
        return text.distance(from: text.startIndex, to: afterSep) + 1
    }
}

/// Иерархический счётчик элементов списка по уровням: вложенный уровень начинается
/// с 1 и сбрасывается, когда родительский элемент получает следующий номер;
/// родительская нумерация продолжается после вложенного подсписка.
struct ListCounters {
    private var counts: [Int] = []
    private var formats: [DocxCore.ListFormatStyle?] = []

    /// Разрыв последовательности (обычный абзац между списками) — полный сброс.
    mutating func breakSequence() {
        counts = []
        formats = []
    }

    /// Следующий элемент на уровне `level` формата `format`; возвращает стек
    /// счётчиков уровней 0...level для генерации маркера.
    /// v1.5.16: `start` (w:start/startOverride из DOCX) — если последовательность
    /// уровня пуста (или формат сменился и она сброшена), начинаем с него.
    mutating func next(level: Int, format: DocxCore.ListFormatStyle, start: Int? = nil) -> [Int] {
        let lvl = max(0, min(level, 8))
        if counts.count <= lvl {
            counts += Array(repeating: 0, count: lvl + 1 - counts.count)
            formats += Array(repeating: nil, count: lvl + 1 - formats.count)
        }
        // Смена формата на том же уровне — новая последовательность этого уровня.
        if let prev = formats[lvl], prev != format { counts[lvl] = 0 }
        // Стартовое значение: применяется к свежей (нулевой) последовательности.
        if counts[lvl] == 0, let start, start > 0 { counts[lvl] = start - 1 }
        counts[lvl] += 1
        formats[lvl] = format
        // Более глубокие уровни начнут нумерацию заново под новым родителем.
        if counts.count > lvl + 1 {
            counts.removeSubrange((lvl + 1)...)
            formats.removeSubrange((lvl + 1)...)
        }
        // Пропущенные родительские уровни (список начался сразу с вложенного) — минимум 1.
        return counts[0...lvl].map { max(1, $0) }
    }
}

private func listLetterSequence(_ number: Int, upper: Bool) -> String {
    var n = number
    var s = ""
    while n > 0 {
        n -= 1
        let letter = Character(UnicodeScalar(97 + (n % 26))!)
        s = String(letter) + s
        n /= 26
    }
    return upper ? s.uppercased() : s
}

private func listRomanNumeral(_ number: Int) -> String {
    let values: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
        (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]
    var n = number
    var result = ""
    for (value, symbol) in values {
        while n >= value {
            result += symbol
            n -= value
        }
    }
    return result.isEmpty ? "I" : result
}

// MARK: - ParagraphAttributes → NSParagraphStyle  (Fix #2)

extension ParagraphAttributes {
    func makeNSParagraphStyle() -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        switch alignment {
        case .left:    ps.alignment = .left
        case .center:  ps.alignment = .center
        case .right:   ps.alignment = .right
        case .justify: ps.alignment = .justified
        }
        if let li = listInfo {
            let (head, firstLine) = listIndent(forLevel: li.level)
            ps.headIndent = head
            ps.firstLineHeadIndent = firstLine
            ps.textLists = [NSTextList(markerFormat: listMarkerFormat(for: li.formatStyle), options: 0)]
        } else {
            // Hanging: первая строка «пуляется» левее (firstLineHeadIndent < headIndent).
            // FirstLine: первая строка сдвинута правее относительно leftIndent.
            // Оба вместе не поддерживаются моделью — предпочтение hangingIndent.
            if hangingIndent > 0 {
                ps.headIndent          = leftIndent
                ps.firstLineHeadIndent = max(0, leftIndent - hangingIndent)
            } else {
                ps.firstLineHeadIndent = leftIndent + firstLineIndent
                ps.headIndent          = leftIndent
            }
        }
        ps.tailIndent          = rightIndent == 0 ? 0 : -rightIndent
        ps.paragraphSpacingBefore = spaceBefore
        ps.paragraphSpacing       = spaceAfter
        // v1.5.4: пользовательские таб-стопы.
        if !tabStops.isEmpty {
            ps.tabStops = tabStops.map { t in
                let align: NSTextAlignment = {
                    switch t.alignment {
                    case .center: return .center
                    case .right:  return .right
                    default:      return .left
                    }
                }()
                return NSTextTab(textAlignment: align, location: t.position)
            }
        }
        switch lineSpacing {
        case .single:       ps.lineHeightMultiple = 1.0
        case .onePoint15:   ps.lineHeightMultiple = 1.15
        case .onePoint5:    ps.lineHeightMultiple = 1.5
        case .double:       ps.lineHeightMultiple = 2.0
        case .multiple(let v): ps.lineHeightMultiple = v
        case .exact(let v): ps.minimumLineHeight = v; ps.maximumLineHeight = v
        case .atLeast(let v): ps.minimumLineHeight = v
        }
        return ps
    }

    /// Извлекает атрибуты абзаца обратно из `NSParagraphStyle` (для сохранения в модель).
    /// Обратная к `makeNSParagraphStyle()`.
    static func from(nsParagraphStyle ps: NSParagraphStyle) -> ParagraphAttributes {
        var attrs = ParagraphAttributes()
        switch ps.alignment {
        case .center:    attrs.alignment = .center
        case .right:     attrs.alignment = .right
        case .justified: attrs.alignment = .justify
        default:         attrs.alignment = .left
        }
        attrs.rightIndent     = ps.tailIndent == 0 ? 0 : -ps.tailIndent
        attrs.spaceBefore     = ps.paragraphSpacingBefore
        attrs.spaceAfter      = ps.paragraphSpacing
        // v1.5.4: таб-стопы обратно в модель. Только ПОЛЬЗОВАТЕЛЬСКИЕ —
        // дефолтный NSParagraphStyle возвращает 12 левых стопов через 28pt,
        // их записывать в модель нельзя (иначе писались бы в каждый абзац).
        if ps.tabStops != NSParagraphStyle.default.tabStops {
            attrs.tabStops = ps.tabStops.map { tab in
                let align: TextAlignment = {
                    switch tab.alignment {
                    case .center: return .center
                    case .right:  return .right
                    default:      return .left
                    }
                }()
                return TabStop(position: tab.location, alignment: align)
            }
        }
        if ps.maximumLineHeight > 0, ps.maximumLineHeight == ps.minimumLineHeight {
            attrs.lineSpacing = .exact(ps.maximumLineHeight)
        } else if ps.minimumLineHeight > 0, ps.lineHeightMultiple == 0 {
            attrs.lineSpacing = .atLeast(ps.minimumLineHeight)
        } else if ps.lineHeightMultiple > 0 {
            attrs.lineSpacing = .multiple(ps.lineHeightMultiple)
        } else {
            attrs.lineSpacing = .single
        }
        if let list = ps.textLists.first {
            let style = listFormatStyle(from: list.markerFormat)
            let level = listLevel(fromHeadIndent: ps.headIndent)
            let type: ListType
            if case .bullet = style { type = .bulleted } else { type = .numbered }
            attrs.listInfo = ListInfo(listType: type, level: level, continuation: .continue, formatStyle: style)
            attrs.firstLineIndent = 0
            attrs.leftIndent = 0
        } else {
            attrs.leftIndent = ps.headIndent
            let fl = ps.firstLineHeadIndent
            let head = ps.headIndent
            if fl < head {
                // Hanging: первая строка левее continuation.
                attrs.hangingIndent = head - fl
                attrs.firstLineIndent = 0
            } else {
                attrs.firstLineIndent = fl - head
                attrs.hangingIndent = 0
            }
        }
        return attrs
    }
}

// MARK: - DocumentModel → NSAttributedString

extension DocumentModel {
    /// Собирает NSAttributedString из всех runs всех параграфов.
    /// Параграфы разделяются символом `\n` (как в NSTextView).
    /// `fallbackFontName` — избранный шрифт для подстановки, если шрифт документа не установлен в системе.
    func toAttributedString(
        defaultFont: NSFont = NSFont.systemFont(ofSize: 12),
        fallbackFontName: String? = nil,
        usableWidth: CGFloat = 0
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: NSColor.labelColor,
        ]
        var isFirstParagraph = true
        // Иерархическая нумерация маркеров списка по уровням; сбрасывается
        // при разрыве последовательности (не-списочный абзац между элементами).
        var listCounters = ListCounters()

        for section in sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p):
                    if !isFirstParagraph {
                        result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                    }
                    isFirstParagraph = false
                    let paraStyle = p.attributes.makeNSParagraphStyle()

                    if let li = p.attributes.listInfo {
                        let counters = listCounters.next(level: li.level, format: li.formatStyle, start: li.start)
                        let markerText = listMarkerText(for: li.formatStyle, counters: counters)
                        var markerAttrs = defaultAttrs
                        markerAttrs[.paragraphStyle] = paraStyle
                        if let firstRunFont = p.runs.first?.attributes.fontName,
                           let f = NSFont(name: firstRunFont, size: p.runs.first?.attributes.fontSize ?? defaultFont.pointSize) {
                            markerAttrs[.font] = f
                        }
                        result.append(NSAttributedString(string: markerText, attributes: markerAttrs))
                    } else {
                        listCounters.breakSequence()
                    }

                    if p.runs.isEmpty {
                        // Пустой абзац — добавляем пустую строку с параграф-стилем.
                        var attrs = defaultAttrs
                        attrs[.paragraphStyle] = paraStyle
                        if let sid = p.attributes.styleId { attrs[.docxEditStyleId] = sid }
                        if let b = p.attributes.border, !b.isEmpty { attrs[.docxEditParagraphBorder] = b }
                        // v1.4.2 (ADR-049): горизонтальная линия — пустой абзац
                        // не несёт ни одного символа, атрибуту styleId не на чём
                        // «висеть» (пропадал при from(attributed:)), да и высоты
                        // строки нет. Рендерим пробел-носитель; линию рисует
                        // DocxLayoutManager. При обратном разборе пробел попадёт
                        // в runs HR-абзаца — экспорт MD их игнорирует.
                        let carrier = p.attributes.styleId == "HorizontalRule" ? " " : ""
                        result.append(NSAttributedString(string: carrier, attributes: attrs))
                    }
                    for run in p.runs {
                        // Inline-изображение — через NSTextAttachment (v0.1.52).
                        if let img = run.image {
                            var attrs = run.attributes.nsAttributes(defaultFont: defaultFont, fallbackFontName: fallbackFontName)
                            attrs[.paragraphStyle] = paraStyle
                            if let sid = p.attributes.styleId { attrs[.docxEditStyleId] = sid }
                            if let b = p.attributes.border, !b.isEmpty { attrs[.docxEditParagraphBorder] = b }
                            if let url = run.hyperlink { attrs[.link] = url }
                            if let cid = run.commentId { attrs[.docxEditCommentId] = cid }
                            if let alt = img.altText, !alt.isEmpty {
                                attrs[.docxEditImageAltText] = alt
                            }
                            if img.wrap != .inline {
                                attrs[.docxEditImageWrap] = img.wrap.rawValue
                                // v1.5.12: позиция плавающего якоря + размеры (EMU).
                                if img.anchorXEMU != nil || img.anchorYEMU != nil {
                                    let wEmu = Int(img.displayWidth * 12700)
                                    let hEmu = Int(img.displayHeight * 12700)
                                    attrs[.docxEditImageAnchor] = "\(img.anchorXEMU ?? 0),\(img.anchorYEMU ?? 0),\(wEmu),\(hEmu)"
                                }
                            }
                            let att = makeImageAttachment(from: img)
                            let attStr = NSAttributedString(attachment: att)
                            let m = NSMutableAttributedString(attributedString: attStr)
                            m.addAttributes(attrs, range: NSRange(location: 0, length: m.length))
                            result.append(m)
                            continue
                        }
                        // v0.5.3 (R07): якорь сноски — ран с footnoteId (обычно
                        // пустой text). Рендерим как superscript-номер (id как есть),
                        // помечаем custom-ключом для обратного разбора.
                        if let fid = run.footnoteId {
                            var attrs = run.attributes.nsAttributes(defaultFont: defaultFont, fallbackFontName: fallbackFontName)
                            attrs[.paragraphStyle] = paraStyle
                            attrs[.docxEditFootnoteId] = fid
                            // Уменьшаем шрифт до 0.7× + baselineOffset — как super/subscript.
                            if let f = attrs[.font] as? NSFont {
                                attrs[.font] = NSFontManager.shared.convert(f, toSize: f.pointSize * 0.7)
                                attrs[.baselineOffset] = f.pointSize * 0.35
                            }
                            let markerText = run.text.isEmpty ? fid : run.text
                            result.append(NSAttributedString(string: markerText, attributes: attrs))
                            continue
                        }
                        // v1.5.15: якорь концевой сноски — superscript римскими
                        // (конвенция Word для endnotes), маркер по id.
                        if let eid = run.endnoteId {
                            var attrs = run.attributes.nsAttributes(defaultFont: defaultFont, fallbackFontName: fallbackFontName)
                            attrs[.paragraphStyle] = paraStyle
                            attrs[.docxEditEndnoteId] = eid
                            if let f = attrs[.font] as? NSFont {
                                attrs[.font] = NSFontManager.shared.convert(f, toSize: f.pointSize * 0.7)
                                attrs[.baselineOffset] = f.pointSize * 0.35
                            }
                            let markerText = run.text.isEmpty ? romanNumeral(for: eid) : run.text
                            result.append(NSAttributedString(string: markerText, attributes: attrs))
                            continue
                        }
                        if run.text.isEmpty { continue }
                        var attrs = run.attributes.nsAttributes(defaultFont: defaultFont, fallbackFontName: fallbackFontName)
                        attrs[.paragraphStyle] = paraStyle
                        if let sid = p.attributes.styleId { attrs[.docxEditStyleId] = sid }
                        if let b = p.attributes.border, !b.isEmpty { attrs[.docxEditParagraphBorder] = b }
                        if let csid = run.attributes.styleId { attrs[.docxEditCharStyleId] = csid }
                        if let fi = run.fieldInstr { attrs[.docxEditFieldInstr] = fi }
                        if let cid = run.commentId { attrs[.docxEditCommentId] = cid }
                        if let ins = run.insertion {
                            attrs[.docxEditInsertion] = ins
                            attrs[.foregroundColor] = NSColor.systemGreen
                        }
                        if let del = run.deletion {
                            attrs[.docxEditDeletion] = del
                            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                            attrs[.strikethroughColor] = NSColor.systemRed
                        }
                        if let url = run.hyperlink {
                            attrs[.link] = url
                            // Визуальные атрибуты гиперссылки применяются NSTextView
                            // автоматически через linkTextAttributes (см. TextEditorRepresentable);
                            // не выставляем цвет/underline здесь, чтобы не «запекать» их в модель.
                        }
                        // v0.5.5 (R07): перекрёстная ссылка — синий текст с
                        // подчёркиванием + custom-ключ (не .link, чтобы не путать
                        // с гиперссылкой в браузер и не открывать по клику).
                        if let bkm = run.crossRef {
                            attrs[.docxEditCrossRef] = bkm
                            attrs[.foregroundColor] = NSColor.systemBlue
                            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        }
                        // v0.5.6 (R07): TOC-блок — переживёт round-trip через SDT.
                        if let toc = run.tocBlock {
                            attrs[.docxEditTocBlock] = toc
                        }
                        // v0.5.8 (R08): track-changes ревизия атрибутов — только
                        // custom-ключ, без визуальных изменений (в редакторе
                        // выглядит как обычный ран).
                        if let rev = run.attributeRevision {
                            attrs[.docxEditAttributeRevision] = rev
                        }
                        result.append(NSAttributedString(string: run.text, attributes: attrs))
                    }
                case .table(let t):
                    if !isFirstParagraph {
                        result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                    }
                    isFirstParagraph = false
                    listCounters.breakSequence()
                    appendTable(t, to: result, defaultFont: defaultFont,
                                fallbackFontName: fallbackFontName,
                                usableWidth: usableWidth)
                }
            }
        }

        // Если результат пуст, добавляем пустой параграф.
        if result.length == 0 {
            result.append(NSAttributedString(string: "", attributes: defaultAttrs))
        }

        return result
    }

    /// Собирает DocumentModel из NSAttributedString.
    /// Идём поабзацно (по `paragraphRange`): для каждого абзаца извлекаем стиль
    /// абзаца (`NSParagraphStyle` → `ParagraphAttributes`) и runs внутри него.
    /// Абзацы с `NSTextTableBlock` в `paragraphStyle.textBlocks` группируются
    /// в `.table` блоки (R03, v0.1.49); последовательные абзацы с общим
    /// `NSTextTable` образуют одну таблицу, ячейки — по (startingRow, startingColumn).
    static func from(
        attributed: NSAttributedString,
        defaultFont: NSFont = NSFont.systemFont(ofSize: 12)
    ) -> DocumentModel {
        let ns = attributed.string as NSString
        let length = attributed.length
        var blocks: [Block] = []

        // Атрибуты абзаца из стиля первого символа абзаца.
        func paragraphAttrs(at loc: Int) -> ParagraphAttributes {
            guard length > 0, loc < length else { return ParagraphAttributes() }
            var attrs = ParagraphAttributes()
            if let ps = attributed.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle {
                attrs = ParagraphAttributes.from(nsParagraphStyle: ps)
            }
            if let sid = attributed.attribute(.docxEditStyleId, at: loc, effectiveRange: nil) as? String {
                attrs.styleId = sid
            }
            // v1.5.5: границы абзаца обратно в модель.
            if let b = attributed.attribute(.docxEditParagraphBorder, at: loc, effectiveRange: nil) as? ParagraphBorder {
                attrs.border = b
            }
            return attrs
        }

        // Ячейка в буфере: (row, col, rowSpan, colSpan, bg, width, накопленные абзацы, header-row флаг).
        struct CellBuffer {
            var row: Int
            var col: Int
            var rowSpan: Int
            var colSpan: Int
            var bg: NSColor?
            var width: CGFloat?
            var paras: [Paragraph]
            var isHeaderRow: Bool = false
            var rowHeight: CGFloat? = nil
        }
        var pendingTable: (nsTable: NSTextTable, cells: [CellBuffer], alignment: TableAlignment)?

        func flushTable() {
            guard let t = pendingTable else { return }
            let maxRow = t.cells.map { $0.row + $0.rowSpan }.max() ?? 0
            var rows: [TableRow] = []
            for r in 0..<maxRow {
                let cellsInRow = t.cells.filter { $0.row == r }.sorted { $0.col < $1.col }
                let cells: [TableCell] = cellsInRow.map { c in
                    let cellBlocks: [Block] = c.paras.isEmpty
                        ? [.paragraph(Paragraph(runs: [Run(text: "", attributes: CharacterAttributes())], attributes: ParagraphAttributes()))]
                        : c.paras.map { .paragraph($0) }
                    let bgCC = c.bg.map { color -> CodableColor in
                        let cc = color.usingColorSpace(.sRGB) ?? color
                        return CodableColor(red: cc.redComponent, green: cc.greenComponent,
                                             blue: cc.blueComponent, alpha: cc.alphaComponent)
                    }
                    return TableCell(blocks: cellBlocks,
                                     colSpan: max(1, c.colSpan), rowSpan: max(1, c.rowSpan),
                                     width: c.width,
                                     backgroundColor: bgCC)
                }
                let isHeader = cellsInRow.first?.isHeaderRow ?? false
                let rowH = cellsInRow.first?.rowHeight
                rows.append(TableRow(cells: cells, height: rowH, isHeader: isHeader))
            }
            // Восстанавливаем columnWidths из первой строки — по одному значению на grid-колонку.
            var columnWidths: [CGFloat] = []
            if let firstRow = rows.first {
                for cell in firstRow.cells {
                    let span = max(1, cell.colSpan)
                    let per = cell.width.map { $0 / CGFloat(span) } ?? 0
                    for _ in 0..<span { columnWidths.append(per) }
                }
            }
            if !rows.isEmpty {
                blocks.append(.table(TableBlock(
                    rows: rows,
                    columnWidths: columnWidths,
                    alignment: t.alignment)))
            }
            pendingTable = nil
        }

        func buildParagraph(contentRange initialRange: NSRange, pAttrs: ParagraphAttributes) -> Paragraph {
            var contentRange = initialRange
            // Абзац из списка — распознаём и отбрасываем буквальный текст маркера
            // ("• ", "1. "…), вставленный при рендере, чтобы он не попал в содержимое.
            if let li = pAttrs.listInfo, contentRange.length > 0 {
                let content = ns.substring(with: contentRange)
                if let markerLen = listMarkerPrefixLength(in: content, for: li.formatStyle) {
                    contentRange.location += markerLen
                    contentRange.length -= markerLen
                }
            }
            var runs: [Run] = []
            if contentRange.length > 0 {
                attributed.enumerateAttributes(in: contentRange, options: []) { attrs, range, _ in
                    let text = ns.substring(with: range)
                    if text.isEmpty { return }
                    let charAttrs = CharacterAttributes.from(nsAttributes: attrs, defaultFont: defaultFont)
                    // Гиперссылка: значение .link может быть URL или строкой.
                    let hyperlink: String? = {
                        if let s = attrs[.link] as? String { return s }
                        if let u = attrs[.link] as? URL { return u.absoluteString }
                        return nil
                    }()
                    // v0.4.5: id треда комментария (custom NSAttributedString key).
                    let commentId = attrs[.docxEditCommentId] as? String
                    // v0.4.7: track-changes.
                    let insertion = attrs[.docxEditInsertion] as? String
                    let deletion  = attrs[.docxEditDeletion]  as? String
                    // v0.5.5 (R07): перекрёстная ссылка.
                    let crossRef  = attrs[.docxEditCrossRef]  as? String
                    // v0.5.6 (R07): маркер TOC-блока.
                    let tocBlock  = attrs[.docxEditTocBlock]  as? String
                    // v0.5.8 (R08): ревизия атрибутов.
                    let attributeRevision = attrs[.docxEditAttributeRevision] as? String
                    // v1.5.6: инструкция сложного поля.
                    let fieldInstr = attrs[.docxEditFieldInstr] as? String
                    // v0.5.3 (R07): якорь сноски. Если атрибут стоит — сохраняем
                    // как отдельный Run с footnoteId (текст маркера отбрасываем;
                    // маркер восстановится из id при экспорте).
                    if let fid = attrs[.docxEditFootnoteId] as? String {
                        runs.append(Run(text: "", attributes: CharacterAttributes(),
                                        commentId: commentId, insertion: insertion,
                                        deletion: deletion, footnoteId: fid))
                        return
                    }
                    // v1.5.15: якорь концевой сноски — симметрично.
                    if let eid = attrs[.docxEditEndnoteId] as? String {
                        runs.append(Run(text: "", attributes: CharacterAttributes(),
                                        commentId: commentId, insertion: insertion,
                                        deletion: deletion, endnoteId: eid))
                        return
                    }
                    // Inline-изображение: если в атрибутах есть .attachment — извлекаем
                    // InlineImage и создаём отдельный Run (не сливаем с текстовыми).
                    if let att = attrs[.attachment] as? NSTextAttachment,
                       var img = inlineImage(from: att) {
                        if let alt = attrs[.docxEditImageAltText] as? String, !alt.isEmpty {
                            img.altText = alt
                        }
                        if let raw = attrs[.docxEditImageWrap] as? String,
                           let w = InlineImageWrap(rawValue: raw) {
                            img.wrap = w
                        }
                        // v1.5.12: плавающий якорь "xEMU,yEMU,wEMU,hEMU"
                        // (старый формат "x,y" тоже читаем).
                        if let raw = attrs[.docxEditImageAnchor] as? String {
                            let parts = raw.split(separator: ",")
                            if parts.count >= 2 {
                                img.anchorXEMU = Int(parts[0])
                                img.anchorYEMU = Int(parts[1])
                            }
                            if parts.count >= 4,
                               let wEmu = Int(parts[2]), let hEmu = Int(parts[3]),
                               wEmu > 0, hEmu > 0 {
                                img.displayWidth = CGFloat(wEmu) / 12700.0
                                img.displayHeight = CGFloat(hEmu) / 12700.0
                            }
                        }
                        runs.append(Run(text: text, attributes: charAttrs, image: img, hyperlink: hyperlink,
                                        commentId: commentId, insertion: insertion, deletion: deletion))
                        return
                    }
                    if var last = runs.last, last.attributes == charAttrs,
                       last.image == nil, last.hyperlink == hyperlink, last.commentId == commentId,
                       last.insertion == insertion, last.deletion == deletion,
                       last.footnoteId == nil, last.endnoteId == nil, last.crossRef == crossRef, last.tocBlock == tocBlock,
                       last.attributeRevision == attributeRevision,
                       last.fieldInstr == nil, fieldInstr == nil {
                        last.text += text
                        runs[runs.count - 1] = last
                    } else {
                        runs.append(Run(text: text, attributes: charAttrs, hyperlink: hyperlink,
                                        commentId: commentId, insertion: insertion, deletion: deletion,
                                        crossRef: crossRef, tocBlock: tocBlock,
                                        attributeRevision: attributeRevision, fieldInstr: fieldInstr))
                    }
                }
            }
            if runs.isEmpty {
                runs.append(Run(text: "", attributes: CharacterAttributes()))
            }
            return Paragraph(runs: runs, attributes: pAttrs)
        }

        var loc = 0
        while loc < length {
            let paraRange = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let pAttrs = paragraphAttrs(at: paraRange.location)
            // Контент без завершающего перевода строки.
            var contentRange = paraRange
            if contentRange.length > 0,
               ns.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1)) == "\n" {
                contentRange.length -= 1
            }

            // Определяем принадлежность абзаца к ячейке таблицы.
            var cellBlock: NSTextTableBlock?
            if let ps = attributed.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle {
                cellBlock = ps.textBlocks.compactMap { $0 as? NSTextTableBlock }.first
            }

            if let cb = cellBlock {
                let nsTable = cb.table
                if pendingTable?.nsTable !== nsTable {
                    flushTable()
                    // Восстанавливаем alignment из кастомного атрибута на первом символе таблицы.
                    var tableAlign: TableAlignment = .left
                    if let raw = attributed.attribute(.docxEditTableAlignment,
                                                      at: paraRange.location,
                                                      effectiveRange: nil) as? String,
                       let a = TableAlignment(rawValue: raw) {
                        tableAlign = a
                    }
                    pendingTable = (nsTable, [], tableAlign)
                }
                let para = buildParagraph(contentRange: contentRange, pAttrs: pAttrs)
                // Читаем ширину ячейки из NSTextBlock.contentWidth (только absoluteValueType — pt).
                let cellWidth: CGFloat? =
                    (cb.contentWidthValueType == .absoluteValueType && cb.contentWidth > 0)
                        ? cb.contentWidth : nil
                // v0.1.85/86: атрибуты уровня строки — читаем ключи с первого символа контент-диапазона.
                var isHeaderRow = false
                var rowHeight: CGFloat? = nil
                if contentRange.length > 0 {
                    isHeaderRow = (attributed.attribute(.docxEditRowHeader, at: contentRange.location, effectiveRange: nil) as? Bool) ?? false
                    let raw = attributed.attribute(.docxEditRowHeight, at: contentRange.location, effectiveRange: nil)
                    if let v = raw as? CGFloat { rowHeight = v }
                    else if let v = raw as? Double { rowHeight = CGFloat(v) }
                    else if let v = raw as? NSNumber { rowHeight = CGFloat(truncating: v) }
                }
                // v0.1.90: ресайз мышью пишет `.height` прямо в NSTextTableBlock, минуя
                // наш кастомный ключ — читаем блок как источник истины, он новее ключа.
                if cb.valueType(for: .height) == .absoluteValueType {
                    let bh = cb.value(for: .height)
                    if bh > 0 { rowHeight = bh }
                }
                if let idx = pendingTable!.cells.firstIndex(where: {
                    $0.row == cb.startingRow && $0.col == cb.startingColumn
                }) {
                    pendingTable!.cells[idx].paras.append(para)
                    if isHeaderRow { pendingTable!.cells[idx].isHeaderRow = true }
                    if pendingTable!.cells[idx].rowHeight == nil { pendingTable!.cells[idx].rowHeight = rowHeight }
                } else {
                    pendingTable!.cells.append(CellBuffer(
                        row: cb.startingRow, col: cb.startingColumn,
                        rowSpan: cb.rowSpan, colSpan: cb.columnSpan,
                        bg: cb.backgroundColor,
                        width: cellWidth,
                        paras: [para],
                        isHeaderRow: isHeaderRow,
                        rowHeight: rowHeight))
                }
            } else {
                flushTable()
                let para = buildParagraph(contentRange: contentRange, pAttrs: pAttrs)
                blocks.append(.paragraph(para))
            }

            loc = NSMaxRange(paraRange)
        }
        flushTable()

        if blocks.isEmpty {
            blocks.append(.paragraph(Paragraph(
                runs: [Run(text: "", attributes: CharacterAttributes())],
                attributes: ParagraphAttributes()
            )))
        }

        return DocumentModel(
            metadata: DocumentMetadata(),
            pageSettings: .a4Portrait,
            sections: [DocumentSection(blocks: blocks)]
        )
    }
}

// MARK: - Рендер таблицы через NSTextTable (R03, v0.1.49)

/// Собирает `NSAttributedString`-представление таблицы: `NSTextTable` +
/// `NSTextTableBlock` на каждую ячейку в `paragraphStyle.textBlocks` каждого
/// абзаца ячейки. AppKit сам рисует границы/заливку/разбиение на колонки в
/// TextKit 1. Разделитель ячеек — `\n` (терминатор абзаца): следующий абзац
/// имеет свой `textBlocks`, указывающий на соседнюю ячейку.
func appendTable(_ t: TableBlock,
                 to result: NSMutableAttributedString,
                 defaultFont: NSFont,
                 fallbackFontName: String?,
                 usableWidth: CGFloat = 0) {
    // Ширина сетки = сумма colSpan первой строки (у неё нет входящих rowSpan сверху).
    // Берём max по всем строкам на случай неровной модели.
    let columns = max(1, t.rows.map { row in row.cells.reduce(0) { $0 + max(1, $1.colSpan) } }.max() ?? 1)
    let nsTable = NSTextTable()
    nsTable.numberOfColumns = columns
    nsTable.collapsesBorders = t.style.hasBorders
    nsTable.hidesEmptyCells = false
    nsTable.layoutAlgorithm = .automaticLayoutAlgorithm

    let borderColor: NSColor = t.style.borderColor.map { cc in
        NSColor(srgbRed: cc.red, green: cc.green, blue: cc.blue, alpha: cc.alpha)
    } ?? NSColor(white: 0.6, alpha: 1)
    let borderW = t.style.hasBorders ? max(0.5, t.style.borderWidth) : 0

    // v0.1.95: визуальный сдвиг таблицы восстановлен (по решению не откатывать).
    // Overhead-подход из v0.1.93: content-area таблицы = сумма cell.contentWidth
    // + padding (8pt на ячейку) + внешние + слитые внутренние границы. Известное
    // ограничение: на реальных таблицах ширина колонок может «плыть», подбор
    // overhead приблизительный (collapsesBorders не даёт точных API).
    let totalColumnWidth = t.columnWidths.reduce(0, +)
    if t.alignment != .left, usableWidth > 0, totalColumnWidth > 0 {
        let colsF = CGFloat(columns)
        let paddingOverhead = colsF * 8
        let borderOverhead = borderW > 0 ? (colsF + 1) * borderW : 0
        let effectiveWidth = totalColumnWidth + paddingOverhead + borderOverhead
        if effectiveWidth < usableWidth {
            nsTable.setContentWidth(effectiveWidth, type: .absoluteValueType)
            let leftover = usableWidth - effectiveWidth
            let leftMargin = (t.alignment == .center) ? leftover / 2 : leftover
            nsTable.setWidth(leftMargin, type: .absoluteValueType, for: .margin, edge: .minX)
        }
    }

    let defaultAttrs: [NSAttributedString.Key: Any] = [
        .font: defaultFont,
        .foregroundColor: NSColor.labelColor,
    ]

    let tableStart = result.length

    // Грид-трекинг вертикального merge: openMerge[gridCol] = сколько строк ниже
    // ещё «покрыты» rowSpan-ячейкой сверху. В модели такие ячейки ОТСУТСТВУЮТ
    // (строка ниже содержит меньше cells), поэтому startingColumn нельзя брать по
    // индексу массива — нужен реальный grid-столбец с учётом покрытых сверху.
    var openMerge = [Int](repeating: 0, count: columns)
    for (rowIdx, row) in t.rows.enumerated() {
        var cellIter = row.cells.makeIterator()
        var gridCol = 0
        while gridCol < columns {
            if openMerge[gridCol] > 0 {
                openMerge[gridCol] -= 1
                gridCol += 1
                continue
            }
            guard let cell = cellIter.next() else { break }
            let colSpan = max(1, cell.colSpan)
            let rowSpan = max(1, cell.rowSpan)
            let cellBlock = NSTextTableBlock(
                table: nsTable,
                startingRow: rowIdx, rowSpan: rowSpan,
                startingColumn: gridCol, columnSpan: colSpan
            )
            if borderW > 0 {
                cellBlock.setBorderColor(borderColor)
                let edges: [NSRectEdge] = [.minX, .maxX, .minY, .maxY]
                for edge in edges {
                    cellBlock.setWidth(borderW, type: .absoluteValueType, for: .border, edge: edge)
                }
            }
            if let bg = cell.backgroundColor {
                cellBlock.backgroundColor = NSColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: bg.alpha)
            }
            if let w = cell.width, w > 0 {
                cellBlock.setContentWidth(w, type: .absoluteValueType)
            }
            // v0.1.90: высота строки — через `.height` блока, НЕ `.minimumHeight`.
            // TextKit 1 рендерит `.height`, а `.minimumHeight` игнорирует (диагноз
            // v0.1.86–89: ресайз мышью работал, потому что AppKit при drag пишет
            // именно `.height`; наш `.minimumHeight` не давал визуального эффекта,
            // а хак с minimumLineHeight на последнем абзаце (v0.1.87) блокировал
            // последующий ресайз мышью). Единый механизм с мышью = взаимная
            // совместимость: диалог видит мышиное значение и наоборот.
            if let rh = row.height, rh > 0 {
                cellBlock.setValue(rh, type: .absoluteValueType, for: .height)
            }
            // Внутренние отступы, чтобы текст не липнул к границе.
            let edges: [NSRectEdge] = [.minX, .maxX, .minY, .maxY]
            for edge in edges {
                cellBlock.setWidth(4, type: .absoluteValueType, for: .padding, edge: edge)
            }

            let paras: [Paragraph] = cell.blocks.compactMap {
                if case .paragraph(let p) = $0 { return p } else { return nil }
            }
            let cellParas: [Paragraph] = paras.isEmpty
                ? [Paragraph(runs: [Run(text: "", attributes: CharacterAttributes())], attributes: ParagraphAttributes())]
                : paras

            for para in cellParas {
                let ps = NSMutableParagraphStyle()
                ps.setParagraphStyle(para.attributes.makeNSParagraphStyle())
                ps.textBlocks = [cellBlock]
                // v0.1.90: хак v0.1.87 (minimumLineHeight на последнем абзаце) удалён —
                // он фиксировал высоту строки текста и блокировал ресайз мышью.
                // Высота теперь задаётся через cellBlock `.height` (см. выше).

                for run in para.runs {
                    if run.text.isEmpty { continue }
                    var attrs = run.attributes.nsAttributes(defaultFont: defaultFont, fallbackFontName: fallbackFontName)
                    attrs[.paragraphStyle] = ps
                    if let url = run.hyperlink { attrs[.link] = url }
                    if let cid = run.commentId { attrs[.docxEditCommentId] = cid }
                    if row.isHeader { attrs[.docxEditRowHeader] = true }
                    if let rh = row.height, rh > 0 { attrs[.docxEditRowHeight] = rh }
                    result.append(NSAttributedString(string: run.text, attributes: attrs))
                }
                // Терминатор абзаца в ячейке (нужен, даже если ячейка пустая, — иначе
                // следующая ячейка сольётся с текущей).
                var termAttrs = defaultAttrs
                termAttrs[.paragraphStyle] = ps
                if row.isHeader { termAttrs[.docxEditRowHeader] = true }
                // v0.1.88: ключ высоты ставим И на терминатор — курсор часто оказывается
                // на \n в пустой ячейке; без этого refreshSelectionState читает nil.
                if let rh = row.height, rh > 0 { termAttrs[.docxEditRowHeight] = rh }
                result.append(NSAttributedString(string: "\n", attributes: termAttrs))
            }

            // Открываем вертикальный merge на покрытые столбцы для строк ниже.
            if rowSpan > 1 {
                for gc in gridCol..<min(gridCol + colSpan, columns) {
                    openMerge[gc] = rowSpan - 1
                }
            }
            gridCol += colSpan
        }
    }
    // v0.1.72: alignment таблицы храним в кастомном атрибуте на всех символах
    // таблицы (NSTextTable своего alignment API не имеет). Читается на первом
    // абзаце в from(attributed:).
    if result.length > tableStart {
        result.addAttribute(.docxEditTableAlignment,
                            value: t.alignment.rawValue,
                            range: NSRange(location: tableStart, length: result.length - tableStart))
    }
    // Ниже таблицы должен быть абзац без `textBlocks`, чтобы курсор мог встать
    // за таблицей и продолжить обычный текст. Если после таблицы уже идёт
    // содержимое, его `\n` (сверху в цикле блоков) добавляется вызывающим кодом.
    // Если таблица — последний блок документа, пустой хвостовой абзац добавит
    // главный цикл `toAttributedString()` через ветку `result.length == 0`
    // (или он вставится при первой правке пользователя).
}