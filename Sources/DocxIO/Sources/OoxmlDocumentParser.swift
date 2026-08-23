//
//  Распил монолита DocxIO.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Типы перемещены без изменения кода; private → internal (file-scope
//  private в общем файле был de-facto fileprivate, типы нужны кросс-файл).
//

import Foundation
import ZIPFoundation
import DocxCore

// MARK: - Парсер документа

final class OoxmlDocumentParser: NSObject, XMLParserDelegate {
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

    /// v1.6.1: OMML-формулы (m:oMath/m:oMathPara). Импортируем текст формулы
    /// (m:t) как обычный текст — раньше содержимое формул терялось целиком.
    /// Живой round-trip формул (обратно в OMML) не поддерживается: в отчёте
    /// об открытии — запись (уже была).
    private var mathDepth = 0
    private var mathBuffer = ""

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
        add("w:object",        "Legacy-объекты (OLE)",  "Встроенный OLE-объект (Excel-лист, формула и т.п.). Импортируется картинка-превью; редактирование объекта недоступно.")
        add("m:oMath",         "Формулы (OMML)",        "Формула Office Math — импортирована как обычный текст (обратно в формулу при сохранении не превращается).")
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

    /// v1.6.4: ошибка разбора document.xml (nil — файл распарсен целиком).
    /// XMLParser молча обрывает работу на первой синтаксической ошибке —
    /// пользователь видел обрезанный документ без предупреждения.
    private(set) var parseError: Error? = nil

    func parse(documentXml: Data, corePropsXml: Data?) throws -> DocumentModel {
        if let corePropsXml { parseCoreProps(corePropsXml) }
        let parser = XMLParser(data: documentXml)
        parser.delegate = self
        parser.parse()
        parseError = parser.parserError
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

        case "w:framePr":
            // v1.6.1: буквица/рамка абзаца — сохраняем атрибуты как есть.
            if inParaProperties { currentDirectParaProps.framePr = a }

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

        // v1.6.1: OMML-формула. Считаем один раз на блок (outer-элемент).
        case "m:oMath", "m:oMathPara":
            if mathDepth == 0 { note("m:oMath"); mathBuffer = "" }
            mathDepth += 1
        case "m:t":
            break  // текст формулы — в foundCharacters по mathDepth

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

        // v1.6.1: закрытие OMML. Блочная формула (oMathPara) — отдельным
        // абзацем; строчная (oMath на верхнем уровне) — раном в текущем абзаце.
        case "m:oMathPara":
            mathDepth = 0
            let text = mathBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                appendBlock(.paragraph(Paragraph(
                    runs: [Run(text: text, attributes: buildCharAttrs())],
                    attributes: currentParagraphAttributes())))
            }
            mathBuffer = ""
        case "m:oMath":
            mathDepth = max(0, mathDepth - 1)
            if mathDepth == 0 {
                let text = mathBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if currentParagraph == nil {
                        currentParagraph = Paragraph(runs: [], attributes: currentParagraphAttributes())
                    }
                    currentParagraph?.runs.append(
                        Run(text: text, attributes: buildCharAttrs()))
                }
                mathBuffer = ""
            }

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
        // v1.6.1: текст OMML-формулы (m:t внутри m:oMath[Para]).
        if mathDepth > 0 { mathBuffer += string }
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
