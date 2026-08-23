//
//  DocxIO.swift
//  DocxIO
//
//  Импорт/экспорт DOCX (Office Open XML) для DocxEdit.
//
//  v0.1.2: добавлен парсинг styles.xml (docDefaults + named styles + basedOn),
//          отслеживание <w:t>, применение NSParagraphStyle через ParagraphAttributes.
//

import Foundation
import ZIPFoundation
import DocxCore

public enum DocxIO {

    // MARK: - Импорт

    public static func importDocx(data: Data) throws -> DocumentModel {
        try importDocxWithReport(data: data).0
    }

    public static func importDocx(url: URL) throws -> DocumentModel {
        try importDocxWithReport(url: url).0
    }

    /// v0.1.56: расширенный вариант — возвращает вместе с моделью отчёт о том,
    /// что не удалось полноценно импортировать (сложные поля, VML/OLE, floating).
    public static func importDocxWithReport(data: Data) throws -> (DocumentModel, ImportReport) {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw DocumentError.invalidDocument(
                "Не удалось открыть DOCX как ZIP: \(error.localizedDescription)"
            )
        }
        return try importDocx(archive: archive)
    }

    public static func importDocxWithReport(url: URL) throws -> (DocumentModel, ImportReport) {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw DocumentError.ioError(
                "Не удалось открыть файл \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        return try importDocx(archive: archive)
    }

    private static func importDocx(archive: Archive) throws -> (DocumentModel, ImportReport) {
        var documentXml: Data?
        var stylesXml: Data?
        var corePropsXml: Data?
        var numberingXml: Data?
        var settingsXml: Data?
        var commentsXml: Data?
        var footnotesXml: Data?
        var endnotesXml: Data?
        var documentRelsXml: Data?
        // v1.5.2: исходный [Content_Types].xml — для ContentType preserved-частей.
        var contentTypesData: Data?
        // v1.5.2: неизвестные/неперегенерируемые части — lossless passthrough.
        var preservedParts: [String: Data] = [:]
        // v0.4.1: все части колонтитулов по точному имени — раньше брался ПЕРВЫЙ
        // попавшийся word/header*.xml в порядке обхода ZIP (недетерминированном),
        // из-за чего колонтитул первой страницы (header2.xml) мог импортироваться
        // как основной. Ключ — имя файла (header1.xml, footer2.xml, …).
        var headerParts: [String: Data] = [:]
        var footerParts: [String: Data] = [:]
        // v1.5.1: rels частей колонтитулов (word/_rels/headerN.xml.rels),
        // ключ — имя части ("headerN.xml").
        var hfRelsParts: [String: Data] = [:]
        // v0.1.53: media (изображения) — ключ = имя файла без префикса word/media/.
        var mediaFiles: [String: Data] = [:]

        for entry in archive {
            let path = entry.path
            var buffer = Data()
            _ = try? archive.extract(entry) { chunk in buffer.append(chunk) }
            switch path {
            case "word/document.xml":            documentXml     = buffer
            case "word/styles.xml":              stylesXml       = buffer
            case "docProps/core.xml":            corePropsXml    = buffer
            case "word/numbering.xml":           numberingXml    = buffer
            case "word/settings.xml":            settingsXml     = buffer
            case "word/comments.xml":            commentsXml     = buffer
            case "word/footnotes.xml":           footnotesXml    = buffer
            case "word/endnotes.xml":
                endnotesXml = buffer
                // v1.5.15: копия остаётся в preservedParts — если в теле нет
                // ни одной живой ссылки (writer не сгенерирует свою часть),
                // оригинал переживает round-trip как раньше (v1.5.2).
                preservedParts["word/endnotes.xml"] = buffer
            case "word/_rels/document.xml.rels": documentRelsXml = buffer
            case "[Content_Types].xml":          contentTypesData = buffer
            case "_rels/.rels":
                // Корневые rels — регенерируем; но вложенные пакеты (если
                // упоминаются нестандартные части) покрываются preservedParts
                // через Content_Types. Сам файл не сохраняем.
                continue
            default:
                if path.hasPrefix("word/media/") {
                    let name = String(path.dropFirst("word/media/".count))
                    mediaFiles[name] = buffer
                    continue
                }
                // v1.5.1: rels частей колонтитулов (word/_rels/headerN.xml.rels) —
                // ключ = имя части ("headerN.xml"). Нужны для passthrough media.
                if path.hasPrefix("word/_rels/"), path.hasSuffix(".xml.rels"),
                   path.contains("header") || path.contains("footer") {
                    let part = String(path.dropFirst("word/_rels/".count).dropLast(".rels".count))
                    hfRelsParts[part] = buffer
                    continue
                }
                if path.hasPrefix("word/header"), path.hasSuffix(".xml") {
                    headerParts[String(path.dropFirst("word/".count))] = buffer
                } else if path.hasPrefix("word/footer"), path.hasSuffix(".xml") {
                    footerParts[String(path.dropFirst("word/".count))] = buffer
                } else if !path.hasSuffix("/") {
                    // v1.5.2: всё остальное (customXml/*, word/theme/*,
                    // word/fontTable.xml, word/webSettings.xml, word/endnotes.xml,
                    // docProps/app.xml, …) — lossless passthrough при экспорте.
                    preservedParts[path] = buffer
                }
            }
        }

        guard let documentXml else {
            throw DocumentError.invalidDocument("В архиве DOCX отсутствует word/document.xml")
        }

        // Парсим стили (если есть).
        var defaultRunProps = RunProps()
        var styleTable: [String: StyleDef] = [:]
        if let stylesXml {
            let stylesParser = OoxmlStylesParser()
            stylesParser.parse(data: stylesXml)
            defaultRunProps = stylesParser.defaultRunProps
            styleTable = stylesParser.resolvedStyles()
        }

        // Парсим numbering.xml (если есть) — маппинг numId/ilvl → тип/стиль списка.
        var numberingParser: NumberingXmlParser? = nil
        if let numberingXml {
            let np = NumberingXmlParser()
            np.parse(data: numberingXml)
            numberingParser = np
        }

        // v0.1.53: mapping rId → target для изображений.
        var relsMap: [String: String] = [:]
        if let documentRelsXml {
            let rp = DocumentRelsParser()
            rp.parse(data: documentRelsXml)
            relsMap = rp.map
        }
        let parser = OoxmlDocumentParser(
            defaultRunProps: defaultRunProps,
            styleTable: styleTable,
            numbering: numberingParser,
            imagesRels: relsMap,
            mediaFiles: mediaFiles
        )
        var model = try parser.parse(
            documentXml: documentXml,
            corePropsXml: corePropsXml
        )
        // Импортируем override стандартных стилей из styles.xml в model.styles.
        // (Раньше styleTable читался только для рендера runProps ранов; сами
        // определения стилей терялись, и диалог «Стили…» после re-open показывал
        // дефолты — фидбек #1 пользователя после v0.1.38.)
        model.styles = buildDocumentStyles(from: styleTable, defaultRunProps: defaultRunProps)
        // Колонтитулы — v1.5.1 (DESIGN_HEADER_FOOTER.md):
        // 1. Слоты резолвятся через document.xml.rels + headerReference/footerReference
        //    в document.xml (раньше — по имени файла: header1=default, header2=first,
        //    header3=even — на сторонних файлах слоты ПЕРЕПУТЫВАЛИСЬ, напр. в файле
        //    с header1=even/header2=default/header3=first). Fallback — конвенция имён.
        // 2. Сырые байты частей (+ их rels + media) сохраняются в
        //    model.preservedHeaderFooter — lossless passthrough при экспорте,
        //    если колонтитул не редактировался (графика/текстбоксы/рамки больше
        //    не отрезаются при open→save).
        // 3. Сложное содержимое (drawing/pict/txbx/tbl/pBdr/tabs) — записи в
        //    ImportReport (раньше отбрасывалось молча).
        var hf = HeaderFooter()
        let parsePart = { (data: Data) -> (String, DocxCore.TextAlignment) in
            let p = HeaderFooterPartParser(); p.parse(data: data)
            return (p.text, p.alignment)
        }
        let slotByPart = resolveHFSlots(documentXml: documentXml, relsMap: relsMap,
                                        headerParts: headerParts, footerParts: footerParts)
        var preservedHF: [String: PreservedHFPart] = [:]
        for (slot, partName) in slotByPart {
            guard let xml = headerParts[partName] ?? footerParts[partName] else { continue }
            let (text, align) = parsePart(xml)
            switch slot {
            case "headerDefault": (hf.headerText, hf.headerAlignment) = (text, align)
            case "footerDefault": (hf.footerText, hf.footerAlignment) = (text, align)
            case "headerFirst":   (hf.firstHeaderText, hf.firstHeaderAlignment) = (text, align)
            case "footerFirst":   (hf.firstFooterText, hf.firstFooterAlignment) = (text, align)
            case "headerEven":    (hf.evenHeaderText, hf.evenHeaderAlignment) = (text, align)
            case "footerEven":    (hf.evenFooterText, hf.evenFooterAlignment) = (text, align)
            default: break
            }
            // Passthrough-часть: rels с переписанными target'ами media
            // (hfp_<slot>_<name> — во избежание коллизий с генерируемыми imageN).
            var relsOut: Data? = nil
            var media: [String: Data] = [:]
            // rId → оригинальное имя media (для резолва картинок v1.5.3).
            var mediaByRId: [String: String] = [:]
            if let rd = hfRelsParts[partName], var s = String(data: rd, encoding: .utf8) {
                if let relRx = try? NSRegularExpression(
                    pattern: #"Id="([^"]+)"[^>]*Target="media/([^"]+)""#) {
                    for m in relRx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                        guard let idR = Range(m.range(at: 1), in: s),
                              let tR = Range(m.range(at: 2), in: s) else { continue }
                        mediaByRId[String(s[idR])] = String(s[tR])
                    }
                }
                if let rx = try? NSRegularExpression(pattern: #"Target="media/([^"]+)""#) {
                    let matches = rx.matches(in: s, range: NSRange(s.startIndex..., in: s))
                    for m in matches {
                        guard let r = Range(m.range(at: 1), in: s) else { continue }
                        let orig = String(s[r])
                        let newName = "hfp_\(slot)_\(orig)"
                        if let bytes = mediaFiles[orig] {
                            media[newName] = bytes
                            s = s.replacingOccurrences(of: "media/\(orig)", with: "media/\(newName)")
                        }
                    }
                }
                relsOut = Data(s.utf8)
            }
            // v1.5.3: плавающие изображения (wp:anchor) — позиции для отрисовки
            // колонтитула в редакторе. x — от колонки текста, y — от абзаца.
            var images: [HFImage] = []
            if let doc = String(data: xml, encoding: .utf8),
               let drawRx = try? NSRegularExpression(
                   pattern: #"<w:drawing>.*?</w:drawing>"#, options: [.dotMatchesLineSeparators]) {
                for dm in drawRx.matches(in: doc, range: NSRange(doc.startIndex..., in: doc)) {
                    guard let dr = Range(dm.range, in: doc) else { continue }
                    let d = String(doc[dr])
                    guard d.contains("<wp:anchor"), d.contains("<a:blip") else { continue }
                    func intAfter(_ pat: String) -> Int? {
                        guard let rx = try? NSRegularExpression(pattern: pat),
                              let mm = rx.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)),
                              let rr = Range(mm.range(at: 1), in: d) else { return nil }
                        return Int(d[rr])
                    }
                    func strAfter(_ pat: String) -> String? {
                        guard let rx = try? NSRegularExpression(pattern: pat),
                              let mm = rx.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)),
                              let rr = Range(mm.range(at: 1), in: d) else { return nil }
                        return String(d[rr])
                    }
                    guard let cx = intAfter(#"<wp:extent cx="(\d+)""#),
                          let cy = intAfter(#"cy="(\d+)""#),
                          let embed = strAfter(#"r:embed="([^"]+)""#),
                          let origName = mediaByRId[embed],
                          media["hfp_\(slot)_\(origName)"] != nil else { continue }
                    images.append(HFImage(
                        mediaName: "hfp_\(slot)_\(origName)",
                        xEMU: intAfter(#"<wp:positionH[^>]*>\s*<wp:posOffset>(-?\d+)<"#) ?? 0,
                        yEMU: intAfter(#"<wp:positionV[^>]*>\s*<wp:posOffset>(-?\d+)<"#) ?? 0,
                        cxEMU: cx, cyEMU: cy))
                }
            }
            // v1.5.14: водяные знаки — VML `<w:pict>` с `v:textpath` (WordArt,
            // повёрнутый серый текст) или `v:imagedata` (картинка-подложка).
            // Перед сканированием вырезаем mc:Fallback-участки (в 133.docx
            // fallback несёт VML-дубли wps-шейпов — не водяные знаки).
            var watermarks: [HFWatermark] = []
            if let rawXml = String(data: xml, encoding: .utf8) {
                let doc = rawXml.replacingOccurrences(
                    of: #"<mc:Fallback>.*?</mc:Fallback>"#, with: "",
                    options: .regularExpression)
                if let pictRx = try? NSRegularExpression(
                    pattern: #"<w:pict>.*?</w:pict>"#, options: [.dotMatchesLineSeparators]) {
                for pm in pictRx.matches(in: doc, range: NSRange(doc.startIndex..., in: doc)) {
                    guard let pr = Range(pm.range, in: doc) else { continue }
                    let d = String(doc[pr])
                    func strAfter(_ pat: String) -> String? {
                        guard let rx = try? NSRegularExpression(pattern: pat),
                              let mm = rx.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)),
                              let rr = Range(mm.range(at: 1), in: d) else { return nil }
                        return String(d[rr])
                    }
                    func ptAfter(_ name: String) -> CGFloat {
                        strAfter(name + #":(-?[\d.]+)pt"#).flatMap(Double.init).map { CGFloat($0) } ?? 0
                    }
                    let x = ptAfter("margin-left")
                    let y = ptAfter("margin-top")
                    let w = ptAfter("width")
                    let h = ptAfter("height")
                    let rot = strAfter(#"rotation:(-?[\d.]+)"#).flatMap(Double.init).map { CGFloat($0) } ?? 0
                    let color = strAfter(#"fillcolor="(#[0-9A-Fa-f]{6})""#)
                    if let text = strAfter(#"<v:textpath[^>]*string="([^"]*)""#), !text.isEmpty {
                        watermarks.append(HFWatermark(text: text, xPt: x, yPt: y,
                                                      wPt: w, hPt: h, rotation: rot,
                                                      colorHex: color))
                    } else if let rid = strAfter(#"<v:imagedata[^>]*r:id="([^"]+)""#),
                              let origName = mediaByRId[rid],
                              media["hfp_\(slot)_\(origName)"] != nil {
                        watermarks.append(HFWatermark(mediaName: "hfp_\(slot)_\(origName)",
                                                      xPt: x, yPt: y, wPt: w, hPt: h,
                                                      rotation: rot, colorHex: nil))
                    }
                }
                }
            }
            preservedHF[slot] = PreservedHFPart(partName: partName, xml: xml,
                                                relsXml: relsOut, media: media,
                                                images: images,
                                                watermarks: watermarks)
        }
        // Флаги режимов — ТОЛЬКО из авторитетных источников (раньше
        // выставлялись по наличию части: рисовали even-колонтитул там, где
        // Word его не показывает, и при экспорте писали лишний
        // <w:evenAndOddHeaders/> в settings.xml).
        if let docStr = String(data: documentXml, encoding: .utf8),
           docStr.contains("<w:titlePg/>") || docStr.contains("<w:titlePg ") {
            hf.differentFirstPage = true
        }
        if let settingsXml, let s = String(data: settingsXml, encoding: .utf8),
           s.contains("<w:evenAndOddHeaders/>") {
            hf.differentOddEven = true
        }
        // ...но если части first/even есть, а флага нет (наш writer до v1.5.1
        // не писал флаги при пустых текстах) — для round-trip своих файлов
        // ориентируемся на наличие НЕПУСТОГО текста в слоте.
        if !hf.differentFirstPage,
           !(hf.firstHeaderText.isEmpty && hf.firstFooterText.isEmpty) {
            hf.differentFirstPage = true
        }
        model.headerFooter = hf
        model.preservedHeaderFooter = preservedHF
        // v1.5.2: passthrough неизвестных частей + их Content-Type из исходного
        // [Content_Types].xml (иначе пакет невалиден). settings.xml хранится
        // отдельно (при экспорте в него может инжектиться evenAndOddHeaders).
        model.preservedSettingsXml = settingsXml
        var ctMap: [String: String] = [:]
        if let ctd = contentTypesData, let cts = String(data: ctd, encoding: .utf8),
           let rx = try? NSRegularExpression(
               pattern: #"<Override PartName="/([^"]+)" ContentType="([^"]+)""#) {
            for m in rx.matches(in: cts, range: NSRange(cts.startIndex..., in: cts)) {
                guard let p = Range(m.range(at: 1), in: cts),
                      let t = Range(m.range(at: 2), in: cts) else { continue }
                ctMap[String(cts[p])] = String(cts[t])
            }
        }
        model.preservedParts = preservedParts
        model.preservedContentTypes = preservedParts.keys.reduce(into: [:]) { acc, key in
            if let ct = ctMap[key] { acc[key] = ct }
        }
        // v1.5.4: неизвестные дети <w:sectPr> (w:cols — колонки, w:docGrid,
        // w:vAlign, w:pgNumType, w:pgBorders, …) сохраняем сырым фрагментом и
        // инжектим при экспорте — вёрстка не теряется при open→save, хотя
        // редактор рендерит одну колонку.
        if let doc = String(data: documentXml, encoding: .utf8),
           let rx = try? NSRegularExpression(
               pattern: #"<w:sectPr[^>]*>(.*?)</w:sectPr>"#, options: [.dotMatchesLineSeparators]),
           let m = rx.matches(in: doc, range: NSRange(doc.startIndex..., in: doc)).last,
           let r = Range(m.range(at: 1), in: doc) {
            var extras = String(doc[r])
            for pat in [#"<w:headerReference[^>]*/>"#, #"<w:footerReference[^>]*/>"#,
                        #"<w:titlePg/>"#, #"<w:pgSz[^>]*/>"#, #"<w:pgMar[^>]*/>"#,
                        #"<w:mirrorMargins/>"#] {
                extras = extras.replacingOccurrences(of: pat, with: "",
                                                     options: .regularExpression)
            }
            extras = extras.trimmingCharacters(in: .whitespacesAndNewlines)
            model.preservedSectPrExtras = extras.isEmpty ? nil : extras
        }
        // v1.5.17: определения стилей таблиц — passthrough (сырые блоки
        // <w:style w:type="table">…</w:style> склеиваются и дописываются
        // при экспорте; наш генератор styles.xml их не умеет).
        if let stylesXml, let s = String(data: stylesXml, encoding: .utf8),
           let rx = try? NSRegularExpression(
               pattern: #"<w:style w:type="table".*?</w:style>"#,
               options: [.dotMatchesLineSeparators]) {
            let blocks = rx.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .compactMap { Range($0.range, in: s).map { String(s[$0]) } }
            if !blocks.isEmpty {
                model.preservedTableStylesXml = blocks.joined()
            }
        }
        // v0.4.5 (R06): комментарии — если есть comments.xml, парсим треды.
        // Runs уже получили `commentId` от OoxmlDocumentParser (значения = w:id
        // из commentRangeStart, в виде строки — совпадают с id, что мы кладём
        // в model.comments).
        if let commentsXml {
            let cp = CommentsXmlParser()
            cp.parse(data: commentsXml)
            model.comments = cp.threads
        }
        // v0.5.2 (R07): сноски. Runs получили footnoteId от OoxmlDocumentParser,
        // а тексты сносок — из word/footnotes.xml.
        if let footnotesXml {
            let fp = FootnotesXmlParser()
            fp.parse(data: footnotesXml)
            model.footnotes = fp.footnotes
        }
        // v1.5.15: концевые сноски — word/endnotes.xml (элементы w:endnote).
        if let endnotesXml {
            let ep = FootnotesXmlParser()
            ep.elementName = "w:endnote"
            ep.parse(data: endnotesXml)
            model.endnotes = ep.footnotes
        }
        var report = parser.buildReport().merging(hfReportEntries(preservedHF: preservedHF))
        // v1.6.4: ошибка XML — первой записью отчёта об открытии.
        if let parseError = parser.parseError {
            report.entries.insert(ImportReport.Entry(
                category: "Целостность документа",
                element: "XML parse error",
                count: 1,
                explanation: "Файл прочитан частично: ошибка XML — \(parseError.localizedDescription). Документ может быть обрезан; сохраните копию перед редактированием."),
                at: 0)
        }
        return (model, report)
    }

    /// v1.5.1: резолв слотов колонтитулов через document.xml.rels +
    /// headerReference/footerReference в document.xml. Возвращает
    /// slot → имя части ("header2.xml"). Fallback — конвенция имён нашего
    /// writer (header1=default, header2=first, header3=even).
    private static func resolveHFSlots(
        documentXml: Data,
        relsMap: [String: String],
        headerParts: [String: Data],
        footerParts: [String: Data]
    ) -> [String: String] {
        var result: [String: String] = [:]
        if let doc = String(data: documentXml, encoding: .utf8),
           let rx = try? NSRegularExpression(
               pattern: #"<w:(header|footer)Reference[^>]*w:type="(default|first|even)"[^>]*r:id="([^"]+)""#) {
            for m in rx.matches(in: doc, range: NSRange(doc.startIndex..., in: doc)) {
                guard let kindR = Range(m.range(at: 1), in: doc),
                      let typeR = Range(m.range(at: 2), in: doc),
                      let ridR  = Range(m.range(at: 3), in: doc) else { continue }
                let kind = doc[kindR] == "header" ? "header" : "footer"
                let type = String(doc[typeR])  // default / first / even
                let rid  = String(doc[ridR])
                guard let target = relsMap[rid] else { continue }
                // target относительно word/ — "header2.xml".
                let slot = kind + type.prefix(1).uppercased() + String(type.dropFirst())
                result[slot] = target
            }
        }
        // Fallback: добиваем отсутствующие слоты конвенцией имён (наши файлы).
        let fallback: [(String, String, [String: Data])] = [
            ("headerDefault", "header1.xml", headerParts),
            ("headerFirst",   "header2.xml", headerParts),
            ("headerEven",    "header3.xml", headerParts),
            ("footerDefault", "footer1.xml", footerParts),
            ("footerFirst",   "footer2.xml", footerParts),
            ("footerEven",    "footer3.xml", footerParts),
        ]
        for (slot, name, dict) in fallback where result[slot] == nil && dict[name] != nil {
            result[slot] = name
        }
        return result
    }

    /// v1.5.1: записи ImportReport о сложном содержимом колонтитулов —
    /// раньше графика/текстбоксы/рамки отбрасывались из ОТОБРАЖЕНИЯ молча.
    private static func hfReportEntries(preservedHF: [String: PreservedHFPart]) -> [ImportReport.Entry] {
        var counts: [String: Int] = [:]
        for (_, part) in preservedHF {
            guard let s = String(data: part.xml, encoding: .utf8) else { continue }
            let patterns: [(String, String)] = [
                ("<w:drawing",  "Графика в колонтитулах"),
                ("<w:pict",     "VML в колонтитулах"),
                ("txbxContent", "Текстовые фреймы в колонтитулах"),
                ("<w:tbl>",     "Таблицы в колонтитулах"),
                ("<w:pBdr",     "Границы абзацев в колонтитулах"),
                ("<w:tabs",     "Позиции табуляции в колонтитулах"),
            ]
            for (pat, key) in patterns {
                let n = s.components(separatedBy: pat).count - 1
                if n > 0 { counts[key, default: 0] += n }
            }
        }
        let explanation = "Сохраняется при пересохранении (lossless passthrough); в редакторе колонтитул отображается упрощённо (только текст)."
        return counts.map { ImportReport.Entry(category: "Колонтитулы", element: $0.key,
                                               count: $0.value, explanation: explanation) }
    }

    /// Конвертирует таблицу разобранных стилей DOCX в `DocumentStyles` — только
    /// для стандартных id (Normal / Heading1..6 / Strong / Emphasis / CodeChar).
    /// Overrides ложатся поверх наших `StandardParagraphStyle.def` — если стиль
    /// в файле совпадает с дефолтом, он всё равно записывается в model.styles
    /// (это гарантирует, что при последующем экспорте мы не «потеряем» его
    /// специфику, даже если внутренние defaults изменятся в будущем).
    private static func buildDocumentStyles(from styleTable: [String: StyleDef],
                                            defaultRunProps: RunProps) -> DocumentStyles {
        var result = DocumentStyles.defaultStyles
        // Проходим ВСЕ стили из styles.xml (не только стандартные id) — иначе
        // пользовательские стили внешних OOXML-файлов терялись при импорте:
        // диалог «Стили» их не показывал, а экспорт не сохранял.
        for (id, sd) in styleTable {
            let rp = sd.resolvedRunProps.merging(sd.ownRunProps)
            if sd.styleType == "character" {
                var def = StandardCharacterStyle.find(id: id)?.def
                    ?? CharacterStyleDef(name: sd.name ?? id)
                if let nm = sd.name { def.name = nm }
                if let name = sd.ownRunProps.fontName { def.fontName = name }
                if let size = rp.fontSize { def.fontSize = size }
                if let b = rp.bold        { def.bold   = b }
                if let i = rp.italic      { def.italic = i }
                result.characterStyles[id] = def
            } else {
                var def = StandardParagraphStyle.find(id: id)?.def
                    ?? ParagraphStyleDef(name: sd.name ?? id, basedOn: sd.basedOn)
                if let nm = sd.name { def.name = nm }
                if def.basedOn == nil, let bo = sd.basedOn { def.basedOn = bo }
                // fontName — ТОЛЬКО из явного rPr стиля (не из унаследованного
                // docDefaults), иначе Заголовки «запекались» в Times New Roman.
                if let name = sd.ownRunProps.fontName { def.fontName = name }
                if let size = rp.fontSize        { def.fontSize = size }
                if let b = rp.bold               { def.bold = b }
                if let i = rp.italic             { def.italic = i }
                if let c = rp.textColor          { def.textColor = c }
                if let bg = rp.backgroundColor   { def.backgroundColor = bg }
                if let sb = sd.ownParaProps.spaceBefore { def.spaceBefore = sb }
                if let sa = sd.ownParaProps.spaceAfter  { def.spaceAfter  = sa }
                if let al = sd.ownParaProps.alignment   { def.alignment   = al }
                result.paragraphStyles[id] = def
            }
        }
        return result
    }

    // MARK: - Экспорт

    public static func exportDocx(_ document: DocumentModel) throws -> Data {
        let serializer = OoxmlDocumentSerializer()
        let parts = try serializer.serialize(document: document)
        return try buildArchive(parts: parts)
    }

    public static func exportDocx(_ document: DocumentModel, to url: URL) throws {
        let data = try exportDocx(document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }
}

