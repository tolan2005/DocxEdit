//
//  Распил монолита DocxIO.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Типы перемещены без изменения кода; private → internal (file-scope
//  private в общем файле был de-facto fileprivate, типы нужны кросс-файл).
//

import Foundation
import ZIPFoundation
import DocxCore

// MARK: - Парсер word/_rels/document.xml.rels (v0.1.53)

/// Разбирает `<Relationship Id="..." Target="..."/>` и заполняет `map: [Id → Target]`.
/// Используется для резолвинга `r:embed` в `<a:blip>` → путь к бинарю в media/.
final class DocumentRelsParser: NSObject, XMLParserDelegate {
    var map: [String: String] = [:]

    func parse(data: Data) {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        if el == "Relationship", let id = a["Id"], let target = a["Target"] {
            map[id] = target
        }
    }
}

// MARK: - Парсер numbering.xml

/// Разбирает word/numbering.xml: <w:abstractNum>/<w:lvl> (формат по уровню) и
/// <w:num>→<w:abstractNumId> (какой абстрактный список использует конкретный numId).
/// Позволяет при разборе document.xml по паре (numId, ilvl) определить реальный
/// ListType/DocxCore.ListFormatStyle вместо жёстко заданного «буллит на уровне 0».
final class NumberingXmlParser: NSObject, XMLParserDelegate {
    /// abstractNumId → [ilvl: (ListType, DocxCore.ListFormatStyle)]
    private var abstractNums: [String: [Int: (ListType, DocxCore.ListFormatStyle)]] = [:]
    /// numId → abstractNumId
    private var numToAbstract: [String: String] = [:]
    /// v1.5.16: w:start по уровню abstractNum.
    private var abstractStarts: [String: [Int: Int]] = [:]
    /// v1.5.16: w:startOverride по (numId, ilvl) из w:lvlOverride.
    private var numStartOverrides: [String: [Int: Int]] = [:]

    private var inAbstractNum = false
    private var currentAbstractId = ""
    private var inLvl = false
    private var currentIlvl = 0
    private var currentNumFmt = "bullet"
    private var currentLvlText = "•"

    private var inNum = false
    private var currentNumId = ""
    /// v1.5.16: внутри w:lvlOverride — уровень для startOverride.
    private var currentOverrideIlvl: Int? = nil

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    /// Возвращает (ListType, DocxCore.ListFormatStyle) для пары numId/ilvl, если найдено в numbering.xml.
    func listInfo(numId: String, ilvl: Int) -> (ListType, DocxCore.ListFormatStyle)? {
        guard let abstractId = numToAbstract[numId] else { return nil }
        return abstractNums[abstractId]?[ilvl]
    }

    /// v1.5.16: стартовое значение нумерации для (numId, ilvl):
    /// startOverride (lvlOverride) приоритетнее w:start уровня.
    func startValue(numId: String, ilvl: Int) -> Int? {
        guard let abstractId = numToAbstract[numId] else { return nil }
        return numStartOverrides[numId]?[ilvl] ?? abstractStarts[abstractId]?[ilvl]
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        switch el {
        case "w:abstractNum":
            inAbstractNum = true
            currentAbstractId = a["w:abstractNumId"] ?? ""
            abstractNums[currentAbstractId] = abstractNums[currentAbstractId] ?? [:]
        case "w:lvl":
            if inAbstractNum {
                inLvl = true
                currentIlvl = Int(a["w:ilvl"] ?? "0") ?? 0
                currentNumFmt = "bullet"
                currentLvlText = "•"
            }
        case "w:numFmt":
            if inLvl, let v = a["w:val"] { currentNumFmt = v }
        case "w:lvlText":
            if inLvl, let v = a["w:val"] { currentLvlText = v }
        case "w:start":
            // v1.5.16: стартовое значение уровня (w:lvl > w:start).
            if inLvl, let v = a["w:val"], let n = Int(v) {
                abstractStarts[currentAbstractId, default: [:]][currentIlvl] = n
            }
        case "w:lvlOverride":
            // v1.5.16: перезапуск/переопределение уровня для конкретного numId.
            if inNum { currentOverrideIlvl = Int(a["w:ilvl"] ?? "") }
        case "w:startOverride":
            if inNum, let ilvl = currentOverrideIlvl,
               let v = a["w:val"], let n = Int(v) {
                numStartOverrides[currentNumId, default: [:]][ilvl] = n
            }
        case "w:num":
            inNum = true
            currentNumId = a["w:numId"] ?? ""
        case "w:abstractNumId":
            if inNum, let v = a["w:val"] { numToAbstract[currentNumId] = v }
        default: break
        }
    }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "w:abstractNum":
            inAbstractNum = false
            // Составной номер («1.1.1.») на уровне 0 в OOXML неотличим от обычного
            // decimal (lvlText="%1."): если хоть один уровень abstractNum составной —
            // считаем составными все нумерованные уровни этого списка.
            if let levels = abstractNums[currentAbstractId],
               levels.values.contains(where: { $0.1 == .decimalNested }) {
                for (ilvl, entry) in levels where entry.0 == .numbered {
                    abstractNums[currentAbstractId]?[ilvl] = (.numbered, .decimalNested)
                }
            }
        case "w:lvl":
            if inLvl {
                let (type, style) = Self.resolve(numFmt: currentNumFmt, lvlText: currentLvlText)
                abstractNums[currentAbstractId]?[currentIlvl] = (type, style)
                inLvl = false
            }
        case "w:num":
            inNum = false
            currentOverrideIlvl = nil
        case "w:lvlOverride":
            currentOverrideIlvl = nil
        default: break
        }
    }

    private static func resolve(numFmt: String, lvlText: String) -> (ListType, DocxCore.ListFormatStyle) {
        let type: ListType
        let style: DocxCore.ListFormatStyle
        // Количество плейсхолдеров %N в lvlText: ≥2 — составной номер вида "1.1.1.".
        let placeholders = lvlText.filter { $0 == "%" }.count
        switch numFmt {
        case "bullet":
            type = .bulleted
            style = .bullet(character: lvlText)
        case "decimal":
            type = .numbered
            if placeholders >= 2 {
                style = .decimalNested
            } else {
                style = lvlText.hasSuffix(")") ? .decimalEnclosedParen : .decimal
            }
        case "lowerLetter":
            type = .numbered
            style = lvlText.hasSuffix(")") ? .lowerLetterParen : .lowerLetter
        case "upperLetter":
            type = .numbered
            style = .upperLetter
        case "lowerRoman":
            type = .numbered
            style = lvlText.hasSuffix(")") ? .lowerRomanParen : .lowerRoman
        case "upperRoman":
            type = .numbered
            style = .upperRoman
        default:
            type = .bulleted
            style = .bullet(character: "•")
        }
        return (type, style)
    }
}

// MARK: - Парсер комментариев (comments.xml) — v0.4.5 (R06)

/// Разбирает `word/comments.xml`. Каждый `<w:comment w:id/author/date/initials>`
/// → CommentThread. Текст берётся из содержимого `<w:t>` внутри параграфов
/// комментария; несколько параграфов внутри одного `<w:comment>` объединяются
/// через `\n`. Ответы отдельно не реконструируются (в нашем writer'е они
/// живут как параграфы того же треда с префиксом `[Автор]:`; при обратном
/// импорте видны как продолжение текста — это MVP-ограничение, задокумент.).
final class CommentsXmlParser: NSObject, XMLParserDelegate {
    var threads: [CommentThread] = []
    private var current: CommentThread?
    private var currentParagraphs: [String] = []
    private var currentText: String = ""
    private var inText = false

    func parse(data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        switch e {
        case "w:comment":
            let id = attr["w:id"] ?? String(threads.count)
            let author = attr["w:author"] ?? ""
            let date: Date = {
                if let s = attr["w:date"] {
                    let f = ISO8601DateFormatter()
                    return f.date(from: s) ?? Date()
                }
                return Date()
            }()
            current = CommentThread(id: id, author: author, date: date, text: "")
            currentParagraphs = []
            currentText = ""
        case "w:t":
            inText = true
        case "w:p":
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inText { currentText += s }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "w:t":
            inText = false
        case "w:p":
            currentParagraphs.append(currentText)
            currentText = ""
        case "w:comment":
            guard var t = current else { return }
            t.text = currentParagraphs.joined(separator: "\n")
            threads.append(t)
            current = nil
            currentParagraphs = []
        default:
            break
        }
    }
}

// MARK: - Парсер сносок (footnotes.xml) — v0.5.2 (R07)

/// Разбирает `word/footnotes.xml`. Каждая `<w:footnote w:id="X">` — это Footnote
/// c текстом из внутренних `<w:t>`. Стандартные footnote (id=-1 separator,
/// id=0 continuationSeparator) пропускаем — они системные.
final class FootnotesXmlParser: NSObject, XMLParserDelegate {
    var footnotes: [Footnote] = []
    /// v1.5.15: имя элемента-контейнера — "w:footnote" (по умолчанию) или
    /// "w:endnote" (концевые сноски). Структура частей идентична.
    var elementName = "w:footnote"
    private var currentId: String?
    private var currentText: String = ""
    private var inText = false

    func parse(data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        switch e {
        case elementName:
            let id = attr["w:id"] ?? ""
            let type = attr["w:type"] ?? ""
            // Системные — separator / continuationSeparator. Пропускаем.
            if type.isEmpty && id != "-1" && id != "0" {
                currentId = id
                currentText = ""
            } else {
                currentId = nil
            }
        case "w:t":
            if currentId != nil { inText = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inText { currentText += s }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "w:t":
            inText = false
        case elementName:
            if let id = currentId {
                footnotes.append(Footnote(id: id, text: currentText))
            }
            currentId = nil
            currentText = ""
        default:
            break
        }
    }
}

// MARK: - Парсер колонтитула (header1.xml / footer1.xml)

/// Извлекает текст и выравнивание из `<w:hdr>`/`<w:ftr>`: содержимое `<w:t>` +
/// поля `<w:fldSimple>` (PAGE→{page}, NUMPAGES→{pages}, DATE→{date}).
final class HeaderFooterPartParser: NSObject, XMLParserDelegate {
    var text = ""
    var alignment: TextAlignment = .center
    private var inText = false
    private var inFld = false
    /// v1.5.2: глубина вложенности mc:Fallback — содержимое пропускаем.
    /// mc:AlternateContent несёт один и тот же текстбокс дважды (wps-Choice +
    /// VML-Fallback), из-за чего список стран в 133.docx дублировался.
    private var fallbackDepth = 0

    func parse(data: Data) {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        // Хвостовые разделители (пробелы после w:p/w:tab) срезаем.
        text = text.trimmingCharacters(in: .whitespaces)
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        if el == "mc:Fallback" { fallbackDepth += 1; return }
        guard fallbackDepth == 0 else { return }
        switch el {
        case "w:jc":
            switch a["w:val"] {
            case "center": alignment = .center
            case "right":  alignment = .right
            case "both":   alignment = .justify
            default:       alignment = .left
            }
        case "w:t":
            inText = true
        case "w:tab":
            // v1.5.2: таб в колонтитуле — разделитель, иначе соседние раны
            // склеиваются («[Escriba texto][Escriba texto]»).
            if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
        case "w:fldSimple":
            inFld = true
            let instr = (a["w:instr"] ?? "").uppercased()
            if instr.contains("NUMPAGES")   { text += "{pages}" }
            else if instr.contains("PAGE")  { text += "{page}" }
            else if instr.contains("DATE")  { text += "{date}" }
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) {
        if inText && !inFld && fallbackDepth == 0 { text += s }
    }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName: String?) {
        if el == "mc:Fallback" { fallbackDepth = max(0, fallbackDepth - 1); return }
        guard fallbackDepth == 0 else { return }
        if el == "w:t" { inText = false }
        if el == "w:fldSimple" { inFld = false }
        // v1.5.2: абзацы не склеиваем — разделитель пробелом (текстбокс со
        // списком стран в 133.docx читался как «ArgentinaAustralia…»).
        if el == "w:p", !text.isEmpty, !text.hasSuffix(" ") { text += " " }
    }
}
