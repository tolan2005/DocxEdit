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
        return (model, parser.buildReport().merging(hfReportEntries(preservedHF: preservedHF)))
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

// MARK: - Вспомогательные типы для парсинга

/// Явно установленные свойства прогона (из XML-элемента <w:rPr> или стиля).
/// nil = «не задано» (унаследовать из нижележащего уровня).
private struct RunProps {
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
private struct ParaProps {
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
        return r
    }
}

/// Определение стиля из styles.xml (до разворачивания наследования).
private struct StyleDef {
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

private final class OoxmlStylesParser: NSObject, XMLParserDelegate {
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

// MARK: - Парсер word/_rels/document.xml.rels (v0.1.53)

/// Разбирает `<Relationship Id="..." Target="..."/>` и заполняет `map: [Id → Target]`.
/// Используется для резолвинга `r:embed` в `<a:blip>` → путь к бинарю в media/.
private final class DocumentRelsParser: NSObject, XMLParserDelegate {
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
private final class NumberingXmlParser: NSObject, XMLParserDelegate {
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
private final class CommentsXmlParser: NSObject, XMLParserDelegate {
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
private final class FootnotesXmlParser: NSObject, XMLParserDelegate {
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
private final class HeaderFooterPartParser: NSObject, XMLParserDelegate {
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

// MARK: - Парсер документа

private final class OoxmlDocumentParser: NSObject, XMLParserDelegate {
    private let defaultRunProps: RunProps
    private let styleTable: [String: StyleDef]
    private let numbering: NumberingXmlParser?

    private var sections: [DocumentSection] = []
    private var currentBlocks: [Block] = []
    private var currentParagraph: Paragraph?

    private var currentRunText = ""
    private var currentDirectRunProps = RunProps()
    private var currentDirectParaProps = ParaProps()
    private var currentRunStyleId: String? = nil

    private var inParagraph     = false
    private var inRun           = false
    private var inRunProperties = false
    private var inParaProperties = false
    private var inSectionProperties = false
    private var inText          = false   // Fix #3: отслеживаем <w:t>

    private var inNumPr = false
    private var currentNumId: String? = nil
    private var currentIlvl = 0

    // v0.1.49: сборка таблиц (`w:tbl`/`w:tr`/`w:tc`). Одноуровневая (вложенные
    // таблицы принимаются, но flatten'ятся к внешней). `tableCurrentCellBlocks`
    // отличен от nil ↔ мы внутри `w:tc` — параграфы идут туда, не в `currentBlocks`.
    private var tableRows: [DocxCore.TableRow] = []
    private var tableCurrentRow: [TableCell] = []
    private var tableCurrentCellBlocks: [Block]? = nil
    private var inTable = false
    // v0.1.51: стиль таблицы и стиль ячейки (borders/width/background).
    private var tableCurrentStyle: TableStyle = TableStyle()
    private var tableCurrentColumnWidths: [CGFloat] = []
    // v0.1.70: горизонтальное выравнивание таблицы (w:jc в tblPr).
    private var tableCurrentAlignment: TableAlignment = .left
    private var tableCurrentCellWidth: CGFloat? = nil
    private var tableCurrentCellBackground: CodableColor? = nil
    // v0.1.85: строка-заголовок таблицы (<w:tblHeader/> внутри <w:trPr>).
    private var tableCurrentRowIsHeader: Bool = false
    private var tableCurrentRowHeight: CGFloat? = nil
    private var inTrPr: Bool = false
    private var tableCurrentCellColSpan: Int = 1
    // v0.1.63: вертикальный merge. `.restart` = ячейка, начинающая вертикальную группу;
    // `.continue` = не добавлять в модель, у restart-ячейки в этой grid-колонке
    // rowSpan+=1; `.none` = обычная ячейка.
    private enum VMergeKind { case none, restart, continue_ }
    private var tableCurrentCellVMerge: VMergeKind = .none
    /// v1.5.17: w:textDirection ячейки ("tbRl"/"btLr").
    private var tableCurrentCellTextDirection: String? = nil
    private var tableCurrentGridCol: Int = 0
    /// (grid-col) → (индекс row в `tableRows`, индекс cell в этой row).
    /// Используется continue-ячейкой, чтобы найти restart-ячейку и увеличить её rowSpan.
    private var openVMergeByGridCol: [Int: (rowIndex: Int, cellIndex: Int)] = [:]
    private var inTablePr: Bool = false
    private var inTblBorders: Bool = false
    /// v1.5.5: внутри <w:pBdr> (границы абзаца).
    private var inPBdr: Bool = false
    private var inTcPr: Bool = false

    private func appendBlock(_ block: Block) {
        if tableCurrentCellBlocks != nil {
            tableCurrentCellBlocks!.append(block)
        } else {
            currentBlocks.append(block)
        }
    }

    private var pageSettings = PageSettings.a4Portrait
    private var metadata = DocumentMetadata()

    /// Определяет `PaperSize` по портретным размерам в points (с погрешностью 2pt).
    private func paperFromDimensions(widthPt: CGFloat, heightPt: CGFloat) -> PaperSize {
        let tolerance: CGFloat = 2
        for size in PaperSize.allCases where size != .custom {
            let s = size.sizeInPoints
            if abs(s.width - widthPt) < tolerance, abs(s.height - heightPt) < tolerance {
                return size
            }
        }
        return .custom
    }

    // v0.1.53: rels mapping (rId → target) + бинари media/.
    private var imagesRels: [String: String] = [:]
    private var mediaFiles: [String: Data] = [:]
    private var inDrawing: Bool = false
    private var currentDrawingWidthEmu: Int = 0
    private var currentDrawingHeightEmu: Int = 0
    private var currentDrawingAltText: String? = nil
    /// v0.1.102: режим обтекания. Заполняется из wp:anchor + wp:wrap* / wp:wrapNone,
    /// иначе .inline (wp:inline).
    private var currentDrawingWrap: InlineImageWrap = .inline
    private var currentDrawingBehindDoc: Bool = false
    /// v1.5.12: позиция якоря (EMU, от колонки/абзаца) — для плавающего рендера.
    private var currentAnchorXEMU: Int? = nil
    private var currentAnchorYEMU: Int? = nil
    /// v1.5.12: сейчас внутри wp:positionH / wp:positionV (для wp:posOffset).
    private var anchorPosAxis: String? = nil   // "h" | "v"
    /// v1.5.12: буфер текста внутри wp:positionH/positionV (wp:posOffset и др.).
    private var anchorPosBuffer = ""
    /// v1.5.12: внутри wp:posOffset — следующий текст идёт в anchorPosBuffer.
    private var inPosOffset = false
    private var currentRunImage: InlineImage? = nil
    /// v1.5.7: глубина вложенности mc:Fallback в ТЕЛЕ документа.
    /// mc:AlternateContent несёт объект дважды (современный Choice + VML/legacy
    /// Fallback): текст Fallback'а подавляем (иначе текстбоксы дублируются,
    /// как раньше в колонтитулах — v1.5.2), а картинку-превью SmartArt/диаграммы
    /// (v:imagedata) извлекаем — раньше она терялась («обычно пустое»).
    private var mcFallbackDepth = 0
    /// v1.5.7: размеры текущего VML-шейпа (pt, из style width/height).
    private var vmlShapeWidthPt: CGFloat = 0
    private var vmlShapeHeightPt: CGFloat = 0

    // v0.1.54: гиперссылки. `<w:hyperlink r:id="rIdN">…runs…</w:hyperlink>` —
    // все ранs внутри получают hyperlink = target(rIdN) из document.xml.rels.
    // Внутренние якоря (w:anchor) в v1 не поддерживаются.
    private var currentHyperlinkURL: String? = nil
    /// v0.4.5 (R06): активные commentRange (стек по вложенности `<w:commentRangeStart>` /
    /// `End`). Первый (innermost по нашей реализации — последний открытый) id
    /// присваивается создаваемым runs. MVP: не поддерживаем перекрывающиеся
    /// комментарии — ран получает id только последнего открытого.
    private var activeCommentIds: [String] = []
    /// v0.4.7 (R06): активные track-changes обёртки — при парсе `<w:ins>` /
    /// `<w:del>` кладём "author|date|id" в стек; на закрывающем теге снимаем.
    /// Ран получает значение из последнего активного (внутренний перевешивает
    /// внешний, если Word пишет вложенные — упрощение MVP).
    private var activeInsertions: [String] = []
    private var activeDeletions:  [String] = []
    /// v0.5.2 (R07): id сноски, увиденной в текущем `<w:r>`. Живёт до
    /// закрытия w:r, потом сбрасывается.
    private var currentRunFootnoteId: String? = nil
    /// v1.5.15: id концевой сноски в текущем `<w:r>` (w:endnoteReference).
    private var currentRunEndnoteId: String? = nil

    // v1.5.6: сложные поля (w:fldChar). Round-trip одноабзацных полей
    // (REF/PAGEREF/SEQ/DATE/…): инструкция вешается на первый ран результата
    // (Run.fieldInstr) и пишется обратно при экспорте. Многоабзацные поля
    // (TOC) — как раньше, результат текстом + запись в отчёте.
    private var fieldDepth = 0
    private var fieldInstrBuffer = ""
    private var inInstrText = false
    private var pendingFieldInstr: String? = nil

    /// v0.5.5 (R07): активная перекрёстная ссылка от `<w:fldSimple w:instr=" REF X \h ">`.
    /// Присваивается всем runs внутри fldSimple; сбрасывается на закрывающем теге.
    private var activeCrossRef: String? = nil

    /// v0.5.8 (R08): активная ревизия атрибутов текущего `<w:r>`. Формат
    /// "author|date|id"; вычитывается из `<w:rPrChange>` в rPr.
    private var currentRunAttrRevision: String? = nil
    /// v0.5.8: глубина вложенности внутри `<w:rPrChange>` — пока > 0, все
    /// внутренние `<w:rPr>`/prop-элементы игнорируем (старые атрибуты не
    /// восстанавливаем в MVP; см. Run.attributeRevision).
    private var insideRPrChangeDepth = 0

    /// v0.5.6 (R07): состояние разбора `<w:sdt>` для TOC-блока.
    /// `inSdtPr` — сейчас разбираем `<w:sdtPr>`; `pendingSdtIsToc` — в этом
    /// sdtPr замечен `<w:docPartGallery w:val="Table of Contents">`;
    /// `activeTocBlock` — присваивается всем runs внутри `<w:sdtContent>`.
    private var inSdtPr = false
    private var pendingSdtIsToc = false
    private var activeTocBlock: String? = nil

    // v0.1.56: Import Diagnostic — считаем встречи «сложных» OOXML-элементов,
    // которые мы узнали, но полноценно не восстановили.
    private var reportCounts: [String: Int] = [:]
    private func note(_ element: String) {
        reportCounts[element, default: 0] += 1
    }
    func buildReport() -> ImportReport {
        var entries: [ImportReport.Entry] = []
        func add(_ el: String, _ category: String, _ explanation: String) {
            if let c = reportCounts[el], c > 0 {
                entries.append(.init(category: category, element: el, count: c, explanation: explanation))
            }
        }
        add("w:fldChar",       "Сложные поля",          "Многосоставные поля (fldChar begin/separate/end) — оглавление, ссылки, TOC. Поддерживаются только простые поля w:fldSimple.")
        add("w:instrText",     "Сложные поля",          "Инструкция сложного поля — сохранена как обычный текст, живая пересборка не сработает.")
        // v0.1.102: wp:anchor теперь поддерживается — режим обтекания сохраняется
        // в модели (`InlineImage.wrap`); ограничение — редактор пока рендерит все
        // режимы как inline (реальный anchored-layout — задача R04).
        add("w:pict",          "Legacy-объекты (VML)",  "Старый формат Word (VML/OLE). Не рендерится в редакторе.")
        add("w:object",        "Legacy-объекты (OLE)",  "Встроенный OLE-объект (Excel-лист, формула и т.п.). Не поддерживается.")
        add("w:sdt",           "Content Controls",      "Структурированные элементы (шаблонные поля). Содержимое импортируется как текст, оболочка теряется.")
        // v0.5.2 (R07): w:footnoteReference теперь поддерживается — не отчитываем.
        // v1.5.15: w:endnoteReference поддержан — импорт/экспорт word/endnotes.xml.
        // Создание концевых сносок в UI пока не добавлено (импорт-only).
        // v0.4.5: `w:comment` больше не считается неподдержанным — реализован
        // импорт `<w:comment>` из word/comments.xml + `commentRangeStart/End`
        // на runs. Известное MVP-ограничение: ответы приходят как продолжение
        // текста треда (наш writer это делает; парсер не пытается разобрать
        // обратно на отдельные CommentReply).
        // v0.4.7: `w:ins`/`w:del` теперь импортируются как track-changes-маркеры
        // на runs (см. `Run.insertion`/`.deletion`); в отчёт не пишем.
        // v1.5.7: из mc:Fallback извлекаем картинку-превью (v:imagedata);
        // текст Fallback'а подавляем (дубль Choice). Сами SmartArt/диаграммы
        // не редактируются — видно превью.
        add("mc:AlternateContent", "SmartArt / графики",  "Диаграммы, SmartArt, chart. Импортируется картинка-превью из fallback-представления; редактирование объекта недоступно.")
        add("w:tab",           "Позиции табуляции",     "Пользовательские позиции табуляции — используются, но диалог настройки табов будет в R04.")
        // Сортируем по частоте (самое частое сверху).
        entries.sort { $0.count > $1.count }
        return ImportReport(entries: entries)
    }

    init(defaultRunProps: RunProps, styleTable: [String: StyleDef], numbering: NumberingXmlParser?,
         imagesRels: [String: String] = [:], mediaFiles: [String: Data] = [:]) {
        self.defaultRunProps = defaultRunProps
        self.styleTable = styleTable
        self.numbering = numbering
        self.imagesRels = imagesRels
        self.mediaFiles = mediaFiles
    }

    func parse(documentXml: Data, corePropsXml: Data?) throws -> DocumentModel {
        if let corePropsXml { parseCoreProps(corePropsXml) }
        let parser = XMLParser(data: documentXml)
        parser.delegate = self
        parser.parse()
        if sections.isEmpty {
            sections = [DocumentSection(blocks: currentBlocks.isEmpty ? [.paragraph(.empty)] : currentBlocks)]
        }
        return DocumentModel(metadata: metadata, pageSettings: pageSettings, sections: sections)
    }

    // MARK: XMLParserDelegate

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes a: [String: String]) {
        switch el {
        case "w:tbl":
            inTable = true
            tableRows = []
            tableCurrentRow = []
            tableCurrentStyle = TableStyle()
            tableCurrentColumnWidths = []
            tableCurrentAlignment = .left

        case "w:tblPr":
            inTablePr = true

        case "w:tblStyle":
            // v1.5.17: именованный стиль таблицы ("TableGrid", "LightShading…").
            if inTablePr, let v = a["w:val"] { tableCurrentStyle.namedStyleId = v }

        case "w:tblBorders":
            if inTablePr { inTblBorders = true; tableCurrentStyle.hasBorders = true }

        case "w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV":
            // v:val="single/none/…", w:sz=1/8 pt units (значение = размер * 8), w:color=RRGGBB.
            if inTblBorders {
                if let v = a["w:val"], v == "none" || v == "nil" {
                    tableCurrentStyle.hasBorders = false
                }
                if let szStr = a["w:sz"], let sz = Double(szStr) {
                    // w:sz — в 1/8 point (Word) → pt = sz / 8.
                    tableCurrentStyle.borderWidth = max(tableCurrentStyle.borderWidth, CGFloat(sz / 8.0))
                }
                if let hex = a["w:color"], let cc = CodableColor.fromHex(hex) {
                    tableCurrentStyle.borderColor = cc
                }
            } else if inPBdr {
                // v1.5.5: границы абзаца (<w:pBdr>). val="none"/"nil" — сторона
                // отключена; не-single стили сводим к сплошной линии.
                var b = currentDirectParaProps.border ?? ParagraphBorder()
                let on = !(a["w:val"] == "none" || a["w:val"] == "nil")
                switch el {
                case "w:top":    b.top = on
                case "w:bottom": b.bottom = on
                case "w:left":   b.left = on
                case "w:right":  b.right = on
                default: break
                }
                if on {
                    if let szStr = a["w:sz"], let sz = Double(szStr) {
                        b.width = max(b.width, CGFloat(sz / 8.0))
                    }
                    if let hex = a["w:color"], hex != "auto",
                       let cc = CodableColor.fromHex(hex) {
                        b.color = cc
                    }
                }
                currentDirectParaProps.border = b.isEmpty ? nil : b
            }

        case "w:pBdr":
            if inParaProperties { inPBdr = true }

        case "w:gridCol":
            if let wStr = a["w:w"], let w = Double(wStr) {
                // twips → points (1 pt = 20 twips).
                tableCurrentColumnWidths.append(CGFloat(w / 20.0))
            }

        case "w:tr":
            tableCurrentRow = []
            tableCurrentGridCol = 0
            tableCurrentRowIsHeader = false
            tableCurrentRowHeight = nil

        case "w:trPr":
            inTrPr = true

        case "w:tblHeader":
            // v0.1.85: строка-заголовок (в <w:trPr>). Без val или val="1" — включено.
            if inTrPr {
                let v = a["w:val"] ?? "1"
                tableCurrentRowIsHeader = (v != "0" && v.lowercased() != "false")
            }
        case "w:trHeight":
            // v0.1.86: высота строки таблицы. twips → points (1 pt = 20 twips).
            if inTrPr, let vStr = a["w:val"], let v = Double(vStr), v > 0 {
                tableCurrentRowHeight = CGFloat(v / 20.0)
            }

        case "w:tc":
            tableCurrentCellBlocks = []
            tableCurrentCellWidth = nil
            tableCurrentCellBackground = nil
            tableCurrentCellColSpan = 1
            tableCurrentCellVMerge = .none
            tableCurrentCellTextDirection = nil

        case "w:tcPr":
            inTcPr = true

        case "w:tcW":
            if inTcPr, let wStr = a["w:w"], let w = Double(wStr) {
                let type = a["w:type"] ?? "dxa"
                if type == "dxa" { tableCurrentCellWidth = CGFloat(w / 20.0) }
            }

        case "w:gridSpan":
            // Горизонтальное объединение ячеек (v0.1.61): w:val = N.
            if inTcPr, let vs = a["w:val"], let n = Int(vs), n > 1 {
                tableCurrentCellColSpan = n
            }

        case "w:vMerge":
            // Вертикальное объединение (v0.1.63): val="restart" — начало группы,
            // отсутствие val (или val="continue") — продолжение.
            if inTcPr {
                let v = a["w:val"] ?? ""
                tableCurrentCellVMerge = (v == "restart") ? .restart : .continue_
            }

        case "w:textDirection":
            // v1.5.17: вертикальный текст в ячейке (tbRl/btLr). Сохраняем для
            // round-trip; рендер в редакторе — горизонтальный (ограничение).
            if inTcPr, let v = a["w:val"], !v.isEmpty {
                tableCurrentCellTextDirection = v
            }

        case "w:shd":
            // Заливка ячейки таблицы: <w:shd w:fill="RRGGBB"/> внутри w:tcPr.
            if inTcPr, let fill = a["w:fill"], fill.lowercased() != "auto",
               let cc = CodableColor.fromHex(fill) {
                tableCurrentCellBackground = cc
            }
            // v0.1.82: заливка рана в теле документа — <w:shd> внутри <w:rPr>.
            else if inRunProperties, let fill = a["w:fill"], fill.lowercased() != "auto",
                    let cc = CodableColor.fromHex(fill) {
                currentDirectRunProps.backgroundColor = cc
            }

        case "w:sectPr":
            inSectionProperties = true

        case "w:pgSz":
            if inSectionProperties {
                if let wStr = a["w:w"], let hStr = a["w:h"],
                   let w = Double(wStr), let h = Double(hStr) {
                    let wPt = CGFloat(w) / 20.0
                    let hPt = CGFloat(h) / 20.0
                    // Определяем формат по размерам (портретная/альбомная).
                    let (portraitW, portraitH) = wPt < hPt ? (wPt, hPt) : (hPt, wPt)
                    let paper = paperFromDimensions(widthPt: portraitW, heightPt: portraitH)
                    pageSettings.paperSize = paper
                    let isLandscape = (a["w:orient"] == "landscape") || (wPt > hPt)
                    pageSettings.orientation = isLandscape ? .landscape : .portrait
                }
            }

        case "w:pgMar":
            if inSectionProperties {
                var m = pageSettings.margins
                if let v = a["w:top"], let n = Double(v)    { m.top = CGFloat(n) / 20.0 }
                if let v = a["w:right"], let n = Double(v)  { m.right = CGFloat(n) / 20.0 }
                if let v = a["w:bottom"], let n = Double(v) { m.bottom = CGFloat(n) / 20.0 }
                if let v = a["w:left"], let n = Double(v)   { m.left = CGFloat(n) / 20.0 }
                if let v = a["w:header"], let n = Double(v) { m.header = CGFloat(n) / 20.0 }
                if let v = a["w:footer"], let n = Double(v) { m.footer = CGFloat(n) / 20.0 }
                if let v = a["w:gutter"], let n = Double(v) { m.gutter = CGFloat(n) / 20.0 }
                pageSettings.margins = m
            }

        case "w:mirrorMargins":
            if inSectionProperties { pageSettings.mirrorMargins = true }

        case "w:drawing":
            inDrawing = true
            currentDrawingWidthEmu = 0
            currentDrawingHeightEmu = 0
            currentDrawingAltText = nil
            currentDrawingWrap = .inline
            currentDrawingBehindDoc = false

        case "wp:inline":
            if inDrawing { currentDrawingWrap = .inline }

        case "wp:anchor":
            if inDrawing {
                currentDrawingBehindDoc = (a["behindDoc"] == "1")
                currentAnchorXEMU = nil
                currentAnchorYEMU = nil
                // Пока не встретим wp:wrap*, считаем wrapNone → behind/inFrontOf.
                currentDrawingWrap = currentDrawingBehindDoc ? .behindText : .inFrontOfText
            }

        // v1.5.12: позиции якоря — wp:posOffset внутри positionH/positionV.
        case "wp:positionH":
            if inDrawing { anchorPosAxis = "h" }
        case "wp:positionV":
            if inDrawing { anchorPosAxis = "v" }
        case "wp:posOffset":
            if inDrawing && anchorPosAxis != nil { inPosOffset = true; anchorPosBuffer = "" }

        case "wp:wrapSquare":
            if inDrawing { currentDrawingWrap = .square }
        case "wp:wrapTight":
            if inDrawing { currentDrawingWrap = .tight }
        case "wp:wrapTopAndBottom":
            if inDrawing { currentDrawingWrap = .topAndBottom }
        case "wp:wrapNone":
            if inDrawing { currentDrawingWrap = currentDrawingBehindDoc ? .behindText : .inFrontOfText }

        case "wp:extent":
            if inDrawing {
                if let cx = a["cx"], let n = Int(cx) { currentDrawingWidthEmu = n }
                if let cy = a["cy"], let n = Int(cy) { currentDrawingHeightEmu = n }
            }

        case "wp:docPr":
            // Alt-text из descr (или title как fallback — некоторые генераторы кладут туда).
            if inDrawing {
                if let d = a["descr"], !d.isEmpty { currentDrawingAltText = d }
                else if let t = a["title"], !t.isEmpty { currentDrawingAltText = t }
            }

        case "a:blip":
            // r:embed указывает на rId в document.xml.rels; резолвим → путь в media/.
            if inDrawing, let embed = a["r:embed"], let target = imagesRels[embed] {
                let filename = target.hasPrefix("media/") ? String(target.dropFirst("media/".count)) : target
                if let data = mediaFiles[filename] {
                    let ext = (filename as NSString).pathExtension.lowercased()
                    let format: InlineImageFormat = {
                        switch ext {
                        case "jpg", "jpeg": return .jpeg
                        case "gif":  return .gif
                        case "tif", "tiff": return .tiff
                        default:     return .png
                        }
                    }()
                    let widthPt = currentDrawingWidthEmu > 0 ? CGFloat(currentDrawingWidthEmu) / 12700.0 : 0
                    let heightPt = currentDrawingHeightEmu > 0 ? CGFloat(currentDrawingHeightEmu) / 12700.0 : 0
                    currentRunImage = InlineImage(format: format, data: data,
                                                   displayWidth: widthPt, displayHeight: heightPt,
                                                   altText: currentDrawingAltText,
                                                   wrap: currentDrawingWrap,
                                                   anchorXEMU: currentAnchorXEMU,
                                                   anchorYEMU: currentAnchorYEMU)
                }
            }

        case "w:p":
            inParagraph = true
            currentDirectParaProps = ParaProps()
            currentParagraph = nil

        case "w:pPr":
            inParaProperties = true

        case "w:pStyle":
            if inParaProperties, let val = a["w:val"] {
                currentDirectParaProps.styleId = val
            }

        case "w:hyperlink":
            if let rId = a["r:id"], let target = imagesRels[rId] {
                currentHyperlinkURL = target
            }

        case "w:commentRangeStart":
            if let id = a["w:id"] { activeCommentIds.append(id) }
        case "w:commentRangeEnd":
            if let id = a["w:id"], let idx = activeCommentIds.lastIndex(of: id) {
                activeCommentIds.remove(at: idx)
            }

        case "w:footnoteReference":
            // v0.5.2 (R07): вход-точка сноски в теле документа. Живёт на текущем ране.
            if let id = a["w:id"] { currentRunFootnoteId = id }

        case "w:endnoteReference":
            // v1.5.15: концевая сноска. Симметрично w:footnoteReference.
            if let id = a["w:id"] { currentRunEndnoteId = id }

        case "w:fldSimple":
            // v0.5.5 (R07): распознаём поле REF — вытаскиваем имя закладки.
            // instr вида " REF _Ref123 \h " или " REF имя ".
            if let instr = a["w:instr"] {
                let trimmed = instr.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("REF ") {
                    let rest = String(trimmed.dropFirst(4))
                    // Первый токен до пробела/слэша — имя закладки.
                    let name = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
                    if !name.isEmpty { activeCrossRef = name }
                }
            }

        case "w:ins":
            let author = a["w:author"] ?? ""
            let date = a["w:date"] ?? ISO8601DateFormatter().string(from: Date())
            let id = a["w:id"] ?? ""
            activeInsertions.append("\(author)|\(date)|\(id)")
        case "w:del":
            let author = a["w:author"] ?? ""
            let date = a["w:date"] ?? ISO8601DateFormatter().string(from: Date())
            let id = a["w:id"] ?? ""
            activeDeletions.append("\(author)|\(date)|\(id)")
        case "w:delText":
            // Собираем текст удалённого рана — идентично w:t.
            inText = true

        case "w:r":
            inRun = true
            currentDirectRunProps = RunProps()
            currentRunStyleId = nil
            currentRunText = ""

        case "w:rPr":
            // v0.5.8 (R08): пропускаем внутренние rPr внутри rPrChange — они
            // описывают СТАРЫЕ атрибуты рана (do-not-restore в MVP).
            if insideRPrChangeDepth == 0 { inRunProperties = true }

        case "w:rPrChange":
            // v0.5.8 (R08): начало ревизии атрибутов. Забираем метаданные,
            // маркируем «внутри rPrChange», временно отключаем сбор props.
            insideRPrChangeDepth += 1
            let author = a["w:author"] ?? ""
            let date   = a["w:date"]   ?? ISO8601DateFormatter().string(from: Date())
            let id     = a["w:id"]     ?? ""
            currentRunAttrRevision = "\(author)|\(date)|\(id)"
            inRunProperties = false

        case "w:rStyle":
            if inRunProperties, let val = a["w:val"] {
                currentRunStyleId = val
            }

        case "w:t":
            inText = true   // Fix #3

        case "w:b":
            if inRunProperties { currentDirectRunProps.bold = true }
        case "w:bCs":
            if inRunProperties { currentDirectRunProps.bold = true }
        case "w:i":
            if inRunProperties { currentDirectRunProps.italic = true }
        case "w:iCs":
            if inRunProperties { currentDirectRunProps.italic = true }
        case "w:u":
            if inRunProperties {
                let val = a["w:val"] ?? "single"
                currentDirectRunProps.underline = OoxmlUnderlineMapper.parse(val)
            }
        case "w:strike":
            if inRunProperties { currentDirectRunProps.strikethrough = true }
        case "w:vertAlign":
            // v0.1.77: над/подстрочный в rPr тела документа.
            if inRunProperties {
                let val = a["w:val"] ?? "baseline"
                if val == "superscript" { currentDirectRunProps.superscript = true }
                if val == "subscript"   { currentDirectRunProps.`subscript` = true }
            }
        case "w:color":
            if inRunProperties, let hex = a["w:val"], let c = CodableColor.fromHex(hex) {
                currentDirectRunProps.textColor = c
            }
        case "w:highlight":
            // v0.1.82: цвет подсветки (именованные OOXML highlight-цвета).
            if inRunProperties, let name = a["w:val"], let c = highlightNameToColor(name) {
                currentDirectRunProps.backgroundColor = c
            }
        case "w:sz":
            if inRunProperties, let v = a["w:val"], let n = Double(v) {
                currentDirectRunProps.fontSize = CGFloat(n) / 2.0
            }
        case "w:rFonts":
            if inRunProperties {
                let name = a["w:ascii"] ?? a["w:hAnsi"] ?? a["w:cs"]
                currentDirectRunProps.fontName = name
            }

        case "w:jc":
            if inParaProperties, let val = a["w:val"] {
                currentDirectParaProps.alignment = alignment(from: val)
            } else if inTablePr, let val = a["w:val"] {
                // v0.1.70: горизонтальное выравнивание таблицы на странице.
                switch val {
                case "center": tableCurrentAlignment = .center
                case "right",
                     "end":    tableCurrentAlignment = .right
                default:       tableCurrentAlignment = .left
                }
            }
        case "w:ind":
            if inParaProperties {
                if let v = a["w:left"],      let n = Double(v) { currentDirectParaProps.leftIndent      = CGFloat(n) / 20.0 }
                if let v = a["w:right"],     let n = Double(v) { currentDirectParaProps.rightIndent     = CGFloat(n) / 20.0 }
                if let v = a["w:firstLine"], let n = Double(v) { currentDirectParaProps.firstLineIndent = CGFloat(n) / 20.0 }
                if let v = a["w:hanging"],   let n = Double(v) { currentDirectParaProps.hangingIndent   = CGFloat(n) / 20.0 }
            }
        case "w:tab":
            // v1.5.4: пользовательские таб-стопы (<w:tabs><w:tab w:val w:pos>).
            // `w:tab` без pos внутри рана — это символ табуляции, не стоп;
            // decimal на macOS не рендерится — маппим в right.
            if inParaProperties, let v = a["w:pos"], let n = Double(v) {
                let align: DocxCore.TextAlignment = {
                    switch a["w:val"] {
                    case "center":           return .center
                    case "right", "decimal": return .right
                    default:                 return .left
                    }
                }()
                var stops = currentDirectParaProps.tabStops ?? []
                stops.append(TabStop(position: CGFloat(n) / 20.0, alignment: align))
                currentDirectParaProps.tabStops = stops
            }
        case "w:spacing":
            if inParaProperties {
                if let v = a["w:line"],   let n = Double(v) { currentDirectParaProps.lineSpacing = .multiple(CGFloat(n) / 240.0) }
                if let v = a["w:before"], let n = Double(v) { currentDirectParaProps.spaceBefore = CGFloat(n) / 20.0 }
                if let v = a["w:after"],  let n = Double(v) { currentDirectParaProps.spaceAfter  = CGFloat(n) / 20.0 }
            }
        case "w:numPr":
            if inParaProperties {
                inNumPr = true
                currentNumId = nil
                currentIlvl = 0
            }
        case "w:ilvl":
            if inNumPr, let v = a["w:val"], let n = Int(v) { currentIlvl = n }
        case "w:numId":
            if inNumPr { currentNumId = a["w:val"] }
        case "w:br":
            // Разрыв строки/страницы внутри прогона. `w:type="page"` → U+000C (FF),
            // остальные (line/textWrapping) → `\n`.
            if inRun {
                if a["w:type"] == "page" { currentRunText += "\u{000C}" }
                else                    { currentRunText += "\n" }
            }

        // v0.1.56: Import Diagnostic — считаем «сложные» элементы. Продолжаем
        // разбор внутренностей, но помечаем факт, что мы «упростили» их.
        case "w:fldChar":
            // v1.5.6: сложные поля — round-trip для одноабзацных (инструкция
            // на первом ране результата); в отчёт — только если поле
            // многоабзацное (сброс в </w:p>).
            switch a["w:fldCharType"] {
            case "begin":
                fieldDepth += 1
                if fieldDepth == 1 { fieldInstrBuffer = "" }
            case "separate":
                if fieldDepth >= 1 {
                    pendingFieldInstr = fieldInstrBuffer.trimmingCharacters(in: .whitespaces)
                }
            case "end":
                fieldDepth = max(0, fieldDepth - 1)
                if fieldDepth == 0 { pendingFieldInstr = nil }
            default: break
            }
        case "w:instrText":
            if fieldDepth > 0 { inInstrText = true }

        case "wp:anchor", "w:pict", "w:object",
             "mc:AlternateContent":
            note(el)

        // v1.5.7: mc:Fallback в теле — текст подавляем (дубль Choice),
        // картинку-превью (v:imagedata) извлекаем.
        case "mc:Fallback":
            mcFallbackDepth += 1

        case "v:shape":
            // v1.5.7: размеры VML-шейпа из style (width/height в pt).
            vmlShapeWidthPt = 0
            vmlShapeHeightPt = 0
            if let style = a["style"] {
                for part in style.split(separator: ";") {
                    let kv = part.split(separator: ":")
                    guard kv.count == 2 else { continue }
                    let v = kv[1].replacingOccurrences(of: "pt", with: "")
                    guard let n = Double(v) else { continue }
                    if kv[0] == "width" { vmlShapeWidthPt = CGFloat(n) }
                    if kv[0] == "height" { vmlShapeHeightPt = CGFloat(n) }
                }
            }

        case "v:imagedata":
            // v1.5.7: картинка из VML (fallback SmartArt/диаграммы, водяной
            // знак-картинка в теле). r:id резолвим в media/ как у a:blip.
            if let rid = a["r:id"], let target = imagesRels[rid] {
                let filename = target.hasPrefix("media/") ? String(target.dropFirst("media/".count)) : target
                if let data = mediaFiles[filename] {
                    let ext = (filename as NSString).pathExtension.lowercased()
                    let format: InlineImageFormat = {
                        switch ext {
                        case "jpg", "jpeg": return .jpeg
                        case "gif":  return .gif
                        case "tif", "tiff": return .tiff
                        case "emf", "wmf": return .png  // растрируем позже; v1 — как есть
                        default:     return .png
                        }
                    }()
                    currentRunImage = InlineImage(format: format, data: data,
                                                   displayWidth: vmlShapeWidthPt,
                                                   displayHeight: vmlShapeHeightPt,
                                                   altText: nil, wrap: .inline)
                }
            }

        // v0.5.6 (R07): SDT — распознаём TOC-контейнер. Остальные типы SDT
        // (chart, docPartList, checkBox, ...) по-прежнему упрощаются.
        case "w:sdt":
            pendingSdtIsToc = false
        case "w:sdtPr":
            inSdtPr = true
        case "w:docPartGallery":
            if inSdtPr, a["w:val"] == "Table of Contents" {
                pendingSdtIsToc = true
            }
        case "w:sdtContent":
            if pendingSdtIsToc { activeTocBlock = "toc" }
            else { note("w:sdt") }

        default: break
        }
    }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "mc:Fallback":
            mcFallbackDepth = max(0, mcFallbackDepth - 1)

        case "wp:posOffset":
            if inPosOffset {
                let v = Int(anchorPosBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
                if anchorPosAxis == "h" { currentAnchorXEMU = v }
                if anchorPosAxis == "v" { currentAnchorYEMU = v }
                inPosOffset = false
            }
        case "wp:positionH", "wp:positionV":
            anchorPosAxis = nil

        case "w:t":
            inText = false   // Fix #3

        case "w:instrText":
            inInstrText = false

        case "w:delText":
            inText = false
        case "w:ins":
            if !activeInsertions.isEmpty { activeInsertions.removeLast() }
        case "w:del":
            if !activeDeletions.isEmpty { activeDeletions.removeLast() }

        case "w:numPr":
            if inNumPr {
                let type: ListType
                let style: DocxCore.ListFormatStyle
                if let numId = currentNumId, let found = numbering?.listInfo(numId: numId, ilvl: currentIlvl) {
                    (type, style) = found
                } else {
                    type = .bulleted
                    style = .bullet(character: "•")
                }
                currentDirectParaProps.listInfo = ListInfo(
                    listType: type, level: currentIlvl,
                    continuation: .continue, formatStyle: style,
                    start: currentNumId.flatMap { numbering?.startValue(numId: $0, ilvl: currentIlvl) }
                )
                inNumPr = false
            }

        case "w:r":
            if inRun {
                let finalCharAttrs = buildCharAttrs()
                // Inline-изображение (v0.1.53): если в ране был <w:drawing><a:blip>,
                // строим Run с image (текст = U+FFFC — Object Replacement Character).
                let commentId = activeCommentIds.last
                let insertion = activeInsertions.last
                let deletion  = activeDeletions.last
                let footnoteId = currentRunFootnoteId
                let endnoteId = currentRunEndnoteId
                let crossRef = activeCrossRef
                let tocBlock = activeTocBlock
                let attrRev = currentRunAttrRevision
                // v1.5.6: инструкция поля — на первый НЕПУСТОЙ ран результата
                // (раны с fldChar begin/separate пустые и не должны её красть).
                let fieldInstr: String? = {
                    if let p = pendingFieldInstr,
                       (!currentRunText.isEmpty || currentRunImage != nil) {
                        pendingFieldInstr = nil
                        return p
                    }
                    return nil
                }()
                if let img = currentRunImage {
                    let run = Run(text: "\u{FFFC}", attributes: finalCharAttrs, image: img, hyperlink: currentHyperlinkURL,
                                  commentId: commentId, insertion: insertion, deletion: deletion,
                                  footnoteId: footnoteId, crossRef: crossRef, tocBlock: tocBlock,
                                  attributeRevision: attrRev, fieldInstr: fieldInstr, endnoteId: endnoteId)
                    if currentParagraph == nil {
                        currentParagraph = Paragraph(runs: [], attributes: currentParagraphAttributes())
                    }
                    currentParagraph?.runs.append(run)
                    currentRunImage = nil
                } else {
                    // v0.5.2 (R07): пустой ран с footnoteReference имеет text="",
                    // но нужен, чтобы был якорь для сноски.
                    let run = Run(text: currentRunText, attributes: finalCharAttrs, hyperlink: currentHyperlinkURL,
                                  commentId: commentId, insertion: insertion, deletion: deletion,
                                  footnoteId: footnoteId, crossRef: crossRef, tocBlock: tocBlock,
                                  attributeRevision: attrRev, fieldInstr: fieldInstr, endnoteId: endnoteId)
                    if currentParagraph == nil {
                        currentParagraph = Paragraph(runs: [], attributes: currentParagraphAttributes())
                    }
                    currentParagraph?.runs.append(run)
                }
                currentRunText = ""
                currentDirectRunProps = RunProps()
                currentRunStyleId = nil
                currentRunFootnoteId = nil
                currentRunEndnoteId = nil
                currentRunAttrRevision = nil
            }
            inRun = false

        case "w:hyperlink":
            currentHyperlinkURL = nil

        case "w:fldSimple":
            // v0.5.5 (R07): выход из поля REF — сбрасываем active cross-ref.
            activeCrossRef = nil

        case "w:sdt":
            // v0.5.6 (R07): выход из SDT — сбрасываем TOC-контекст.
            activeTocBlock = nil
            pendingSdtIsToc = false
        case "w:sdtPr":
            inSdtPr = false

        case "w:drawing":
            inDrawing = false

        case "w:p":
            // v1.5.6: поле пересекло границу абзаца (TOC и т.п.) — не
            // round-trip'им, результат остаётся текстом; пишем в отчёт.
            if fieldDepth > 0 || pendingFieldInstr != nil {
                note("w:fldChar")
                fieldDepth = 0
                pendingFieldInstr = nil
                inInstrText = false
            }
            if inParagraph {
                let paraAttrs = currentParagraphAttributes()
                if let p = currentParagraph {
                    var finalPara = p
                    finalPara.attributes = paraAttrs
                    appendBlock(.paragraph(finalPara))
                } else {
                    appendBlock(.paragraph(
                        Paragraph(runs: [], attributes: paraAttrs)
                    ))
                }
                currentParagraph = nil
                currentDirectParaProps = ParaProps()
            }
            inParagraph = false

        case "w:tc":
            let colSpan = tableCurrentCellColSpan
            if tableCurrentCellVMerge == .continue_ {
                // Continue-ячейка: в модель не добавляем; у restart-ячейки в этой
                // grid-колонке увеличиваем rowSpan. Ищем в openVMergeByGridCol.
                if let ref = openVMergeByGridCol[tableCurrentGridCol] {
                    if ref.rowIndex < tableRows.count,
                       ref.cellIndex < tableRows[ref.rowIndex].cells.count {
                        tableRows[ref.rowIndex].cells[ref.cellIndex].rowSpan += 1
                    }
                }
            } else {
                let cellBlocks = tableCurrentCellBlocks ?? []
                let final: [Block] = cellBlocks.isEmpty
                    ? [.paragraph(Paragraph(runs: [Run(text: "", attributes: CharacterAttributes())],
                                           attributes: ParagraphAttributes()))]
                    : cellBlocks
                tableCurrentRow.append(TableCell(
                    blocks: final,
                    colSpan: colSpan,
                    width: tableCurrentCellWidth,
                    backgroundColor: tableCurrentCellBackground,
                    textDirection: tableCurrentCellTextDirection))
                if tableCurrentCellVMerge == .restart {
                    let rowIdx = tableRows.count // текущая (ещё не закоммиченная) row
                    let cellIdx = tableCurrentRow.count - 1
                    for gc in tableCurrentGridCol..<(tableCurrentGridCol + colSpan) {
                        openVMergeByGridCol[gc] = (rowIdx, cellIdx)
                    }
                }
            }
            tableCurrentGridCol += colSpan
            tableCurrentCellBlocks = nil
            tableCurrentCellWidth = nil
            tableCurrentCellBackground = nil
            tableCurrentCellColSpan = 1
            tableCurrentCellVMerge = .none
            tableCurrentCellTextDirection = nil

        case "w:tcPr":
            inTcPr = false

        case "w:tblPr":
            inTablePr = false

        case "w:tblBorders":
            inTblBorders = false

        case "w:pBdr":
            inPBdr = false

        case "w:trPr":
            inTrPr = false

        case "w:tr":
            tableRows.append(DocxCore.TableRow(cells: tableCurrentRow,
                                                height: tableCurrentRowHeight,
                                                isHeader: tableCurrentRowIsHeader))
            tableCurrentRow = []
            tableCurrentRowIsHeader = false
            tableCurrentRowHeight = nil

        case "w:tbl":
            if !tableRows.isEmpty {
                currentBlocks.append(.table(TableBlock(
                    rows: tableRows,
                    columnWidths: tableCurrentColumnWidths,
                    style: tableCurrentStyle,
                    alignment: tableCurrentAlignment)))
            }
            tableRows = []
            tableCurrentStyle = TableStyle()
            tableCurrentColumnWidths = []
            openVMergeByGridCol = [:]
            inTable = false

        case "w:rPr":
            // Симметрично open: игнорируем inner rPr внутри rPrChange.
            if insideRPrChangeDepth == 0 { inRunProperties = false }
        case "w:rPrChange":
            // v0.5.8 (R08): выход из ревизии — восстанавливаем сбор outer rPr
            // (если w:rPrChange находится посреди outer rPr, продолжим забирать
            // props после его закрытия).
            insideRPrChangeDepth = max(0, insideRPrChangeDepth - 1)
            if insideRPrChangeDepth == 0 { inRunProperties = true }
        case "w:pPr":
            inParaProperties = false
        case "w:sectPr":
            inSectionProperties = false

        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters string: String) {
        // v1.5.12: значение wp:posOffset (позиция якоря плавающей картинки).
        if inPosOffset { anchorPosBuffer += string }
        // Fix #3: собираем текст только внутри <w:t>
        // v1.5.7: текст внутри mc:Fallback пропускаем — это legacy-дубль
        // содержимого mc:Choice (текстбоксы задваивались).
        if inRun && inText && mcFallbackDepth == 0 {
            currentRunText += string
        }
        // v1.5.6: инструкция сложного поля.
        if inInstrText {
            fieldInstrBuffer += string
        }
    }

    func parser(_ p: XMLParser, foundCDATA CDATABlock: Data) {
        if inRun && inText && mcFallbackDepth == 0, let s = String(data: CDATABlock, encoding: .utf8) {
            currentRunText += s
        }
    }

    // MARK: - Вычисление итоговых атрибутов

    /// Строит CharacterAttributes для текущего прогона:
    /// docDefaults → pStyle.runProps → rStyle.runProps → direct rPr.
    private func buildCharAttrs() -> CharacterAttributes {
        // 1. База — docDefaults
        var merged = defaultRunProps

        // 2. Атрибуты стиля абзаца (runProps из pStyle)
        if let styleId = currentDirectParaProps.styleId,
           let styleDef = styleTable[styleId] {
            merged = merged.merging(styleDef.resolvedRunProps)
        }

        // 3. Атрибуты стиля символа (rStyle)
        if let rStyleId = currentRunStyleId,
           let rStyleDef = styleTable[rStyleId] {
            merged = merged.merging(rStyleDef.resolvedRunProps)
        }

        // 4. Прямые атрибуты прогона (высший приоритет)
        merged = merged.merging(currentDirectRunProps)

        var attrs = merged.toCharacterAttributes()
        // Сохраняем rStyle id в модели, чтобы при экспорте писать обратно <w:rStyle>.
        attrs.styleId = currentRunStyleId
        return attrs
    }

    /// Строит ParagraphAttributes для текущего абзаца:
    /// pStyle.paraProps → direct pPr.
    private func currentParagraphAttributes() -> ParagraphAttributes {
        var base = ParagraphAttributes()

        if let styleId = currentDirectParaProps.styleId,
           let styleDef = styleTable[styleId] {
            base = styleDef.resolvedParaProps.apply(to: base)
        }

        return currentDirectParaProps.apply(to: base)
    }

    // MARK: - Утилиты

    private func alignment(from val: String) -> TextAlignment {
        switch val {
        case "center": return .center
        case "right":  return .right
        case "both":   return .justify
        default:       return .left
        }
    }

    /// Именованные highlight-цвета мейнстрим-редакторов → RGB (v0.1.82).
    private func highlightNameToColor(_ name: String) -> CodableColor? {
        let map: [String: (Double, Double, Double)] = [
            "yellow": (1, 1, 0), "green": (0, 1, 0), "cyan": (0, 1, 1),
            "magenta": (1, 0, 1), "blue": (0, 0, 1), "red": (1, 0, 0),
            "darkyellow": (0.5, 0.5, 0), "darkgreen": (0, 0.5, 0),
            "darkcyan": (0, 0.5, 0.5), "darkmagenta": (0.5, 0, 0.5),
            "darkblue": (0, 0, 0.5), "darkred": (0.5, 0, 0),
            "black": (0, 0, 0), "white": (1, 1, 1),
            "darkgray": (0.5, 0.5, 0.5), "lightgray": (0.75, 0.75, 0.75),
        ]
        guard let (r, g, b) = map[name.lowercased()] else { return nil }
        return CodableColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }

    private func parseCoreProps(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        metadata.title   = extractTag(s, "dc:title")   ?? ""
        metadata.author  = extractTag(s, "dc:creator") ?? ""
        metadata.subject = extractTag(s, "dc:subject") ?? ""
        // v0.2.1: keywords (dc:keywords или cp:keywords, разделитель — запятая или ;)
        if let kw = extractTag(s, "cp:keywords") ?? extractTag(s, "dc:keywords"), !kw.isEmpty {
            metadata.keywords = kw.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let lang = extractTag(s, "dc:language"), !lang.isEmpty {
            metadata.language = lang
        }
    }

    private func extractTag(_ s: String, _ tag: String) -> String? {
        let open = "<\(tag)>", close = "</\(tag)>"
        guard let o = s.range(of: open),
              let c = s.range(of: close, range: o.upperBound..<s.endIndex) else { return nil }
        return String(s[o.upperBound..<c.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Сериализация

private final class OoxmlDocumentSerializer {
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

// MARK: - ZIP-архив

private func buildArchive(parts: [String: Data]) throws -> Data {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DocxEdit-\(UUID().uuidString)", isDirectory: true)
    let stagingDir = tempDir.appendingPathComponent("staging", isDirectory: true)
    let zipURL    = tempDir.appendingPathComponent("output.zip")

    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

    for (path, data) in parts {
        let fileURL = stagingDir.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
    }

    guard let archive = try? Archive(url: zipURL, accessMode: .create) else {
        throw DocumentError.ioError("Не удалось создать ZIP-архив")
    }
    try addDirectoryToArchive(archive: archive, baseURL: stagingDir, directory: stagingDir, prefix: "")
    return try Data(contentsOf: zipURL)
}

private func addDirectoryToArchive(archive: Archive, baseURL: URL, directory: URL, prefix: String) throws {
    let fm = FileManager.default
    for item in try fm.contentsOfDirectory(atPath: directory.path) {
        let itemURL   = directory.appendingPathComponent(item)
        let entryPath = prefix.isEmpty ? item : "\(prefix)/\(item)"
        var isDir: ObjCBool = false
        fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            try addDirectoryToArchive(archive: archive, baseURL: baseURL, directory: itemURL, prefix: entryPath)
        } else {
            // relativeTo — корень staging: ZIPFoundation читает файл по baseURL+entryPath.
            // Раньше передавался каталог файла → путь задваивался (docProps/docProps/core.xml).
            try archive.addEntry(
                with: entryPath,
                relativeTo: baseURL,
                compressionMethod: .deflate
            )
        }
    }
}

// v0.5.2: OOXML `w:u w:val=…` ↔ UnderlineStyle.
// До v0.5.2 варианты double/dotted/dashed молча схлопывались в .single и на
// парсере, и на writer — теряя стиль подчёркивания при DOCX round-trip.
enum OoxmlUnderlineMapper {
    static func parse(_ val: String) -> UnderlineStyle {
        switch val {
        case "none":          return .none
        case "double", "doubleThick": return .double
        case "dotted", "dottedThick", "dotDash", "dotDotDash": return .dotted
        case "dash", "dashed", "dashLong", "dashLongHeavy", "dashDotHeavy", "dashDotDotHeavy": return .dashed
        default:              return .single
        }
    }
}
