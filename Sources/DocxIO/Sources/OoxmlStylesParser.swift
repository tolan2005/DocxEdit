//
//  Распил монолита DocxIO.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Типы перемещены без изменения кода; private → internal (file-scope
//  private в общем файле был de-facto fileprivate, типы нужны кросс-файл).
//

import Foundation
import ZIPFoundation
import DocxCore

// MARK: - Вспомогательные типы для парсинга

/// Явно установленные свойства прогона (из XML-элемента <w:rPr> или стиля).
/// nil = «не задано» (унаследовать из нижележащего уровня).
struct RunProps {
    var fontName: String? = nil
    var fontSize: CGFloat? = nil
    var bold: Bool? = nil
    var italic: Bool? = nil
    var underline: UnderlineStyle? = nil
    var strikethrough: Bool? = nil
    var superscript: Bool? = nil
    var `subscript`: Bool? = nil
    var textColor: CodableColor? = nil
    var backgroundColor: CodableColor? = nil

    /// Применяет свои явно-установленные поля поверх базы.
    func apply(to base: CharacterAttributes) -> CharacterAttributes {
        var r = base
        if let v = fontName     { r.fontName     = v }
        if let v = fontSize     { r.fontSize     = v }
        if let v = bold         { r.bold         = v }
        if let v = italic       { r.italic       = v }
        if let v = underline    { r.underline    = v }
        if let v = strikethrough{ r.strikethrough = v }
        if let v = superscript  { r.superscript   = v }
        if let v = `subscript`  { r.`subscript`   = v }
        if let v = textColor    { r.textColor    = v }
        if let v = backgroundColor { r.highlightColor = v }
        return r
    }

    /// Возвращает CharacterAttributes, сформированный только из наших полей (база = default).
    func toCharacterAttributes() -> CharacterAttributes {
        apply(to: CharacterAttributes())
    }

    /// Мерджит поверх себя другой RunProps (other приоритетнее).
    func merging(_ other: RunProps) -> RunProps {
        var r = self
        if let v = other.fontName      { r.fontName      = v }
        if let v = other.fontSize      { r.fontSize      = v }
        if let v = other.bold          { r.bold          = v }
        if let v = other.italic        { r.italic        = v }
        if let v = other.underline     { r.underline     = v }
        if let v = other.strikethrough { r.strikethrough = v }
        if let v = other.superscript   { r.superscript   = v }
        if let v = other.`subscript`   { r.`subscript`   = v }
        if let v = other.textColor     { r.textColor     = v }
        if let v = other.backgroundColor { r.backgroundColor = v }
        return r
    }
}

/// Явно установленные свойства абзаца из <w:pPr>.
struct ParaProps {
    var styleId: String?      = nil
    var alignment: TextAlignment? = nil
    var lineSpacing: LineSpacing? = nil
    var spaceBefore: CGFloat? = nil
    var spaceAfter: CGFloat?  = nil
    var leftIndent: CGFloat?  = nil
    var rightIndent: CGFloat? = nil
    var firstLineIndent: CGFloat? = nil
    var hangingIndent: CGFloat? = nil
    var listInfo: ListInfo?   = nil
    var tabStops: [TabStop]?  = nil
    var border: ParagraphBorder? = nil
    /// v1.6.1: буквица/рамка абзаца (w:framePr) — карта атрибутов.
    var framePr: [String: String]? = nil

    func apply(to base: ParagraphAttributes) -> ParagraphAttributes {
        var r = base
        if let v = styleId         { r.styleId         = v }
        if let v = alignment       { r.alignment       = v }
        if let v = lineSpacing     { r.lineSpacing     = v }
        if let v = spaceBefore     { r.spaceBefore     = v }
        if let v = spaceAfter      { r.spaceAfter      = v }
        if let v = leftIndent      { r.leftIndent      = v }
        if let v = rightIndent     { r.rightIndent     = v }
        if let v = firstLineIndent { r.firstLineIndent = v }
        if let v = hangingIndent   { r.hangingIndent   = v }
        if let v = listInfo        { r.listInfo        = v }
        if let v = tabStops        { r.tabStops        = v }
        if let v = border          { r.border          = v }
        if let v = framePr         { r.framePr         = v }
        return r
    }
}

/// Определение стиля из styles.xml (до разворачивания наследования).
struct StyleDef {
    var styleType: String  = "paragraph" // "paragraph" | "character"
    var name: String?      = nil          // <w:name w:val="…"> — отображаемое имя
    var basedOn: String?   = nil
    var ownRunProps: RunProps  = RunProps()
    var ownParaProps: ParaProps = ParaProps()
    /// Итоговые runProps после разворачивания цепочки basedOn.
    var resolvedRunProps: RunProps = RunProps()
    var resolvedParaProps: ParaProps = ParaProps()
}

// MARK: - Парсер стилей

final class OoxmlStylesParser: NSObject, XMLParserDelegate {
    /// Умолчания из <w:docDefaults>.
    var defaultRunProps = RunProps()

    /// Сырые (ещё не resolved) стили.
    private var rawStyles: [String: StyleDef] = [:]

    // -- внутреннее состояние --
    private var inDocDefaults = false
    private var inDocDefaultsRPr = false
    private var inStyle = false
    private var currentStyleId = ""
    private var currentStyleType = "paragraph"
    private var inStyleRPr = false

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    /// Возвращает таблицу стилей с разворачиванным basedOn (до 10 уровней).
    func resolvedStyles() -> [String: StyleDef] {
        var table = rawStyles
        // Итеративно разворачиваем basedOn цепочку.
        for key in table.keys {
            var style = table[key]!
            style.resolvedRunProps  = resolveRunProps(for: key, in: rawStyles, depth: 0)
            style.resolvedParaProps = resolveParaProps(for: key, in: rawStyles, depth: 0)
            table[key] = style
        }
        return table
    }

    private func resolveRunProps(for id: String, in table: [String: StyleDef], depth: Int) -> RunProps {
        guard depth < 10, let style = table[id] else { return RunProps() }
        if let base = style.basedOn {
            let parentProps = resolveRunProps(for: base, in: table, depth: depth + 1)
            return parentProps.merging(style.ownRunProps)
        }
        return defaultRunProps.merging(style.ownRunProps)
    }

    private func resolveParaProps(for id: String, in table: [String: StyleDef], depth: Int) -> ParaProps {
        guard depth < 10, let style = table[id] else { return ParaProps() }
        if let base = style.basedOn {
            let parentProps = resolveParaProps(for: base, in: table, depth: depth + 1)
            return mergeParaProps(parentProps, style.ownParaProps)
        }
        return mergeParaProps(ParaProps(), style.ownParaProps)
    }

    private func mergeParaProps(_ base: ParaProps, _ other: ParaProps) -> ParaProps {
        var r = base
        if let v = other.styleId         { r.styleId         = v }
        if let v = other.alignment       { r.alignment       = v }
        if let v = other.lineSpacing     { r.lineSpacing     = v }
        if let v = other.spaceBefore     { r.spaceBefore     = v }
        if let v = other.spaceAfter      { r.spaceAfter      = v }
        if let v = other.leftIndent      { r.leftIndent      = v }
        if let v = other.rightIndent     { r.rightIndent     = v }
        if let v = other.firstLineIndent { r.firstLineIndent = v }
        if let v = other.hangingIndent   { r.hangingIndent   = v }
        if let v = other.listInfo        { r.listInfo        = v }
        return r
    }

    // MARK: XMLParserDelegate

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        switch el {
        case "w:docDefaults":
            inDocDefaults = true
        case "w:rPrDefault":
            if inDocDefaults { inDocDefaultsRPr = true }
        case "w:style":
            inStyle = true
            currentStyleId   = a["w:styleId"] ?? ""
            currentStyleType = a["w:type"] ?? "paragraph"
            rawStyles[currentStyleId] = StyleDef(styleType: currentStyleType)
        case "w:name":
            if inStyle, let val = a["w:val"] {
                rawStyles[currentStyleId]?.name = val
            }
        case "w:basedOn":
            if inStyle, let val = a["w:val"] {
                rawStyles[currentStyleId]?.basedOn = val
            }
        case "w:rPr":
            if inStyle { inStyleRPr = true }
        case "w:b":
            if inDocDefaultsRPr { defaultRunProps.bold = true }
            else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.bold = true }
        case "w:i":
            if inDocDefaultsRPr { defaultRunProps.italic = true }
            else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.italic = true }
        case "w:u":
            let val = a["w:val"] ?? "single"
            if val != "none" {
                let style = OoxmlUnderlineMapper.parse(val)
                if inDocDefaultsRPr { defaultRunProps.underline = style }
                else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.underline = style }
            }
        case "w:strike":
            if inDocDefaultsRPr { defaultRunProps.strikethrough = true }
            else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.strikethrough = true }
        case "w:vertAlign":
            // v0.1.77: над/подстрочный. w:val = "superscript" | "subscript" | "baseline".
            let val = a["w:val"] ?? "baseline"
            let isSuper = (val == "superscript")
            let isSub   = (val == "subscript")
            if inDocDefaultsRPr {
                if isSuper { defaultRunProps.superscript = true }
                if isSub   { defaultRunProps.`subscript` = true }
            } else if inStyleRPr {
                if isSuper { rawStyles[currentStyleId]?.ownRunProps.superscript = true }
                if isSub   { rawStyles[currentStyleId]?.ownRunProps.`subscript` = true }
            }
        case "w:color":
            if let hex = a["w:val"], let c = CodableColor.fromHex(hex) {
                if inDocDefaultsRPr { defaultRunProps.textColor = c }
                else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.textColor = c }
            }
        case "w:sz":
            if let v = a["w:val"], let n = Double(v) {
                let pts = CGFloat(n) / 2.0
                if inDocDefaultsRPr { defaultRunProps.fontSize = pts }
                else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.fontSize = pts }
            }
        case "w:rFonts":
            let name = a["w:ascii"] ?? a["w:hAnsi"] ?? a["w:cs"]
            if let name {
                if inDocDefaultsRPr { defaultRunProps.fontName = name }
                else if inStyleRPr  { rawStyles[currentStyleId]?.ownRunProps.fontName = name }
            }
        case "w:shd":
            // Заливка текста стиля: <w:shd w:fill="RRGGBB"/> (auto/пусто — без заливки).
            if inStyleRPr, let fill = a["w:fill"], fill.lowercased() != "auto",
               let c = CodableColor.fromHex(fill) {
                rawStyles[currentStyleId]?.ownRunProps.backgroundColor = c
            }
        case "w:jc":
            if inStyle, let val = a["w:val"] {
                rawStyles[currentStyleId]?.ownParaProps.alignment = alignment(from: val)
            }
        case "w:spacing":
            if inStyle {
                if let v = a["w:line"], let n = Double(v) {
                    rawStyles[currentStyleId]?.ownParaProps.lineSpacing = .multiple(CGFloat(n) / 240.0)
                }
                if let v = a["w:before"], let n = Double(v) {
                    rawStyles[currentStyleId]?.ownParaProps.spaceBefore = CGFloat(n) / 20.0
                }
                if let v = a["w:after"], let n = Double(v) {
                    rawStyles[currentStyleId]?.ownParaProps.spaceAfter = CGFloat(n) / 20.0
                }
            }
        default: break
        }
    }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "w:docDefaults":   inDocDefaults = false
        case "w:rPrDefault":    inDocDefaultsRPr = false
        case "w:style":         inStyle = false; inStyleRPr = false
        case "w:rPr":           inStyleRPr = false
        default: break
        }
    }

    private func alignment(from val: String) -> TextAlignment {
        switch val {
        case "center": return .center
        case "right":  return .right
        case "both":   return .justify
        default:       return .left
        }
    }
}
