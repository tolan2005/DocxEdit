//
//  Распил монолита DocxIO.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Типы перемещены без изменения кода; private → internal (file-scope
//  private в общем файле был de-facto fileprivate, типы нужны кросс-файл).
//

import Foundation
import ZIPFoundation
import DocxCore

// MARK: - Сериализация

final class OoxmlDocumentSerializer {
    /// numId каждого абзаца документа в порядке обхода рендера (0 — не список).
    /// numId назначается на НЕПРЕРЫВНЫЙ блок списочных абзацев (а не на формат
    /// маркера): уровни одного многоуровневого списка имеют разные форматы,
    /// но должны принадлежать одному <w:num>, иначе Word разорвёт нумерацию.
    private var numIdForParagraph: [Int] = []
    /// numId → (уровень → формат маркера) — реальные форматы уровней блока.
    private var levelFormats: [Int: [Int: DocxCore.ListFormatStyle]] = [:]
    /// v1.5.16: стартовые значения уровней по блоку (numId → ilvl → start).
    private var levelStarts: [Int: [Int: Int]] = [:]
    /// Счётчик абзацев при рендере — индекс в numIdForParagraph (обход идентичен collect-проходу).
    private var renderParaIndex = 0
    /// Override стилей на уровне документа (из диалога «Стили…»); nil для того
    /// же id — писать стандартный def.
    private var paragraphOverrides: [String: ParagraphStyleDef] = [:]
    /// v1.5.17: сырые определения стилей таблиц (`<w:style w:type="table">…`)
    /// из исходного styles.xml — passthrough в экспортируемый styles.xml.
    private var preservedTableStylesXml: String? = nil
    private var characterOverrides: [String: CharacterStyleDef] = [:]
    private var docHeaderFooter = HeaderFooter()
    /// v1.5.1 (DESIGN_HEADER_FOOTER.md): lossless passthrough — сырые части
    /// колонтитулов из исходного пакета; пишутся вместо генерации, если
    /// колонтитул не редактировался. Пусто при headerFooterEdited == true.
    private var preservedHF: [String: PreservedHFPart] = [:]
    /// v1.5.2: passthrough прочих неизвестных частей + их Content-Type;
    /// settings.xml пишется из passthrough (hasSettingsXml для Override).
    private var preservedExtra: [String: Data] = [:]
    private var preservedCT: [String: String] = [:]
    private var hasSettingsXml = false
    /// v1.5.4: passthrough неизвестных детей sectPr (w:cols и др.).
    private var sectPrExtras: String? = nil

    private func hfPartName(_ slot: String, fallback: String) -> String {
        preservedHF[slot]?.partName ?? fallback
    }

    private var hasHeader: Bool { !docHeaderFooter.headerText.isEmpty || preservedHF["headerDefault"] != nil }
    private var hasFooter: Bool { !docHeaderFooter.footerText.isEmpty || preservedHF["footerDefault"] != nil }
    // v0.2.3: доп. header/footer part'ы для первой страницы и чётных.
    private var hasFirstHeader: Bool { docHeaderFooter.differentFirstPage && (!docHeaderFooter.firstHeaderText.isEmpty || preservedHF["headerFirst"] != nil) }
    private var hasFirstFooter: Bool { docHeaderFooter.differentFirstPage && (!docHeaderFooter.firstFooterText.isEmpty || preservedHF["footerFirst"] != nil) }
    private var hasEvenHeader:  Bool { docHeaderFooter.differentOddEven && (!docHeaderFooter.evenHeaderText.isEmpty || preservedHF["headerEven"] != nil) }
    private var hasEvenFooter:  Bool { docHeaderFooter.differentOddEven && (!docHeaderFooter.evenFooterText.isEmpty || preservedHF["footerEven"] != nil) }

    // v0.1.53: inline-изображения. Собираются перед рендером; каждая уникальная
    // (data, format) → отдельный rId + word/media/imageN.ext.
    private struct ImageEntry {
        let rId: String       // "rIdImg1", "rIdImg2", …
        let filename: String  // "image1.png"
        let ext: String       // "png"/"jpeg"/"gif"/"tiff"
        let contentType: String
        let data: Data
        let widthPt: CGFloat
        let heightPt: CGFloat
        let altText: String?
        let wrap: InlineImageWrap  // v0.1.102: режим обтекания текстом
        // v1.5.12: позиция плавающего якоря (EMU, от колонки/абзаца).
        let anchorXEMU: Int?
        let anchorYEMU: Int?
    }
    private var imageEntries: [ImageEntry] = []
    /// Индекс `Run.image → rId` — по позиции при обходе. Ключ = порядковый индекс
    /// картинки в обходе `collectImages`, значение = ImageEntry.
    private var imagesByRunIndex: [Int: Int] = [:]
    private var currentImageRunIndex = 0

    // v0.1.54: гиперссылки. Уникальный URL → rId; `<w:hyperlink r:id="…">` в
    // document.xml + Relationship (Type=hyperlink, TargetMode=External) в
    // document.xml.rels. Одна ссылка (URL) может встречаться несколько раз в
    // документе — переиспользуем один rId.
    private var hyperlinkRIdByUrl: [String: String] = [:]
    /// v0.4.5 (R06): thread.id → числовой w:id для `<w:comment w:id="…">` /
    /// commentRangeStart/End/Reference. Только для тредов, у которых есть якорь
    /// в тексте (т.е. хотя бы один Run.commentId равен id треда). Осиротевшие
    /// треды при экспорте теряются — задокументировано.
    private var commentNumIdById: [String: Int] = [:]
    /// v0.5.2 (R07): выставляется true, если writer добавил footnotes.xml —
    /// используется renderContentTypes/renderDocumentRels для вставки Override.
    private var hasFootnotes: Bool = false
    /// v1.5.15: writer добавил endnotes.xml — Content_Types + rels.
    private var hasEndnotes: Bool = false

    func serialize(document: DocumentModel) throws -> [String: Data] {
        // v1.5.16: сброс starts перед сбором блоков.
        levelStarts = [:]
        collectListBlocks(document)
        collectImages(document)
        collectHyperlinks(document)
        collectComments(document)
        revisionCounter = 0
        renderParaIndex = 0
        currentImageRunIndex = 0
        paragraphOverrides = document.styles.paragraphStyles
        characterOverrides = document.styles.characterStyles
        preservedTableStylesXml = document.preservedTableStylesXml
        docHeaderFooter = document.headerFooter
        // v1.5.1: passthrough только если колонтитул не редактировался.
        preservedHF = document.headerFooterEdited ? [:] : document.preservedHeaderFooter
        preservedExtra = document.preservedParts
        preservedCT = document.preservedContentTypes
        hasSettingsXml = document.preservedSettingsXml != nil || docHeaderFooter.differentOddEven
        sectPrExtras = document.preservedSectPrExtras

        var parts: [String: Data] = [:]
        parts["[Content_Types].xml"]          = Data(contentTypesXml.utf8)
        parts["_rels/.rels"]                  = Data(rootRelsXml.utf8)
        parts["word/_rels/document.xml.rels"] = Data(documentRelsXml.utf8)
        parts["word/document.xml"]            = Data(renderDocument(document).utf8)
        parts["word/styles.xml"]              = Data(stylesXml.utf8)
        parts["docProps/core.xml"]            = Data(renderCoreProps(document.metadata).utf8)
        if !levelFormats.isEmpty {
            parts["word/numbering.xml"] = Data(renderNumbering().utf8)
        }
        // v1.5.1: для каждого слота — preserved-часть (сырые байты + rels +
        // media) или регенерация из текста модели, как раньше.
        func writeHF(slot: String, tag: String, text: String,
                     alignment: DocxCore.TextAlignment, fallbackName: String) {
            if let p = preservedHF[slot] {
                parts["word/\(p.partName)"] = p.xml
                if let rels = p.relsXml {
                    parts["word/_rels/\(p.partName).rels"] = rels
                }
                for (name, data) in p.media {
                    parts["word/media/\(name)"] = data
                }
            } else {
                parts["word/\(fallbackName)"] = Data(renderHeaderFooterPart(
                    tag: tag, text: text, alignment: alignment).utf8)
            }
        }
        if hasHeader {
            writeHF(slot: "headerDefault", tag: "w:hdr", text: docHeaderFooter.headerText,
                    alignment: docHeaderFooter.headerAlignment, fallbackName: "header1.xml")
        }
        if hasFooter {
            writeHF(slot: "footerDefault", tag: "w:ftr", text: docHeaderFooter.footerText,
                    alignment: docHeaderFooter.footerAlignment, fallbackName: "footer1.xml")
        }
        if hasFirstHeader {
            writeHF(slot: "headerFirst", tag: "w:hdr", text: docHeaderFooter.firstHeaderText,
                    alignment: docHeaderFooter.firstHeaderAlignment, fallbackName: "header2.xml")
        }
        if hasFirstFooter {
            writeHF(slot: "footerFirst", tag: "w:ftr", text: docHeaderFooter.firstFooterText,
                    alignment: docHeaderFooter.firstFooterAlignment, fallbackName: "footer2.xml")
        }
        if hasEvenHeader {
            writeHF(slot: "headerEven", tag: "w:hdr", text: docHeaderFooter.evenHeaderText,
                    alignment: docHeaderFooter.evenHeaderAlignment, fallbackName: "header3.xml")
        }
        if hasEvenFooter {
            writeHF(slot: "footerEven", tag: "w:ftr", text: docHeaderFooter.evenFooterText,
                    alignment: docHeaderFooter.evenFooterAlignment, fallbackName: "footer3.xml")
        }
        // v0.2.3: `<w:evenAndOddHeaders/>` живёт в settings.xml (не sectPr).
        // v1.5.2: пишем passthrough-оригинал settings.xml (если был), при
        // необходимости инжектим флаг; свой минимальный — только если оригинала
        // не было (раньше терялись compat/zoom/proofState и др. настройки).
        if var settings = document.preservedSettingsXml {
            if docHeaderFooter.differentOddEven,
               let s0 = String(data: settings, encoding: .utf8),
               !s0.contains("<w:evenAndOddHeaders") {
                let s1 = s0.replacingOccurrences(of: "</w:settings>",
                                                 with: "<w:evenAndOddHeaders/></w:settings>")
                settings = Data(s1.utf8)
            }
            parts["word/settings.xml"] = settings
        } else if docHeaderFooter.differentOddEven {
            parts["word/settings.xml"] = Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:evenAndOddHeaders/>
            </w:settings>
            """.utf8)
        }
        // v1.5.2: passthrough неизвестных частей (customXml, theme, fontTable,
        // webSettings, endnotes, app.xml, …). Сгенерированные части имеют
        // приоритет (parts[key] != nil) — конфликт имён невозможен, т.к. при
        // импорте consumed-части в preservedParts не попадают.
        for (key, data) in document.preservedParts where parts[key] == nil {
            parts[key] = data
        }
        // v0.4.5 (R06): комментарии — word/comments.xml. Пишем только треды с
        // якорем в тексте (`commentNumIdById` содержит только их); осиротевшие
        // теряются при экспорте (Word запрещает висячие `<w:comment>`).
        if !commentNumIdById.isEmpty {
            parts["word/comments.xml"] = Data(renderCommentsXml(document.comments).utf8)
        }
        // v0.5.2 (R07): сноски — word/footnotes.xml. Пишем только реально
        // использованные сноски (те, чей id стоит на каком-то ране).
        if !document.footnotes.isEmpty {
            let usedIds = collectUsedFootnoteIds(document)
            let used = document.footnotes.filter { usedIds.contains($0.id) }
            if !used.isEmpty {
                parts["word/footnotes.xml"] = Data(renderFootnotesXml(used).utf8)
                hasFootnotes = true
            }
        }
        // v1.5.15: концевые сноски — word/endnotes.xml (симметрично).
        if !document.endnotes.isEmpty {
            let usedIds = collectUsedEndnoteIds(document)
            let used = document.endnotes.filter { usedIds.contains($0.id) }
            if !used.isEmpty {
                parts["word/endnotes.xml"] = Data(renderEndnotesXml(used).utf8)
                hasEndnotes = true
            }
        }
        // v0.1.53: изображения — media/imageN.ext.
        for e in imageEntries {
            parts["word/media/\(e.filename)"] = e.data
        }
        return parts
    }

    /// Обходит модель в порядке рендера, заполняет `imageEntries` уникальными
    /// картинками и `imagesByRunIndex` — маппинг «индекс run.image при обходе → индекс entry».
    private func collectImages(_ document: DocumentModel) {
        imageEntries = []
        imagesByRunIndex = [:]
        var runIndex = 0

        func visit(_ p: Paragraph) {
            for run in p.runs {
                guard let img = run.image else { continue }
                let extAndCT: (String, String) = {
                    switch img.format {
                    case .png:  return ("png",  "image/png")
                    case .jpeg: return ("jpeg", "image/jpeg")
                    case .gif:  return ("gif",  "image/gif")
                    case .tiff: return ("tiff", "image/tiff")
                    }
                }()
                let n = imageEntries.count + 1
                let entry = ImageEntry(
                    rId: "rIdImg\(n)",
                    filename: "image\(n).\(extAndCT.0)",
                    ext: extAndCT.0,
                    contentType: extAndCT.1,
                    data: img.data,
                    widthPt: img.displayWidth > 0 ? img.displayWidth : 128,
                    heightPt: img.displayHeight > 0 ? img.displayHeight : 128,
                    altText: img.altText,
                    wrap: img.wrap,
                    anchorXEMU: img.anchorXEMU,
                    anchorYEMU: img.anchorYEMU
                )
                imagesByRunIndex[runIndex] = imageEntries.count
                imageEntries.append(entry)
                runIndex += 1
            }
        }

        for section in document.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p): visit(p)
                case .table(let t):
                    for row in t.rows {
                        for cell in row.cells {
                            for case let .paragraph(p) in cell.blocks { visit(p) }
                        }
                    }
                }
            }
        }
    }

    /// v0.4.5 (R06): собирает `commentNumIdById` — только те thread.id, что
    /// реально встречаются на ранах. Осиротевшие треды (нет якорного текста)
    /// в comments.xml не пишутся — Word запрещает висячие `<w:comment>`.
    private func collectComments(_ document: DocumentModel) {
        commentNumIdById = [:]
        var order: [String] = []
        func visit(_ p: Paragraph) {
            for run in p.runs {
                guard let cid = run.commentId, !cid.isEmpty else { continue }
                if commentNumIdById[cid] == nil {
                    commentNumIdById[cid] = order.count
                    order.append(cid)
                }
            }
        }
        for section in document.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p): visit(p)
                case .table(let t):
                    for row in t.rows {
                        for cell in row.cells {
                            for case let .paragraph(p) in cell.blocks { visit(p) }
                        }
                    }
                }
            }
        }
    }

    /// Обходит модель, собирает уникальные URL гиперссылок в `hyperlinkRIdByUrl`
    /// (URL → "rIdHl1"…). Вызывается перед рендером, чтобы renderRun/renderParagraph
    /// могли резолвить URL → rId, а documentRelsXml — сгенерировать Relationships.
    private func collectHyperlinks(_ document: DocumentModel) {
        hyperlinkRIdByUrl = [:]
        func visit(_ p: Paragraph) {
            for run in p.runs {
                guard let url = run.hyperlink, !url.isEmpty else { continue }
                if hyperlinkRIdByUrl[url] == nil {
                    hyperlinkRIdByUrl[url] = "rIdHl\(hyperlinkRIdByUrl.count + 1)"
                }
            }
        }
        for section in document.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p): visit(p)
                case .table(let t):
                    for row in t.rows {
                        for cell in row.cells {
                            for case let .paragraph(p) in cell.blocks { visit(p) }
                        }
                    }
                }
            }
        }
    }

    /// Предварительный проход: обходит абзацы в ТОМ ЖЕ порядке, что и рендер
    /// (renderDocument/renderTable), назначая numId непрерывным блокам списков
    /// и собирая форматы использованных уровней каждого блока.
    private func collectListBlocks(_ document: DocumentModel) {
        numIdForParagraph = []
        levelFormats = [:]
        var nextNumId = 1
        var currentNumId: Int? = nil

        func visit(_ p: Paragraph) {
            guard let li = p.attributes.listInfo else {
                numIdForParagraph.append(0)
                currentNumId = nil
                return
            }
            let numId: Int
            if let cur = currentNumId {
                numId = cur
            } else {
                numId = nextNumId
                nextNumId += 1
                currentNumId = numId
            }
            numIdForParagraph.append(numId)
            if levelFormats[numId] == nil { levelFormats[numId] = [:] }
            if levelFormats[numId]?[li.level] == nil { levelFormats[numId]?[li.level] = li.formatStyle }
            // v1.5.16: стартовое значение уровня (первое встреченное в блоке).
            if let st = li.start, levelStarts[numId]?[li.level] == nil {
                levelStarts[numId, default: [:]][li.level] = st
            }
        }

        for section in document.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p):
                    visit(p)
                case .table(let t):
                    currentNumId = nil
                    for row in t.rows {
                        for cell in row.cells {
                            currentNumId = nil
                            for case let .paragraph(p) in cell.blocks { visit(p) }
                        }
                    }
                    currentNumId = nil
                }
            }
        }
    }

    private func renderDocument(_ document: DocumentModel) -> String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
        """
        for section in document.sections {
            // v0.5.6 (R07): группируем подряд идущие параграфы с tocBlock —
            // оборачиваем в <w:sdt> с docPartGallery="Table of Contents", чтобы
            // Word распознавал блок как автоматическое оглавление.
            var i = 0
            while i < section.blocks.count {
                if case .paragraph(let p0) = section.blocks[i], isTocParagraph(p0) {
                    var j = i
                    while j < section.blocks.count,
                          case .paragraph(let pj) = section.blocks[j],
                          isTocParagraph(pj) { j += 1 }
                    s += "<w:sdt><w:sdtPr><w:docPartObj>"
                    s += "<w:docPartGallery w:val=\"Table of Contents\"/><w:docPartUnique/>"
                    s += "</w:docPartObj></w:sdtPr><w:sdtContent>"
                    for k in i..<j {
                        if case .paragraph(let p) = section.blocks[k] { s += renderParagraph(p) }
                    }
                    s += "</w:sdtContent></w:sdt>"
                    i = j
                } else {
                    switch section.blocks[i] {
                    case .paragraph(let p): s += renderParagraph(p)
                    case .table(let t):     s += renderTable(t)
                    }
                    i += 1
                }
            }
        }
        s += renderSectionProperties(document.pageSettings)
        s += "\n  </w:body>\n</w:document>\n"
        return s
    }

    /// `<w:sectPr>` в конце body: ссылки на колонтитулы + размер/поля страницы.
    private func renderSectionProperties(_ ps: PageSettings) -> String {
        var s = "<w:sectPr>"
        if hasHeader { s += "<w:headerReference w:type=\"default\" r:id=\"rIdHdr1\"/>" }
        if hasFirstHeader { s += "<w:headerReference w:type=\"first\" r:id=\"rIdHdr2\"/>" }
        if hasEvenHeader  { s += "<w:headerReference w:type=\"even\" r:id=\"rIdHdr3\"/>" }
        if hasFooter { s += "<w:footerReference w:type=\"default\" r:id=\"rIdFtr1\"/>" }
        if hasFirstFooter { s += "<w:footerReference w:type=\"first\" r:id=\"rIdFtr2\"/>" }
        if hasEvenFooter  { s += "<w:footerReference w:type=\"even\" r:id=\"rIdFtr3\"/>" }
        // v0.2.3: `<w:titlePg/>` включает разный колонтитул для первой страницы.
        if docHeaderFooter.differentFirstPage { s += "<w:titlePg/>" }
        let size = ps.pageSizeInPoints
        let w = Int(size.width / 72.0 * 1440.0)
        let h = Int(size.height / 72.0 * 1440.0)
        let orient = ps.orientation == .landscape ? " w:orient=\"landscape\"" : ""
        s += "<w:pgSz w:w=\"\(w)\" w:h=\"\(h)\"\(orient)/>"
        let m = ps.margins
        s += "<w:pgMar w:top=\"\(twips(m.top))\" w:right=\"\(twips(m.right))\" "
        s += "w:bottom=\"\(twips(m.bottom))\" w:left=\"\(twips(m.left))\" "
        s += "w:header=\"\(twips(m.header))\" w:footer=\"\(twips(m.footer))\" w:gutter=\"\(twips(m.gutter))\"/>"
        // v0.2.2: зеркальные поля.
        if ps.mirrorMargins { s += "<w:mirrorMargins/>" }
        // v1.5.4: неизвестные дети sectPr из исходного файла (w:cols, w:docGrid,
        // w:vAlign, w:pgNumType, …) — passthrough без потерь вёрстки.
        if let extras = sectPrExtras, !extras.isEmpty { s += extras }
        s += "</w:sectPr>"
        return s
    }

    /// Строит `word/header1.xml` / `word/footer1.xml` — один абзац с выравниванием;
    /// плейсхолдеры {page}/{pages}/{date} → поля PAGE/NUMPAGES/DATE.
    private func renderHeaderFooterPart(tag: String, text: String,
                                        alignment: TextAlignment) -> String {
        let jc: String
        switch alignment {
        case .left:    jc = "left"
        case .center:  jc = "center"
        case .right:   jc = "right"
        case .justify: jc = "both"
        }
        var runs = ""
        var buffer = ""
        func flush() {
            if !buffer.isEmpty {
                runs += "<w:r><w:t xml:space=\"preserve\">\(escapeXml(buffer))</w:t></w:r>"
                buffer = ""
            }
        }
        var idx = text.startIndex
        while idx < text.endIndex {
            let rest = text[idx...]
            if rest.hasPrefix("{page}") {
                flush(); runs += "<w:fldSimple w:instr=\" PAGE \"/>"
                idx = text.index(idx, offsetBy: 6)
            } else if rest.hasPrefix("{pages}") {
                flush(); runs += "<w:fldSimple w:instr=\" NUMPAGES \"/>"
                idx = text.index(idx, offsetBy: 7)
            } else if rest.hasPrefix("{date}") {
                flush(); runs += "<w:fldSimple w:instr=\" DATE \"/>"
                idx = text.index(idx, offsetBy: 6)
            } else {
                buffer.append(text[idx]); idx = text.index(after: idx)
            }
        }
        flush()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <\(tag) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:p><w:pPr><w:jc w:val="\(jc)"/></w:pPr>\(runs)</w:p>
        </\(tag)>
        """
    }

    private func renderParagraph(_ p: Paragraph) -> String {
        let numId = renderParaIndex < numIdForParagraph.count ? numIdForParagraph[renderParaIndex] : 0
        renderParaIndex += 1
        var s = "<w:p>"
        s += renderParagraphProperties(p.attributes, numId: numId)
        // v0.4.5: комментарий-диапазоны — снаружи run-групп. Отслеживаем
        // активный commentId; при смене — закрываем предыдущий (rangeEnd +
        // reference) и открываем новый (rangeStart). В конце параграфа —
        // закрываем принудительно (MVP: комментарий в границах одного абзаца).
        var activeCommentId: String? = nil
        func openComment(_ id: String) -> String {
            guard let num = commentNumIdById[id] else { return "" }
            return "<w:commentRangeStart w:id=\"\(num)\"/>"
        }
        func closeComment(_ id: String) -> String {
            guard let num = commentNumIdById[id] else { return "" }
            var t = "<w:commentRangeEnd w:id=\"\(num)\"/>"
            t += "<w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr>"
            t += "<w:commentReference w:id=\"\(num)\"/></w:r>"
            return t
        }
        // Группируем подряд идущие runs с одинаковым hyperlink URL / crossRef —
        // hyperlink уходит в `<w:hyperlink r:id="…">…</w:hyperlink>`,
        // crossRef (v0.5.5, R07) — в `<w:fldSimple w:instr=" REF <name> \h ">…</w:fldSimple>`.
        var i = 0
        while i < p.runs.count {
            let url = p.runs[i].hyperlink
            let cid = p.runs[i].commentId
            let xref = p.runs[i].crossRef
            var j = i + 1
            while j < p.runs.count && p.runs[j].hyperlink == url
                    && p.runs[j].commentId == cid
                    && p.runs[j].crossRef == xref { j += 1 }
            // Смена commentId между группами.
            if cid != activeCommentId {
                if let old = activeCommentId { s += closeComment(old) }
                if let new = cid { s += openComment(new) }
                activeCommentId = cid
            }
            let renderRuns: () -> String = {
                var t = ""
                for k in i..<j { t += self.renderRun(p.runs[k]) }
                return t
            }
            if let u = url, !u.isEmpty, let rId = hyperlinkRIdByUrl[u] {
                s += "<w:hyperlink r:id=\"\(rId)\" w:history=\"1\">"
                s += renderRuns()
                s += "</w:hyperlink>"
            } else if let name = xref, !name.isEmpty {
                let instr = " REF \(escapeXml(name)) \\h "
                s += "<w:fldSimple w:instr=\"\(instr)\">"
                s += renderRuns()
                s += "</w:fldSimple>"
            } else {
                s += renderRuns()
            }
            i = j
        }
        if let old = activeCommentId { s += closeComment(old) }
        s += "</w:p>"
        return s
    }

    private func renderParagraphProperties(_ attrs: ParagraphAttributes, numId: Int) -> String {
        var s = "<w:pPr>"
        if let sid = attrs.styleId { s += "<w:pStyle w:val=\"\(escapeXml(sid))\"/>" }
        // v1.6.1: буквица/рамка абзаца (атрибуты как карта, round-trip).
        if let fp = attrs.framePr, !fp.isEmpty {
            // Детерминированный порядок: типичные атрибуты framePr первыми.
            let knownOrder = ["w:dropCap", "w:lines", "w:wrap", "w:vAnchor",
                              "w:hAnchor", "w:hSpace", "w:vSpace", "w:hRule",
                              "w:x", "w:y", "w:width", "w:height",
                              "w:xAlign", "w:yAlign", "w:anchorLock"]
            var fpS = "<w:framePr"
            var emitted: Set<String> = []
            for k in knownOrder {
                if let v = fp[k] { fpS += " \(k)=\"\(escapeXml(v))\""; emitted.insert(k) }
            }
            for k in fp.keys.sorted() where !emitted.contains(k) {
                fpS += " \(k)=\"\(escapeXml(fp[k]!))\""
            }
            fpS += "/>"
            s += fpS
        }
        switch attrs.alignment {
        case .left:    s += "<w:jc w:val=\"left\"/>"
        case .center:  s += "<w:jc w:val=\"center\"/>"
        case .right:   s += "<w:jc w:val=\"right\"/>"
        case .justify: s += "<w:jc w:val=\"both\"/>"
        }
        if attrs.leftIndent != 0 || attrs.rightIndent != 0 || attrs.firstLineIndent != 0 || attrs.hangingIndent != 0 {
            s += "<w:ind"
            if attrs.leftIndent      != 0 { s += " w:left=\"\(twips(attrs.leftIndent))\"" }
            if attrs.rightIndent     != 0 { s += " w:right=\"\(twips(attrs.rightIndent))\"" }
            // hanging и firstLine взаимоисключающие в OOXML — hanging приоритетнее.
            if attrs.hangingIndent   != 0 {
                s += " w:hanging=\"\(twips(attrs.hangingIndent))\""
            } else if attrs.firstLineIndent != 0 {
                s += " w:firstLine=\"\(twips(attrs.firstLineIndent))\""
            }
            s += "/>"
        }
        let m = attrs.lineSpacing.multiplier
        let hasSpacing = attrs.spaceBefore != 0 || attrs.spaceAfter != 0
        // v1.5.5: границы абзаца.
        if let b = attrs.border, !b.isEmpty {
            let sz = max(1, Int((b.width * 8).rounded()))
            let colorAttr = b.color.map { " w:color=\"\(String($0.hexString.dropFirst()))\"" } ?? ""
            s += "<w:pBdr>"
            if b.top    { s += "<w:top w:val=\"single\" w:sz=\"\(sz)\" w:space=\"1\"\(colorAttr)/>" }
            if b.left   { s += "<w:left w:val=\"single\" w:sz=\"\(sz)\" w:space=\"1\"\(colorAttr)/>" }
            if b.bottom { s += "<w:bottom w:val=\"single\" w:sz=\"\(sz)\" w:space=\"1\"\(colorAttr)/>" }
            if b.right  { s += "<w:right w:val=\"single\" w:sz=\"\(sz)\" w:space=\"1\"\(colorAttr)/>" }
            s += "</w:pBdr>"
        }
        // v1.5.4: пользовательские таб-стопы.
        if !attrs.tabStops.isEmpty {
            s += "<w:tabs>"
            for t in attrs.tabStops {
                let val: String
                switch t.alignment {
                case .center: val = "center"
                case .right:  val = "right"
                default:      val = "left"
                }
                s += "<w:tab w:val=\"\(val)\" w:pos=\"\(twips(t.position))\"/>"
            }
            s += "</w:tabs>"
        }
        if m != 1.15 || hasSpacing {
            s += "<w:spacing w:line=\"\(Int(m * 240))\" w:lineRule=\"auto\""
            if attrs.spaceBefore != 0 { s += " w:before=\"\(twips(attrs.spaceBefore))\"" }
            if attrs.spaceAfter  != 0 { s += " w:after=\"\(twips(attrs.spaceAfter))\"" }
            s += "/>"
        }
        if let li = attrs.listInfo, numId > 0 {
            s += "<w:numPr><w:ilvl w:val=\"\(li.level)\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"
        }
        s += "</w:pPr>"
        return s
    }

    /// Строит word/numbering.xml: по одному <w:abstractNum> (9 уровней, ilvl 0-8)
    /// на каждый непрерывный блок списка, плюс соответствующий <w:num>. Уровни
    /// используют РЕАЛЬНЫЕ форматы из документа; неиспользованные уровни
    /// заполняются по подходящему варианту многоуровневого списка (галерея
    /// MultilevelListVariant), чтобы углубление списка в OOXML-совместимых редакторах продолжало ряд.
    private func renderNumbering() -> String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        """
        let numIds = levelFormats.keys.sorted()
        for numId in numIds {
            s += "<w:abstractNum w:abstractNumId=\"\(numId)\">"
            for level in 0...8 {
                let indent = 720 + level * 360
                s += "<w:lvl w:ilvl=\"\(level)\">"
                let startVal = levelStarts[numId]?[level] ?? 1
                s += "<w:start w:val=\"\(startVal)\"/>"
                s += lvlFormatXml(for: numberingLevelFormat(numId: numId, level: level), level: level)
                s += "<w:pPr><w:ind w:left=\"\(indent)\" w:hanging=\"360\"/></w:pPr>"
                s += "</w:lvl>"
            }
            s += "</w:abstractNum>"
        }
        for numId in numIds {
            s += "<w:num w:numId=\"\(numId)\"><w:abstractNumId w:val=\"\(numId)\"/></w:num>"
        }
        s += "</w:numbering>"
        return s
    }

    /// Формат маркера для уровня abstractNum: сначала реальный формат из документа,
    /// затем формат по варианту галереи, согласующемуся со всеми известными уровнями
    /// блока, затем ближайший известный уровень.
    private func numberingLevelFormat(numId: Int, level: Int) -> DocxCore.ListFormatStyle {
        let known = levelFormats[numId] ?? [:]
        if let f = known[level] { return f }
        if let v = MultilevelListVariant.presets.first(where: { v in
            !known.isEmpty && known.allSatisfy { v.format(at: $0.key) == $0.value }
        }) {
            return v.format(at: level)
        }
        if let f = known.filter({ $0.key < level }).max(by: { $0.key < $1.key })?.value { return f }
        return known.min(by: { $0.key < $1.key })?.value ?? .bullet(character: "•")
    }

    /// <w:numFmt> + <w:lvlText> для формата на уровне: плейсхолдер счётчика — %N,
    /// где N = уровень + 1 (счётчик собственного уровня); составной формат
    /// (.decimalNested) перечисляет счётчики всех уровней: "%1.%2.%3.".
    private func lvlFormatXml(for style: DocxCore.ListFormatStyle, level: Int) -> String {
        let ph = "%\(level + 1)"
        switch style {
        case .bullet(let ch):        return "<w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\(escapeXml(ch))\"/>"
        case .decimal:               return "<w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"\(ph).\"/>"
        case .lowerLetter:           return "<w:numFmt w:val=\"lowerLetter\"/><w:lvlText w:val=\"\(ph).\"/>"
        case .upperLetter:           return "<w:numFmt w:val=\"upperLetter\"/><w:lvlText w:val=\"\(ph).\"/>"
        case .lowerRoman:            return "<w:numFmt w:val=\"lowerRoman\"/><w:lvlText w:val=\"\(ph).\"/>"
        case .upperRoman:            return "<w:numFmt w:val=\"upperRoman\"/><w:lvlText w:val=\"\(ph).\"/>"
        case .decimalEnclosedParen:  return "<w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"\(ph))\"/>"
        case .lowerLetterParen:      return "<w:numFmt w:val=\"lowerLetter\"/><w:lvlText w:val=\"\(ph))\"/>"
        case .lowerRomanParen:       return "<w:numFmt w:val=\"lowerRoman\"/><w:lvlText w:val=\"\(ph))\"/>"
        case .decimalNested:
            let text = (0...level).map { "%\($0 + 1)." }.joined()
            return "<w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"\(text)\"/>"
        }
    }

    private func renderRun(_ run: Run) -> String {
        // Inline-изображение (v0.1.53): `<w:r><w:drawing><wp:inline>...</wp:inline></w:drawing></w:r>`
        // со ссылкой на rId в document.xml.rels; сами байты — в word/media/imageN.ext.
        if run.image != nil {
            defer { currentImageRunIndex += 1 }
            guard let entryIdx = imagesByRunIndex[currentImageRunIndex],
                  entryIdx < imageEntries.count else { return "" }
            return renderInlineImage(entry: imageEntries[entryIdx], nvId: entryIdx + 1)
        }
        let a = run.attributes
        var rpr = "<w:rPr>"
        if let sid = a.styleId { rpr += "<w:rStyle w:val=\"\(escapeXml(sid))\"/>" }
        if let name = a.fontName { rpr += "<w:rFonts w:ascii=\"\(escapeXml(name))\" w:hAnsi=\"\(escapeXml(name))\"/>" }
        if let sz = a.fontSize   { rpr += "<w:sz w:val=\"\(Int(sz * 2))\"/><w:szCs w:val=\"\(Int(sz * 2))\"/>" }
        if a.bold         { rpr += "<w:b/><w:bCs/>" }
        if a.italic       { rpr += "<w:i/><w:iCs/>" }
        switch a.underline {
        case .none: break
        case .single: rpr += "<w:u w:val=\"single\"/>"
        case .double: rpr += "<w:u w:val=\"double\"/>"
        case .dotted: rpr += "<w:u w:val=\"dotted\"/>"
        case .dashed: rpr += "<w:u w:val=\"dash\"/>"
        }
        if a.strikethrough { rpr += "<w:strike/>" }
        if a.superscript  { rpr += "<w:vertAlign w:val=\"superscript\"/>" }
        if a.subscript    { rpr += "<w:vertAlign w:val=\"subscript\"/>" }
        if let c = a.textColor, let hex = hexFor(c) { rpr += "<w:color w:val=\"\(hex)\"/>" }
        // v0.1.82: цвет подсветки — пишем и как w:highlight (ближайший именованный,
        // для совместимости с мейнстрим-редакторов), и как w:shd (точный hex).
        if let hc = a.highlightColor, let hex = hexFor(hc) {
            let name = colorToHighlightName(hc)
            rpr += "<w:highlight w:val=\"\(name)\"/>"
            rpr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hex)\"/>"
        }
        // v0.5.8 (R08): track-changes ревизия атрибутов. Пишем ФАКТ ревизии
        // с пустым inner rPr — OOXML-читатель покажет балун с подписью автора/даты,
        // но без diff «было/стало» (задача R09/R10, см. Run.attributeRevision).
        if let rev = run.attributeRevision {
            let (author, date) = parseRevisionValue(rev)
            let id = nextRevisionId()
            rpr += "<w:rPrChange w:id=\"\(id)\" w:author=\"\(escapeXml(author))\" w:date=\"\(escapeXml(date))\"><w:rPr/></w:rPrChange>"
        }
        rpr += "</w:rPr>"
        // v0.4.7: DOCX track-changes. Для deletion текст пишется как
        // `<w:delText>`; вся структура рана оборачивается в `<w:ins>`/`<w:del>`.
        let textTag = run.deletion != nil ? "w:delText" : "w:t"
        // U+000C (Form Feed) — разрыв страницы → `<w:br w:type="page"/>` внутри
        // отдельного `<w:r>`. Разбиваем текст рана по FF на сегменты; между
        // сегментами вставляем break-раны.
        var body: String = {
            if run.text.contains("\u{000C}") {
                let parts = run.text.split(separator: "\u{000C}", omittingEmptySubsequences: false)
                var out = ""
                for (idx, part) in parts.enumerated() {
                    if !part.isEmpty {
                        let escaped = escapeXml(String(part))
                        let sp = (part.first == " " || part.last == " ") ? " xml:space=\"preserve\"" : ""
                        out += "<w:r>\(rpr)<\(textTag)\(sp)>\(escaped)</\(textTag)></w:r>"
                    }
                    if idx < parts.count - 1 {
                        out += "<w:r>\(rpr)<w:br w:type=\"page\"/></w:r>"
                    }
                }
                return out
            }
            let escaped = escapeXml(run.text)
            let spaceAttr = (run.text.hasPrefix(" ") || run.text.hasSuffix(" ")) ? " xml:space=\"preserve\"" : ""
            // v0.5.2 (R07): если ран несёт footnoteId, добавляем маркер сноски
            // ВНУТРИ w:r после w:t. Word ждёт ссылку в том же ране.
            let footnoteMarker: String
            if let fid = run.footnoteId {
                footnoteMarker = "<w:footnoteReference w:id=\"\(escapeXml(fid))\"/>"
            } else {
                footnoteMarker = ""
            }
            // v1.5.15: маркер концевой сноски (w:endnoteReference).
            let endnoteMarker: String
            if let eid = run.endnoteId {
                endnoteMarker = "<w:endnoteReference w:id=\"\(escapeXml(eid))\"/>"
            } else {
                endnoteMarker = ""
            }
            if run.text.isEmpty && !footnoteMarker.isEmpty && endnoteMarker.isEmpty {
                // Пустой ран только с footnoteRef — не пишем текст.
                return "<w:r>\(rpr)\(footnoteMarker)</w:r>"
            }
            if run.text.isEmpty && footnoteMarker.isEmpty && !endnoteMarker.isEmpty {
                return "<w:r>\(rpr)\(endnoteMarker)</w:r>"
            }
            return "<w:r>\(rpr)<\(textTag)\(spaceAttr)>\(escaped)</\(textTag)>\(footnoteMarker)\(endnoteMarker)</w:r>"
        }()
        // Оборачиваем в w:ins/w:del — по одному id на ран (упрощение MVP).
        if let ins = run.insertion {
            let (author, date) = parseRevisionValue(ins)
            let id = nextRevisionId()
            body = "<w:ins w:id=\"\(id)\" w:author=\"\(escapeXml(author))\" w:date=\"\(escapeXml(date))\">\(body)</w:ins>"
        } else if let del = run.deletion {
            let (author, date) = parseRevisionValue(del)
            let id = nextRevisionId()
            body = "<w:del w:id=\"\(id)\" w:author=\"\(escapeXml(author))\" w:date=\"\(escapeXml(date))\">\(body)</w:del>"
        }
        // v1.5.6: ран — начало результата сложного поля → оборачиваем в
        // fldChar begin/instrText/separate … end (поле остаётся «живым»).
        if let instr = run.fieldInstr, !instr.isEmpty {
            body = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
                 + "<w:r><w:instrText xml:space=\"preserve\"> \(escapeXml(instr)) </w:instrText></w:r>"
                 + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
                 + body
                 + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
        }
        return body
    }

    private var revisionCounter = 0
    private func nextRevisionId() -> Int {
        // v0.4.7: используем большой offset, чтобы не пересечься с w:comment w:id
        // (числовые, начинаются с 0). Ограничение: если commentNumIdById.count > 10000,
        // возможно пересечение — маловероятно для документа с > 10000 комментариев.
        defer { revisionCounter += 1 }
        return 10000 + revisionCounter
    }

    private func parseRevisionValue(_ s: String) -> (author: String, date: String) {
        // Формат: "author|iso-date|revId" (см. TrackChangesEngine).
        let parts = s.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let author = parts.count > 0 ? parts[0] : ""
        let date   = parts.count > 1 ? parts[1] : ISO8601DateFormatter().string(from: Date())
        return (author, date)
    }

    /// v0.5.6 (R07): true, если параграф целиком принадлежит блоку оглавления
    /// (хотя бы один непустой ран несёт `tocBlock` — маркер, поставленный
    /// `insertTableOfContents` через custom NSAttributedString-ключ).
    private func isTocParagraph(_ p: Paragraph) -> Bool {
        return p.runs.contains { $0.tocBlock != nil }
    }

    private func renderTable(_ t: TableBlock) -> String {
        var s = "<w:tbl>"
        // tblPr — именованный стиль (v1.5.17: из документа, default TableGrid) +
        // границы (v0.1.51).
        let styleId = t.style.namedStyleId ?? "TableGrid"
        var tblPr = "<w:tblStyle w:val=\"\(escapeXml(styleId))\"/><w:tblW w:w=\"0\" w:type=\"auto\"/>"
        if t.style.hasBorders {
            let borderColorHex = t.style.borderColor.flatMap { hexFor($0) } ?? "808080"
            // w:sz — в 1/8 pt units (Word convention): sz = pt * 8.
            let sz = max(2, Int((t.style.borderWidth * 8).rounded()))
            var borders = "<w:tblBorders>"
            for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                borders += "<w:\(edge) w:val=\"single\" w:sz=\"\(sz)\" w:space=\"0\" w:color=\"\(borderColorHex)\"/>"
            }
            borders += "</w:tblBorders>"
            tblPr += borders
        } else {
            var borders = "<w:tblBorders>"
            for edge in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                borders += "<w:\(edge) w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>"
            }
            borders += "</w:tblBorders>"
            tblPr += borders
        }
        // Выравнивание таблицы на странице (v0.1.70).
        switch t.alignment {
        case .left:   break // Default in Word, don't write.
        case .center: tblPr += "<w:jc w:val=\"center\"/>"
        case .right:  tblPr += "<w:jc w:val=\"right\"/>"
        }
        s += "<w:tblPr>\(tblPr)</w:tblPr>"
        // tblGrid — колонки: используем columnWidths, иначе — ширины первых ячеек, иначе fallback.
        let cols = max(t.columnWidths.count, t.rows.first?.cells.count ?? 1)
        s += "<w:tblGrid>"
        for i in 0..<cols {
            let ptWidth: CGFloat
            if i < t.columnWidths.count, t.columnWidths[i] > 0 {
                ptWidth = t.columnWidths[i]
            } else if let firstRow = t.rows.first, i < firstRow.cells.count,
                      let w = firstRow.cells[i].width, w > 0 {
                ptWidth = w
            } else {
                ptWidth = 100.0
            }
            let twips = Int((ptWidth * 20).rounded())
            s += "<w:gridCol w:w=\"\(twips)\"/>"
        }
        s += "</w:tblGrid>"
        // Vertical merge (v0.1.63): в модели ячейки-continue отсутствуют — есть только
        // ячейка-restart с rowSpan>1. При экспорте нужно вставить в rows ниже
        // continue-ячейки с `<w:vMerge/>` и пустым `<w:p/>`. Трекаем через
        // openMerge[gridCol] = сколько строк continue ещё осталось; ширины continue
        // берём из columnWidths (или fallback).
        let gridColumns = cols
        var openMerge: [Int] = Array(repeating: 0, count: max(gridColumns, 1))
        for row in t.rows {
            s += "<w:tr>"
            // v0.1.85: строка-заголовок таблицы — повторяется на каждой странице.
            // v0.1.86: высота строки — <w:trHeight w:val="…" w:hRule="atLeast"/> (twips = pt*20).
            let hasTrPr = row.isHeader || row.height != nil
            if hasTrPr {
                s += "<w:trPr>"
                if row.isHeader { s += "<w:tblHeader/>" }
                if let h = row.height, h > 0 {
                    let twips = Int((h * 20).rounded())
                    s += "<w:trHeight w:val=\"\(twips)\" w:hRule=\"atLeast\"/>"
                }
                s += "</w:trPr>"
            }
            var cellIter = row.cells.makeIterator()
            var gridCol = 0
            while gridCol < gridColumns {
                if gridCol < openMerge.count, openMerge[gridCol] > 0 {
                    let widthPt = gridCol < t.columnWidths.count ? t.columnWidths[gridCol] : 100.0
                    let twips = Int((widthPt * 20).rounded())
                    s += "<w:tc><w:tcPr><w:tcW w:w=\"\(twips)\" w:type=\"dxa\"/><w:vMerge/></w:tcPr><w:p/></w:tc>"
                    openMerge[gridCol] -= 1
                    gridCol += 1
                    continue
                }
                guard let cell = cellIter.next() else { break }
                let colSpan = max(1, cell.colSpan)
                let rowSpan = max(1, cell.rowSpan)
                var tcPr = ""
                let ptWidth: CGFloat
                if let w = cell.width, w > 0 {
                    ptWidth = w
                } else if gridCol < t.columnWidths.count, t.columnWidths[gridCol] > 0 {
                    ptWidth = t.columnWidths[gridCol]
                } else {
                    ptWidth = 100.0
                }
                let twips = Int((ptWidth * 20).rounded())
                tcPr += "<w:tcW w:w=\"\(twips)\" w:type=\"dxa\"/>"
                if colSpan > 1 {
                    tcPr += "<w:gridSpan w:val=\"\(colSpan)\"/>"
                }
                if rowSpan > 1 {
                    tcPr += "<w:vMerge w:val=\"restart\"/>"
                }
                if let bg = cell.backgroundColor, let hex = hexFor(bg) {
                    tcPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hex)\"/>"
                }
                // v1.5.17: вертикальный текст ячейки (round-trip).
                if let td = cell.textDirection, !td.isEmpty {
                    tcPr += "<w:textDirection w:val=\"\(escapeXml(td))\"/>"
                }
                s += "<w:tc><w:tcPr>\(tcPr)</w:tcPr>"
                for case let .paragraph(p) in cell.blocks { s += renderParagraph(p) }
                s += "</w:tc>"
                if rowSpan > 1 {
                    // Расширяем openMerge при необходимости.
                    while openMerge.count < gridCol + colSpan {
                        openMerge.append(0)
                    }
                    for gc in gridCol..<(gridCol + colSpan) {
                        openMerge[gc] = rowSpan - 1
                    }
                }
                gridCol += colSpan
            }
            s += "</w:tr>"
        }
        s += "</w:tbl>"
        return s
    }

    /// v0.4.5 (R06): содержимое `word/comments.xml`. Пишем треды в порядке
    /// `commentNumIdById`; каждый ответ — как отдельный параграф внутри
    /// того же `<w:comment>`, разделённый пустой строкой (MVP: Word стандартно
    /// пишет ответы как отдельные `<w:comment>` со ссылкой parentId; мы это
    /// пока не делаем — при open-in-Word ответы будут видны, но как продолжение).
    private func renderCommentsXml(_ threads: [CommentThread]) -> String {
        let iso = ISO8601DateFormatter()
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        """
        // Порядок = порядок присвоения w:id (commentNumIdById).
        let ordered = threads
            .filter { commentNumIdById[$0.id] != nil }
            .sorted { commentNumIdById[$0.id]! < commentNumIdById[$1.id]! }
        for thread in ordered {
            let num = commentNumIdById[thread.id]!
            let initials = commentInitials(from: thread.author)
            s += "\n  <w:comment w:id=\"\(num)\" w:author=\"\(escapeXml(thread.author))\" w:date=\"\(iso.string(from: thread.date))\" w:initials=\"\(escapeXml(initials))\">"
            s += renderCommentParagraph(thread.text)
            for reply in thread.replies {
                s += renderCommentParagraph("[\(reply.author)]: \(reply.text)")
            }
            s += "</w:comment>"
        }
        s += "\n</w:comments>\n"
        return s
    }

    // MARK: - Сноски (v0.5.2, R07)

    /// Собирает все `footnoteId`, реально используемые в теле документа.
    /// Осиротевшие сноски (в модели, но без якоря) в файл не пишутся.
    private func collectUsedFootnoteIds(_ document: DocumentModel) -> Set<String> {
        collectUsedNoteIds(document, endnotes: false)
    }

    /// v1.5.15: сбор id концевых сносок (endnoteId) — тот же обход.
    private func collectUsedEndnoteIds(_ document: DocumentModel) -> Set<String> {
        collectUsedNoteIds(document, endnotes: true)
    }

    private func collectUsedNoteIds(_ document: DocumentModel, endnotes: Bool) -> Set<String> {
        var ids: Set<String> = []
        for section in document.sections {
            for block in section.blocks {
                if case let .paragraph(p) = block {
                    for run in p.runs {
                        if let fid = endnotes ? run.endnoteId : run.footnoteId { ids.insert(fid) }
                    }
                } else if case let .table(t) = block {
                    for row in t.rows {
                        for cell in row.cells {
                            for b in cell.blocks {
                                if case let .paragraph(p) = b {
                                    for run in p.runs {
                                        if let fid = endnotes ? run.endnoteId : run.footnoteId { ids.insert(fid) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return ids
    }

    /// `word/footnotes.xml`: обязательные системные (id=-1 separator, 0 continuationSeparator)
    /// + пользовательские сноски. Текст каждой сноски — простой параграф.
    private func renderFootnotesXml(_ notes: [Footnote]) -> String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
        <w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
        """
        for n in notes {
            s += "\n<w:footnote w:id=\"\(escapeXml(n.id))\">"
            s += "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXml(n.text))</w:t></w:r></w:p>"
            s += "</w:footnote>"
        }
        s += "\n</w:footnotes>\n"
        return s
    }

    /// v1.5.15: `word/endnotes.xml` — системные separator/continuationSeparator
    /// + пользовательские концевые сноски. Структура зеркалит footnotes.xml.
    private func renderEndnotesXml(_ notes: [Footnote]) -> String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:endnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:endnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:endnote>
        <w:endnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:endnote>
        """
        for n in notes {
            s += "\n<w:endnote w:id=\"\(escapeXml(n.id))\">"
            s += "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXml(n.text))</w:t></w:r></w:p>"
            s += "</w:endnote>"
        }
        s += "\n</w:endnotes>\n"
        return s
    }

    private func renderCommentParagraph(_ text: String) -> String {
        return "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXml(text))</w:t></w:r></w:p>"
    }

    /// Первая буква имени + первая буква фамилии; если только одно слово —
    /// первая буква. Используется в `<w:comment w:initials>`.
    private func commentInitials(from author: String) -> String {
        let parts = author.split(separator: " ", omittingEmptySubsequences: true)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.prefix(2).joined().uppercased()
    }

    private func renderCoreProps(_ m: DocumentMetadata) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                           xmlns:dc="http://purl.org/dc/elements/1.1/"
                           xmlns:dcterms="http://purl.org/dc/terms/"
                           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapeXml(m.title))</dc:title>
          <dc:creator>\(escapeXml(m.author))</dc:creator>
          <dc:subject>\(escapeXml(m.subject))</dc:subject>
          <cp:keywords>\(escapeXml(m.keywords.joined(separator: ", ")))</cp:keywords>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(formatter.string(from: m.createdAt))</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(formatter.string(from: m.modifiedAt))</dcterms:modified>
          <dc:language>\(m.language)</dc:language>
        </cp:coreProperties>
        """
    }

    private func twips(_ pts: CGFloat) -> Int { Int(pts * 20) }

    /// EMU = pt * 12700 (Word convention). Точная константа: 914400 EMU per inch, 72 pt per inch.
    private func emu(_ pts: CGFloat) -> Int { Int((pts * 12700).rounded()) }

    /// Собирает `<w:r>` с `<w:drawing>` для одного inline-изображения.
    private func renderInlineImage(entry: ImageEntry, nvId: Int) -> String {
        let cx = emu(entry.widthPt)
        let cy = emu(entry.heightPt)
        let descrAttr: String = {
            guard let alt = entry.altText, !alt.isEmpty else { return "" }
            return " descr=\"\(escapeXml(alt))\" title=\"\(escapeXml(alt))\""
        }()

        let graphic = """
        <a:graphic>\
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic>\
        <pic:nvPicPr>\
        <pic:cNvPr id="\(nvId)" name="\(entry.filename)"/>\
        <pic:cNvPicPr/>\
        </pic:nvPicPr>\
        <pic:blipFill>\
        <a:blip r:embed="\(entry.rId)"/>\
        <a:stretch><a:fillRect/></a:stretch>\
        </pic:blipFill>\
        <pic:spPr>\
        <a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>\
        </pic:spPr>\
        </pic:pic>\
        </a:graphicData>\
        </a:graphic>
        """

        // v0.1.102: не-inline режимы → `<wp:anchor>` c нужным wrapMode.
        // v1.5.12: реальные posOffset (позиция от колонки/абзаца) — редактор
        // рендерит плавающие картинки и даёт их двигать мышью.
        if entry.wrap != .inline {
            let offX = entry.anchorXEMU ?? 0
            let offY = entry.anchorYEMU ?? 0
            let wrapEl: String = {
                switch entry.wrap {
                case .square:        return "<wp:wrapSquare wrapText=\"bothSides\"/>"
                case .tight:         return "<wp:wrapTight wrapText=\"bothSides\"><wp:wrapPolygon edited=\"0\"><wp:start x=\"0\" y=\"0\"/><wp:lineTo x=\"21600\" y=\"0\"/><wp:lineTo x=\"21600\" y=\"21600\"/><wp:lineTo x=\"0\" y=\"21600\"/><wp:lineTo x=\"0\" y=\"0\"/></wp:wrapPolygon></wp:wrapTight>"
                case .topAndBottom:  return "<wp:wrapTopAndBottom/>"
                case .behindText:    return "<wp:wrapNone/>"
                case .inFrontOfText: return "<wp:wrapNone/>"
                case .inline:        return ""
                }
            }()
            let behind = entry.wrap == .behindText ? "1" : "0"
            return """
            <w:r><w:drawing>\
            <wp:anchor distT="0" distB="0" distL="114300" distR="114300" simplePos="0" relativeHeight="0" behindDoc="\(behind)" locked="0" layoutInCell="1" allowOverlap="1">\
            <wp:simplePos x="0" y="0"/>\
            <wp:positionH relativeFrom="column"><wp:posOffset>\(offX)</wp:posOffset></wp:positionH>\
            <wp:positionV relativeFrom="paragraph"><wp:posOffset>\(offY)</wp:posOffset></wp:positionV>\
            <wp:extent cx="\(cx)" cy="\(cy)"/>\
            <wp:effectExtent l="0" t="0" r="0" b="0"/>\
            \(wrapEl)\
            <wp:docPr id="\(nvId)" name="Picture \(nvId)"\(descrAttr)/>\
            \(graphic)\
            </wp:anchor>\
            </w:drawing></w:r>
            """
        }

        return """
        <w:r><w:drawing>\
        <wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(nvId)" name="Picture \(nvId)"\(descrAttr)/>\
        \(graphic)\
        </wp:inline>\
        </w:drawing></w:r>
        """
    }

    /// Ближайший именованный highlight-цвет мейнстрим-редакторов к произвольному RGB.
    /// Word поддерживает фиксированный набор: yellow/green/cyan/magenta/blue/red/
    /// darkYellow/…/black/white/darkGray/lightGray/none.
    private func colorToHighlightName(_ c: CodableColor) -> String {
        let palette: [(String, Double, Double, Double)] = [
            ("yellow", 1, 1, 0), ("green", 0, 1, 0), ("cyan", 0, 1, 1),
            ("magenta", 1, 0, 1), ("blue", 0, 0, 1), ("red", 1, 0, 0),
            ("darkYellow", 0.5, 0.5, 0), ("darkGreen", 0, 0.5, 0),
            ("darkCyan", 0, 0.5, 0.5), ("darkMagenta", 0.5, 0, 0.5),
            ("darkBlue", 0, 0, 0.5), ("darkRed", 0.5, 0, 0),
            ("black", 0, 0, 0), ("white", 1, 1, 1),
            ("darkGray", 0.5, 0.5, 0.5), ("lightGray", 0.75, 0.75, 0.75),
        ]
        var best = ("yellow", Double.infinity)
        for (name, r, g, b) in palette {
            let d = pow(r - Double(c.red), 2) + pow(g - Double(c.green), 2) + pow(b - Double(c.blue), 2)
            if d < best.1 { best = (name, d) }
        }
        return best.0
    }

    private func hexFor(_ color: CodableColor) -> String? {
        let r = Int((color.red   * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue  * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func escapeXml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private var contentTypesXml: String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        """
        // Default для расширений изображений (уникальные) — включая media,
        // сохранённые passthrough из колонтитулов (v1.5.1).
        var seenExts: Set<String> = []
        for e in imageEntries where !seenExts.contains(e.ext) {
            seenExts.insert(e.ext)
            s += "\n  <Default Extension=\"\(e.ext)\" ContentType=\"\(e.contentType)\"/>"
        }
        let extContentType: [String: String] = [
            "png": "image/png", "jpeg": "image/jpeg", "jpg": "image/jpeg",
            "gif": "image/gif", "tiff": "image/tiff", "bmp": "image/bmp",
            "emf": "image/x-emf", "wmf": "image/x-wmf", "svg": "image/svg+xml",
        ]
        for part in preservedHF.values {
            for name in part.media.keys {
                let ext = (name as NSString).pathExtension.lowercased()
                guard !ext.isEmpty, !seenExts.contains(ext),
                      let ct = extContentType[ext] else { continue }
                seenExts.insert(ext)
                s += "\n  <Default Extension=\"\(ext)\" ContentType=\"\(ct)\"/>"
            }
        }
        s += """

          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        """
        if !levelFormats.isEmpty {
            s += "\n  <Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
        }
        if hasHeader {
            s += "\n  <Override PartName=\"/word/\(hfPartName("headerDefault", fallback: "header1.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if hasFirstHeader {
            s += "\n  <Override PartName=\"/word/\(hfPartName("headerFirst", fallback: "header2.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if hasEvenHeader {
            s += "\n  <Override PartName=\"/word/\(hfPartName("headerEven", fallback: "header3.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>"
        }
        if hasFooter {
            s += "\n  <Override PartName=\"/word/\(hfPartName("footerDefault", fallback: "footer1.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        if hasFirstFooter {
            s += "\n  <Override PartName=\"/word/\(hfPartName("footerFirst", fallback: "footer2.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        if hasEvenFooter {
            s += "\n  <Override PartName=\"/word/\(hfPartName("footerEven", fallback: "footer3.xml"))\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>"
        }
        if hasSettingsXml {
            s += "\n  <Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>"
        }
        // v1.5.2: Override для passthrough-частей (customXml, theme, fontTable…)
        // — их Content-Type из исходного [Content_Types].xml.
        for key in preservedExtra.keys.sorted() {
            guard let ct = preservedCT[key] else { continue }
            s += "\n  <Override PartName=\"/\(key)\" ContentType=\"\(ct)\"/>"
        }
        if !commentNumIdById.isEmpty {
            s += "\n  <Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/>"
        }
        if hasFootnotes {
            s += "\n  <Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/>"
        }
        if hasEndnotes {
            s += "\n  <Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/>"
        }
        s += "\n</Types>\n"
        return s
    }

    private var rootRelsXml: String { """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        </Relationships>
        """ }

    private var documentRelsXml: String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        if !levelFormats.isEmpty {
            s += "\n  <Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        }
        if hasHeader {
            s += "\n  <Relationship Id=\"rIdHdr1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(hfPartName("headerDefault", fallback: "header1.xml"))\"/>"
        }
        if hasFirstHeader {
            s += "\n  <Relationship Id=\"rIdHdr2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(hfPartName("headerFirst", fallback: "header2.xml"))\"/>"
        }
        if hasEvenHeader {
            s += "\n  <Relationship Id=\"rIdHdr3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"\(hfPartName("headerEven", fallback: "header3.xml"))\"/>"
        }
        if hasFooter {
            s += "\n  <Relationship Id=\"rIdFtr1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(hfPartName("footerDefault", fallback: "footer1.xml"))\"/>"
        }
        if hasFirstFooter {
            s += "\n  <Relationship Id=\"rIdFtr2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(hfPartName("footerFirst", fallback: "footer2.xml"))\"/>"
        }
        if hasEvenFooter {
            s += "\n  <Relationship Id=\"rIdFtr3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"\(hfPartName("footerEven", fallback: "footer3.xml"))\"/>"
        }
        for e in imageEntries {
            s += "\n  <Relationship Id=\"\(e.rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(e.filename)\"/>"
        }
        if !commentNumIdById.isEmpty {
            s += "\n  <Relationship Id=\"rIdComments\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"comments.xml\"/>"
        }
        if hasFootnotes {
            s += "\n  <Relationship Id=\"rIdFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>"
        }
        if hasEndnotes {
            s += "\n  <Relationship Id=\"rIdEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>"
        }
        // Гиперссылки (v0.1.54) — сортируем по rId для детерминированного вывода.
        for (url, rId) in hyperlinkRIdByUrl.sorted(by: { $0.value < $1.value }) {
            s += "\n  <Relationship Id=\"\(rId)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escapeXml(url))\" TargetMode=\"External\"/>"
        }
        s += "\n</Relationships>\n"
        return s
    }

    private var stylesXml: String {
        var s = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
                <w:sz w:val="24"/>
              </w:rPr>
            </w:rPrDefault>
          </w:docDefaults>

        """
        // Стандартные стили — всегда (override из документа ?? дефолт).
        let standardParaIds = Set(StandardParagraphStyle.all.map(\.id))
        let standardCharIds = Set(StandardCharacterStyle.all.map(\.id))
        for style in StandardParagraphStyle.all {
            let def = paragraphOverrides[style.id] ?? style.def
            s += renderStyleDef(id: style.id, def: def)
        }
        for cstyle in StandardCharacterStyle.all {
            let def = characterOverrides[cstyle.id] ?? cstyle.def
            s += renderCharStyleDef(id: cstyle.id, def: def)
        }
        // Пользовательские стили внешних .docx (не входящие в стандартный набор).
        // Сортируем id для детерминированного вывода.
        for id in paragraphOverrides.keys.sorted() where !standardParaIds.contains(id) {
            s += renderStyleDef(id: id, def: paragraphOverrides[id]!)
        }
        for id in characterOverrides.keys.sorted() where !standardCharIds.contains(id) {
            s += renderCharStyleDef(id: id, def: characterOverrides[id]!)
        }
        // v0.4.5 (R06): CommentReference — символьный стиль для маркера
        // `<w:commentReference>`. Пишем только если в документе есть комментарии.
        if !commentNumIdById.isEmpty {
            s += "<w:style w:type=\"character\" w:styleId=\"CommentReference\">"
            s += "<w:name w:val=\"Comment Reference\"/>"
            s += "<w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr>"
            s += "</w:style>"
        }
        // v1.5.17: определения стилей таблиц из исходного styles.xml —
        // passthrough (мы их не рендерим, но Word/LibreOffice применит).
        if let ts = preservedTableStylesXml, !ts.isEmpty {
            s += ts
        }
        s += "</w:styles>"
        return s
    }

    /// Строит `<w:style w:type="character">` для символьного стиля (Strong/Emphasis/Code).
    private func renderCharStyleDef(id: String, def: CharacterStyleDef) -> String {
        var s = "<w:style w:type=\"character\" w:styleId=\"\(id)\">"
        s += "<w:name w:val=\"\(escapeXml(def.name))\"/>"
        s += "<w:basedOn w:val=\"DefaultParagraphFont\"/>"
        var rPr = ""
        if let font = def.fontName { rPr += "<w:rFonts w:ascii=\"\(escapeXml(font))\" w:hAnsi=\"\(escapeXml(font))\"/>" }
        if let sz   = def.fontSize { rPr += "<w:sz w:val=\"\(Int(sz * 2))\"/><w:szCs w:val=\"\(Int(sz * 2))\"/>" }
        if def.bold   { rPr += "<w:b/><w:bCs/>" }
        if def.italic { rPr += "<w:i/><w:iCs/>" }
        if !rPr.isEmpty { s += "<w:rPr>\(rPr)</w:rPr>" }
        s += "</w:style>\n"
        return s
    }

    /// Строит `<w:style>` для одного стандартного стиля абзаца.
    private func renderStyleDef(id: String, def: ParagraphStyleDef) -> String {
        var s = "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\""
        if id == "Normal" { s += " w:default=\"1\"" }
        s += ">"
        s += "<w:name w:val=\"\(escapeXml(def.name))\"/>"
        if let base = def.basedOn { s += "<w:basedOn w:val=\"\(base)\"/>" }
        if let next = id == "Normal" ? nil : "Normal" { s += "<w:next w:val=\"\(next)\"/>" }
        // pPr — интервалы + outlineLvl
        var pPr = ""
        let hasSpacing = def.spaceBefore != nil || def.spaceAfter != nil
        if hasSpacing {
            pPr += "<w:spacing"
            if let sb = def.spaceBefore { pPr += " w:before=\"\(twips(sb))\"" }
            if let sa = def.spaceAfter  { pPr += " w:after=\"\(twips(sa))\"" }
            pPr += "/>"
        }
        if let al = def.alignment {
            let jc: String
            switch al {
            case .left:    jc = "left"
            case .center:  jc = "center"
            case .right:   jc = "right"
            case .justify: jc = "both"
            }
            pPr += "<w:jc w:val=\"\(jc)\"/>"
        }
        if let lvl = def.outlineLevel { pPr += "<w:outlineLvl w:val=\"\(lvl)\"/>" }
        if !pPr.isEmpty { s += "<w:pPr>\(pPr)</w:pPr>" }
        // rPr — шрифт + размер + начертание + цвет + заливка
        var rPr = ""
        if let font = def.fontName { rPr += "<w:rFonts w:ascii=\"\(escapeXml(font))\" w:hAnsi=\"\(escapeXml(font))\" w:cs=\"\(escapeXml(font))\"/>" }
        if let sz = def.fontSize { rPr += "<w:sz w:val=\"\(Int(sz * 2))\"/><w:szCs w:val=\"\(Int(sz * 2))\"/>" }
        if def.bold == true      { rPr += "<w:b/><w:bCs/>" }
        if def.italic == true    { rPr += "<w:i/><w:iCs/>" }
        if let c = def.textColor, let hex = hexFor(c) { rPr += "<w:color w:val=\"\(hex)\"/>" }
        if let bg = def.backgroundColor, let hex = hexFor(bg) { rPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hex)\"/>" }
        if !rPr.isEmpty { s += "<w:rPr>\(rPr)</w:rPr>" }
        s += "</w:style>\n"
        return s
    }
}
