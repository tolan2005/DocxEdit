//
//  DocumentModel.swift
//  DocxCore
//
//  Базовая модель документа DocxEdit R01.
//  Не зависит от UI/AppKit. Маппится в NSAttributedString слоем UI.
//
//  Архитектура: DocumentModel → Sections → Blocks (Paragraph/Table) → Runs
//

import Foundation
import CoreGraphics

// MARK: - Корень документа

/// Модель документа. Содержит секции, метаданные, настройки страницы.
public struct DocumentModel: Codable, Equatable, Sendable {
    public var metadata: DocumentMetadata
    public var pageSettings: PageSettings
    public var sections: [DocumentSection]
    public var styles: DocumentStyles
    public var headerFooter: HeaderFooter
    /// v0.4.4 (R06): треды комментариев (содержимое). Привязка к тексту — через
    /// custom NSAttributedString-ключ `.docxEditCommentId` (см. DESIGN_R06.md §3).
    public var comments: [CommentThread]

    /// v0.5.2 (R07): сноски документа. Привязка — `Run.footnoteId`.
    public var footnotes: [Footnote]

    /// v1.5.1 (DESIGN_HEADER_FOOTER.md): сырые части колонтитулов из исходного
    /// пакета — lossless passthrough при экспорте, если колонтитул не
    /// редактировался (`headerFooterEdited == false`). Ключ — слот:
    /// "headerDefault" / "headerFirst" / "headerEven" / "footerDefault" /
    /// "footerFirst" / "footerEven". Слоты резолвятся при импорте через
    /// document.xml.rels + headerReference (не по имени файла!).
    public var preservedHeaderFooter: [String: PreservedHFPart]

    /// v1.5.1: true — пользователь редактировал колонтитул через диалог;
    /// экспорт регенерирует части из модели (passthrough отключён).
    public var headerFooterEdited: Bool

    /// v1.5.2 (DESIGN_HEADER_FOOTER.md): lossless passthrough ПРОЧИХ частей
    /// пакета, которые мы не парсим и не генерируем (customXml/*, word/theme/*,
    /// word/fontTable.xml, word/webSettings.xml, word/endnotes.xml,
    /// docProps/app.xml и любые неизвестные). Пишутся при экспорте как есть.
    /// Ключ — путь в пакете ("word/theme/theme1.xml").
    public var preservedParts: [String: Data]

    /// Content-Type для preservedParts (PartName без ведущего слэша →
    /// ContentType из исходного [Content_Types].xml) — нужен для валидного
    /// пакета при записи preserved-частей.
    public var preservedContentTypes: [String: String]

    /// v1.5.2: исходный word/settings.xml (целиком). При экспорте пишется
    /// как есть; при `headerFooter.differentOddEven` в него инжектится
    /// `<w:evenAndOddHeaders/>` (раньше мы писали свой минимальный settings.xml,
    /// теряя compat/zoom/proofState и др. настройки документа).
    public var preservedSettingsXml: Data?

    /// v1.5.4 (DESIGN_HEADER_FOOTER.md бэклог P0): неизвестные дочерние
    /// элементы `<w:sectPr>` (w:cols — многоколоночная вёрстка, w:docGrid,
    /// w:vAlign, w:pgNumType, w:pgBorders и др.) — сырой XML-фрагмент,
    /// инжектится в генерируемый sectPr при экспорте. Редактор рендерит
    /// одну колонку, но при open→save вёрстка не теряется.
    public var preservedSectPrExtras: String?

    public init(
        metadata: DocumentMetadata = .init(),
        pageSettings: PageSettings = .a4Portrait,
        sections: [DocumentSection] = [DocumentSection()],
        styles: DocumentStyles = .defaultStyles,
        headerFooter: HeaderFooter = .init(),
        comments: [CommentThread] = [],
        footnotes: [Footnote] = [],
        preservedHeaderFooter: [String: PreservedHFPart] = [:],
        headerFooterEdited: Bool = false,
        preservedParts: [String: Data] = [:],
        preservedContentTypes: [String: String] = [:],
        preservedSettingsXml: Data? = nil,
        preservedSectPrExtras: String? = nil
    ) {
        self.metadata = metadata
        self.pageSettings = pageSettings
        self.sections = sections
        self.styles = styles
        self.headerFooter = headerFooter
        self.comments = comments
        self.footnotes = footnotes
        self.preservedHeaderFooter = preservedHeaderFooter
        self.headerFooterEdited = headerFooterEdited
        self.preservedParts = preservedParts
        self.preservedContentTypes = preservedContentTypes
        self.preservedSettingsXml = preservedSettingsXml
        self.preservedSectPrExtras = preservedSectPrExtras
    }

    // Совместимость декодирования старых моделей без headerFooter/comments/footnotes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try c.decode(DocumentMetadata.self, forKey: .metadata)
        pageSettings = try c.decode(PageSettings.self, forKey: .pageSettings)
        sections = try c.decode([DocumentSection].self, forKey: .sections)
        styles = try c.decode(DocumentStyles.self, forKey: .styles)
        headerFooter = try c.decodeIfPresent(HeaderFooter.self, forKey: .headerFooter) ?? .init()
        comments = try c.decodeIfPresent([CommentThread].self, forKey: .comments) ?? []
        footnotes = try c.decodeIfPresent([Footnote].self, forKey: .footnotes) ?? []
        preservedHeaderFooter = try c.decodeIfPresent([String: PreservedHFPart].self, forKey: .preservedHeaderFooter) ?? [:]
        headerFooterEdited = try c.decodeIfPresent(Bool.self, forKey: .headerFooterEdited) ?? false
        preservedParts = try c.decodeIfPresent([String: Data].self, forKey: .preservedParts) ?? [:]
        preservedContentTypes = try c.decodeIfPresent([String: String].self, forKey: .preservedContentTypes) ?? [:]
        preservedSettingsXml = try c.decodeIfPresent(Data.self, forKey: .preservedSettingsXml)
        preservedSectPrExtras = try c.decodeIfPresent(String.self, forKey: .preservedSectPrExtras)
    }
}

/// v1.5.1 (DESIGN_HEADER_FOOTER.md): сырая часть колонтитула для lossless
/// passthrough. Хранит XML части, её .rels (target'ы media переписаны на
/// уникальные имена `hfp_<slot>_<name>` — во избежание коллизий с
/// генерируемыми `media/imageN`) и сами media-данные под новыми именами.
public struct PreservedHFPart: Codable, Equatable, Sendable {
    /// Имя части относительно word/ — например "header2.xml".
    public var partName: String
    /// Байты word/<partName>.
    public var xml: Data
    /// Байты word/_rels/<partName>.rels (nil — у части нет rels).
    public var relsXml: Data?
    /// Media-файлы, на которые ссылается rels: новое имя (hfp_…) → байты.
    public var media: [String: Data]
    /// v1.5.3: плавающие изображения (wp:anchor) с позициями — для отрисовки
    /// в редакторе (DocxTextView). Ссылки — через mediaName в `media`.
    public var images: [HFImage]

    public init(partName: String, xml: Data, relsXml: Data? = nil,
                media: [String: Data] = [:], images: [HFImage] = []) {
        self.partName = partName
        self.xml = xml
        self.relsXml = relsXml
        self.media = media
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case partName, xml, relsXml, media, images
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partName = try c.decode(String.self, forKey: .partName)
        xml = try c.decode(Data.self, forKey: .xml)
        relsXml = try c.decodeIfPresent(Data.self, forKey: .relsXml)
        media = try c.decodeIfPresent([String: Data].self, forKey: .media) ?? [:]
        images = try c.decodeIfPresent([HFImage].self, forKey: .images) ?? []
    }
}

/// v1.5.3: плавающее изображение колонтитула (wp:anchor в header/footer-части).
/// Координаты — EMU (1 pt = 12700 EMU): x — wp:positionH от колонки текста,
/// y — wp:positionV от абзаца колонтитула, cx/cy — wp:extent.
public struct HFImage: Codable, Equatable, Sendable {
    public var mediaName: String   // ключ в PreservedHFPart.media (hfp_…)
    public var xEMU: Int
    public var yEMU: Int
    public var cxEMU: Int
    public var cyEMU: Int

    public init(mediaName: String, xEMU: Int, yEMU: Int, cxEMU: Int, cyEMU: Int) {
        self.mediaName = mediaName
        self.xEMU = xEMU
        self.yEMU = yEMU
        self.cxEMU = cxEMU
        self.cyEMU = cyEMU
    }
}

/// v0.4.4 (R06): тред комментария. Один тред = один якорь в тексте (диапазон
/// с одинаковым `.docxEditCommentId`), в нём — исходный комментарий + ответы.
public struct CommentThread: Codable, Equatable, Sendable, Identifiable {
    public var id: String            // UUID
    public var author: String
    public var date: Date
    public var text: String
    public var replies: [CommentReply]
    public var resolved: Bool

    public init(id: String = UUID().uuidString, author: String, date: Date = Date(),
                text: String, replies: [CommentReply] = [], resolved: Bool = false) {
        self.id = id
        self.author = author
        self.date = date
        self.text = text
        self.replies = replies
        self.resolved = resolved
    }
}

public struct CommentReply: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var author: String
    public var date: Date
    public var text: String

    public init(id: String = UUID().uuidString, author: String, date: Date = Date(), text: String) {
        self.id = id
        self.author = author
        self.date = date
        self.text = text
    }
}

/// Колонтитулы документа (верхний/нижний) с выравниванием. Текст может содержать
/// плейсхолдеры `{page}` (номер страницы), `{pages}` (всего страниц), `{date}`.
public struct HeaderFooter: Codable, Equatable, Sendable {
    public var headerText: String
    public var footerText: String
    public var headerAlignment: TextAlignment
    public var footerAlignment: TextAlignment
    /// v0.2.3 (R04): «Первая страница отличается» — свой колонтитул для стр. 1.
    /// Когда true, используются `firstHeaderText`/`firstFooterText` для страницы 1;
    /// иначе стр. 1 использует основной. DOCX: `<w:titlePg/>` в sectPr + headerReference type="first".
    public var differentFirstPage: Bool
    public var firstHeaderText: String
    public var firstFooterText: String
    public var firstHeaderAlignment: TextAlignment
    public var firstFooterAlignment: TextAlignment
    /// v0.2.3 (R04): «Разные для чётных/нечётных страниц» — свой колонтитул для чётных.
    /// Когда true, используется `evenHeaderText`/`evenFooterText` для чётных страниц;
    /// нечётные — основной. DOCX: `<w:evenAndOddHeaders/>` в settings.xml + headerReference type="even".
    public var differentOddEven: Bool
    public var evenHeaderText: String
    public var evenFooterText: String
    public var evenHeaderAlignment: TextAlignment
    public var evenFooterAlignment: TextAlignment

    public init(headerText: String = "", footerText: String = "",
                headerAlignment: TextAlignment = .center,
                footerAlignment: TextAlignment = .center,
                differentFirstPage: Bool = false,
                firstHeaderText: String = "",
                firstFooterText: String = "",
                firstHeaderAlignment: TextAlignment = .center,
                firstFooterAlignment: TextAlignment = .center,
                differentOddEven: Bool = false,
                evenHeaderText: String = "",
                evenFooterText: String = "",
                evenHeaderAlignment: TextAlignment = .center,
                evenFooterAlignment: TextAlignment = .center) {
        self.headerText = headerText
        self.footerText = footerText
        self.headerAlignment = headerAlignment
        self.footerAlignment = footerAlignment
        self.differentFirstPage = differentFirstPage
        self.firstHeaderText = firstHeaderText
        self.firstFooterText = firstFooterText
        self.firstHeaderAlignment = firstHeaderAlignment
        self.firstFooterAlignment = firstFooterAlignment
        self.differentOddEven = differentOddEven
        self.evenHeaderText = evenHeaderText
        self.evenFooterText = evenFooterText
        self.evenHeaderAlignment = evenHeaderAlignment
        self.evenFooterAlignment = evenFooterAlignment
    }

    public var isEmpty: Bool {
        headerText.isEmpty && footerText.isEmpty
            && firstHeaderText.isEmpty && firstFooterText.isEmpty
            && evenHeaderText.isEmpty && evenFooterText.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case headerText, footerText, headerAlignment, footerAlignment
        case differentFirstPage, firstHeaderText, firstFooterText,
             firstHeaderAlignment, firstFooterAlignment
        case differentOddEven, evenHeaderText, evenFooterText,
             evenHeaderAlignment, evenFooterAlignment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.headerText = try c.decodeIfPresent(String.self, forKey: .headerText) ?? ""
        self.footerText = try c.decodeIfPresent(String.self, forKey: .footerText) ?? ""
        self.headerAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .headerAlignment) ?? .center
        self.footerAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .footerAlignment) ?? .center
        self.differentFirstPage = try c.decodeIfPresent(Bool.self, forKey: .differentFirstPage) ?? false
        self.firstHeaderText = try c.decodeIfPresent(String.self, forKey: .firstHeaderText) ?? ""
        self.firstFooterText = try c.decodeIfPresent(String.self, forKey: .firstFooterText) ?? ""
        self.firstHeaderAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .firstHeaderAlignment) ?? .center
        self.firstFooterAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .firstFooterAlignment) ?? .center
        self.differentOddEven = try c.decodeIfPresent(Bool.self, forKey: .differentOddEven) ?? false
        self.evenHeaderText = try c.decodeIfPresent(String.self, forKey: .evenHeaderText) ?? ""
        self.evenFooterText = try c.decodeIfPresent(String.self, forKey: .evenFooterText) ?? ""
        self.evenHeaderAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .evenHeaderAlignment) ?? .center
        self.evenFooterAlignment = try c.decodeIfPresent(TextAlignment.self, forKey: .evenFooterAlignment) ?? .center
    }
}

// MARK: - Отчёт об импорте (v0.1.56)

/// Список OOXML-элементов документа, которые парсер узнал, но не смог
/// восстановить полноценно (сложные поля, VML/SmartArt, плавающие объекты и т.п.).
/// Показывается пользователю в диалоге «Отчёт об открытии» — помогает понять,
/// что мы «съели» при импорте, и полезен для bug-reports.
public struct ImportReport: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// Читаемая категория: «Сложные поля», «Плавающие изображения» и т.п.
        public var category: String
        /// Технический ярлык OOXML-элемента: `w:fldChar`, `wp:anchor`.
        public var element: String
        /// Сколько раз встретилось.
        public var count: Int
        /// Дополнительное описание (что именно потеряется).
        public var explanation: String

        public init(category: String, element: String, count: Int, explanation: String) {
            self.category = category
            self.element = element
            self.count = count
            self.explanation = explanation
        }
    }
    public var entries: [Entry]
    public var isEmpty: Bool { entries.isEmpty }

    public init(entries: [Entry] = []) { self.entries = entries }

    /// v1.5.1: слияние с дополнительными записями (например, колонтитулы) —
    /// результат отсортирован по частоте, как в buildReport.
    public func merging(_ extra: [Entry]) -> ImportReport {
        ImportReport(entries: (entries + extra).sorted { $0.count > $1.count })
    }
}

// MARK: - Метаданные

public struct DocumentMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var author: String
    public var subject: String
    public var keywords: [String]
    public var createdAt: Date
    public var modifiedAt: Date
    public var language: String  // BCP-47, e.g. "ru-RU", "en-US"

    public init(
        title: String = "",
        author: String = "",
        subject: String = "",
        keywords: [String] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        language: String = "ru-RU"
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.language = language
    }
}

// MARK: - Параметры страницы

public struct PageSettings: Codable, Equatable, Sendable {
    public var paperSize: PaperSize
    public var orientation: PageOrientation
    public var margins: PageMargins
    /// v0.2.2 (R04): зеркальные поля. Когда true, левое/правое поле меняются местами
    /// на чётных страницах (для брошюрной верстки, где левое поле «внутреннее» — у
    /// корешка, правое — «внешнее»). DOCX: `<w:pgMar w:mirrorMargins="…"/>` в sectPr.
    public var mirrorMargins: Bool

    public init(
        paperSize: PaperSize = .a4,
        orientation: PageOrientation = .portrait,
        margins: PageMargins = .standard,
        mirrorMargins: Bool = false
    ) {
        self.paperSize = paperSize
        self.orientation = orientation
        self.margins = margins
        self.mirrorMargins = mirrorMargins
    }

    private enum CodingKeys: String, CodingKey { case paperSize, orientation, margins, mirrorMargins }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.paperSize = try c.decode(PaperSize.self, forKey: .paperSize)
        self.orientation = try c.decode(PageOrientation.self, forKey: .orientation)
        self.margins = try c.decode(PageMargins.self, forKey: .margins)
        self.mirrorMargins = try c.decodeIfPresent(Bool.self, forKey: .mirrorMargins) ?? false
    }

    /// Размер листа в пунктах (после применения ориентации).
    public var pageSizeInPoints: CGSize {
        let base = paperSize.sizeInPoints
        switch orientation {
        case .portrait: return base
        case .landscape: return CGSize(width: base.height, height: base.width)
        }
    }

    /// Полезная ширина страницы (ширина листа − левое+правое поле) в пунктах.
    /// Используется для расчёта горизонтального смещения таблиц (v0.1.73).
    public var usableWidthInPoints: CGFloat {
        max(1, pageSizeInPoints.width - CGFloat(margins.left) - CGFloat(margins.right))
    }

    public static let a4Portrait = PageSettings(
        paperSize: .a4,
        orientation: .portrait,
        margins: .standard
    )

    public static let letterPortrait = PageSettings(
        paperSize: .letter,
        orientation: .portrait,
        margins: .standard
    )
}

public enum PaperSize: String, Codable, CaseIterable, Sendable {
    case a3, a4, a5, letter, legal, custom

    /// Базовый размер в пунктах (1pt = 1/72 inch, 1 inch = 25.4 mm).
    public var sizeInPoints: CGSize {
        switch self {
        case .a3: return CGSize(width: 842, height: 1191)   // 297 × 420 mm
        case .a4: return CGSize(width: 595, height: 842)    // 210 × 297 mm
        case .a5: return CGSize(width: 420, height: 595)    // 148 × 210 mm
        case .letter: return CGSize(width: 612, height: 792) // 8.5 × 11 in
        case .legal: return CGSize(width: 612, height: 1008) // 8.5 × 14 in
        case .custom: return CGSize(width: 595, height: 842) // по умолчанию A4
        }
    }

    public var displayName: String {
        switch self {
        case .a3: return "A3"
        case .a4: return "A4"
        case .a5: return "A5"
        case .letter: return "Letter"
        case .legal: return "Legal"
        case .custom: return "Пользовательский"
        }
    }
}

public enum PageOrientation: String, Codable, Sendable {
    case portrait, landscape
}

public struct PageMargins: Codable, Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat
    public var right: CGFloat
    public var header: CGFloat
    public var footer: CGFloat
    public var gutter: CGFloat

    public init(
        top: CGFloat,
        bottom: CGFloat,
        left: CGFloat,
        right: CGFloat,
        header: CGFloat = 36,
        footer: CGFloat = 36,
        gutter: CGFloat = 0
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.header = header
        self.footer = footer
        self.gutter = gutter
    }

    /// Стандартные поля: 2 см сверху/снизу, 3 см слева/справа.
    public static let standard = PageMargins(
        top: 56.69,    // 2 см
        bottom: 56.69,
        left: 85.04,   // 3 см
        right: 85.04
    )

    /// Узкие поля: 1.27 см со всех сторон (0.5 in).
    public static let narrow = PageMargins(
        top: 36,
        bottom: 36,
        left: 36,
        right: 36
    )

    /// Широкие поля: 2.54 см со всех сторон (1 in).
    public static let wide = PageMargins(
        top: 72,
        bottom: 72,
        left: 144,  // 1.5 in по бокам
        right: 144
    )
}

// MARK: - Секция

/// Секция документа. В R01 — один раздел на документ; R04 расширяет до multi-section.
public struct DocumentSection: Codable, Equatable, Sendable {
    public var blocks: [Block]

    public init(blocks: [Block] = [Block.paragraph(.empty)]) {
        self.blocks = blocks
    }
}

// MARK: - Блоки документа

public enum Block: Codable, Equatable, Sendable {
    case paragraph(Paragraph)
    case table(TableBlock)
    // R03+: image, listItem (пока список кодируется прямо в Paragraph через listInfo)
}

/// Параграф (абзац) текста.
public struct Paragraph: Codable, Equatable, Sendable {
    public var runs: [Run]
    public var attributes: ParagraphAttributes

    public init(runs: [Run] = [], attributes: ParagraphAttributes = .init()) {
        self.runs = runs
        self.attributes = attributes
    }

    public static let empty = Paragraph(runs: [], attributes: .init())
}

/// Прогон — непрерывная последовательность символов с одинаковыми атрибутами.
public struct Run: Codable, Equatable, Sendable {
    public var text: String
    public var attributes: CharacterAttributes
    /// Inline-изображение (v0.1.52, R03). Если задано, символ `text` — обычно
    /// U+FFFC (Object Replacement Character), а само изображение отрисовывается
    /// через NSTextAttachment. DOCX-сериализация изображений — в v0.1.53.
    public var image: InlineImage?
    /// Гиперссылка (v0.1.54, R03). URL цели; несколько соседних runs могут
    /// делить одну ссылку — при сериализации группируются под одним
    /// `<w:hyperlink r:id>` (см. OoxmlDocumentSerializer.renderParagraph).
    public var hyperlink: String?
    /// v0.4.5 (R06): id треда комментария, к которому принадлежит этот ран.
    /// Заполняется при `DocumentModel.from(attributed:)` из custom-ключа
    /// `.docxEditCommentId`. При сериализации DOCX подряд идущие runs с
    /// одинаковым commentId оборачиваются commentRangeStart/End. MVP-огран.:
    /// один комментарий на ран; вложение/пересечение — не поддерживается.
    public var commentId: String?

    /// v0.4.7 (R06): track-changes — маркер вставки. Формат строки:
    /// `author|iso-date|revId`. DOCX: `<w:ins w:id/author/date>`.
    public var insertion: String?
    /// v0.4.7 (R06): track-changes — маркер удаления. Тот же формат.
    /// DOCX: `<w:del>` (текст пишется как `<w:delText>` вместо `<w:t>`).
    public var deletion: String?

    /// v0.5.2 (R07): id сноски. Ран несёт этот id, если в его позиции стоит
    /// `<w:footnoteReference w:id="X"/>`. Содержимое сноски — в
    /// `DocumentModel.footnotes[id]`.
    public var footnoteId: String?

    /// v0.5.5 (R07): имя закладки-цели перекрёстной ссылки. Соседние runs с
    /// одинаковым `crossRef` при сериализации оборачиваются в
    /// `<w:fldSimple w:instr=" REF <name> \h ">…</w:fldSimple>`.
    public var crossRef: String?

    /// v0.5.6 (R07): маркер «этот ран — часть блока оглавления». Соседние
    /// параграфы, у которых все runs с одинаковым `tocBlock`, при сериализации
    /// оборачиваются в `<w:sdt>` с docPartGallery="Table of Contents" (мейнстрим-
    /// редакторы распознают как автоматическое оглавление с опцией Update Field).
    public var tocBlock: String?

    /// v0.5.8 (R08): ревизия атрибутов рана (track-changes `<w:rPrChange>`).
    /// Формат — "author|date|id", как у `insertion`/`deletion`. Сохраняем ФАКТ
    /// ревизии; **старые** атрибуты (до правки) в MVP не восстанавливаем —
    /// writer эмитит пустой inner rPr. OOXML-читатель покажет балун-подпись автора и
    /// даты, но без детального diff «было/стало» (задача R09/R10).
    public var attributeRevision: String?

    /// v1.5.6: инструкция сложного поля (`w:fldChar` begin + `w:instrText`),
    /// чей результат НАЧИНАЕТСЯ с этого рана. При сериализации ран оборачивается
    /// begin/instrText/separate … end — поле переживает round-trip и остаётся
    /// «живым» (обновляемым) в OOXML-читателях. Только одноабзацные поля
    /// (REF/PAGEREF/SEQ/DATE/…); многоабзацные (TOC) — через tocBlock/SDT.
    public var fieldInstr: String?

    public init(text: String, attributes: CharacterAttributes = .init(),
                image: InlineImage? = nil, hyperlink: String? = nil,
                commentId: String? = nil,
                insertion: String? = nil, deletion: String? = nil,
                footnoteId: String? = nil,
                crossRef: String? = nil,
                tocBlock: String? = nil,
                attributeRevision: String? = nil,
                fieldInstr: String? = nil) {
        self.text = text
        self.attributes = attributes
        self.image = image
        self.hyperlink = hyperlink
        self.commentId = commentId
        self.insertion = insertion
        self.deletion = deletion
        self.footnoteId = footnoteId
        self.crossRef = crossRef
        self.tocBlock = tocBlock
        self.attributeRevision = attributeRevision
        self.fieldInstr = fieldInstr
    }

    // decodeIfPresent — backward-compat со старыми JSON.
    private enum CodingKeys: String, CodingKey {
        case text, attributes, image, hyperlink, commentId, insertion, deletion, footnoteId, crossRef, tocBlock, attributeRevision, fieldInstr
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        attributes = try c.decode(CharacterAttributes.self, forKey: .attributes)
        image = try c.decodeIfPresent(InlineImage.self, forKey: .image)
        hyperlink = try c.decodeIfPresent(String.self, forKey: .hyperlink)
        commentId = try c.decodeIfPresent(String.self, forKey: .commentId)
        insertion = try c.decodeIfPresent(String.self, forKey: .insertion)
        deletion  = try c.decodeIfPresent(String.self, forKey: .deletion)
        footnoteId = try c.decodeIfPresent(String.self, forKey: .footnoteId)
        crossRef = try c.decodeIfPresent(String.self, forKey: .crossRef)
        tocBlock = try c.decodeIfPresent(String.self, forKey: .tocBlock)
        attributeRevision = try c.decodeIfPresent(String.self, forKey: .attributeRevision)
        fieldInstr = try c.decodeIfPresent(String.self, forKey: .fieldInstr)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(attributes, forKey: .attributes)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(hyperlink, forKey: .hyperlink)
        try c.encodeIfPresent(commentId, forKey: .commentId)
        try c.encodeIfPresent(insertion, forKey: .insertion)
        try c.encodeIfPresent(deletion,  forKey: .deletion)
        try c.encodeIfPresent(footnoteId, forKey: .footnoteId)
        try c.encodeIfPresent(crossRef, forKey: .crossRef)
        try c.encodeIfPresent(tocBlock, forKey: .tocBlock)
        try c.encodeIfPresent(attributeRevision, forKey: .attributeRevision)
        try c.encodeIfPresent(fieldInstr, forKey: .fieldInstr)
    }
}

/// v0.5.2 (R07): содержимое сноски. Текст простой (без rich formatting в MVP —
/// расширим на Run[] в следующей итерации, когда UI позволит редактировать).
public struct Footnote: Codable, Equatable, Sendable, Identifiable {
    public var id: String     // строковый w:id из OOXML
    public var text: String
    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// Формат хранения inline-изображения.
public enum InlineImageFormat: String, Codable, Sendable {
    case png, jpeg, gif, tiff
}

/// Режим обтекания изображения текстом (v0.1.102).
/// Модель/DOCX round-trip корректны; редактор пока рендерит все режимы как inline
/// (реальный anchored-layout — задача R04). При открытии в мейнстрим-редакторов обтекание
/// восстанавливается по сохранённому режиму.
public enum InlineImageWrap: String, Codable, Sendable {
    case inline       // в потоке текста (по умолчанию)
    case square       // прямоугольное обтекание
    case tight        // плотное обтекание по контуру
    case topAndBottom // сверху и снизу
    case behindText   // за текстом
    case inFrontOfText // перед текстом
}

/// Данные inline-изображения: raw байты + отображаемый размер в points.
public struct InlineImage: Codable, Equatable, Sendable {
    public var format: InlineImageFormat
    public var data: Data
    /// Отображаемая ширина в points; 0 = использовать натуральный размер.
    public var displayWidth: CGFloat
    /// Отображаемая высота в points; 0 = использовать натуральный размер.
    public var displayHeight: CGFloat
    /// Замещающий текст (accessibility). Пишется в `<wp:docPr descr="…">` при
    /// экспорте DOCX и в `NSTextAttachment.accessibilityLabel` при рендере.
    public var altText: String?
    /// Режим обтекания текстом. Пишется в DOCX как `<wp:anchor>` (для не-inline)
    /// или `<wp:inline>` (для .inline). См. `InlineImageWrap`.
    public var wrap: InlineImageWrap

    public init(format: InlineImageFormat, data: Data,
                displayWidth: CGFloat = 0, displayHeight: CGFloat = 0,
                altText: String? = nil,
                wrap: InlineImageWrap = .inline) {
        self.format = format
        self.data = data
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.altText = altText
        self.wrap = wrap
    }
}

// MARK: - Атрибуты символов

public struct CharacterAttributes: Codable, Equatable, Sendable {
    public var fontName: String?
    public var fontSize: CGFloat?
    public var bold: Bool
    public var italic: Bool
    public var underline: UnderlineStyle
    public var strikethrough: Bool
    public var textColor: CodableColor?
    public var highlightColor: CodableColor?
    public var superscript: Bool
    public var `subscript`: Bool
    public var smallCaps: Bool
    public var allCaps: Bool
    /// ID применённого символьного стиля (Strong/Emphasis/CodeChar) — пишется в
    /// DOCX как `<w:rStyle w:val="…"/>`. nil = стиль не применён.
    public var styleId: String?

    public init(
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        bold: Bool = false,
        italic: Bool = false,
        underline: UnderlineStyle = .none,
        strikethrough: Bool = false,
        textColor: CodableColor? = nil,
        highlightColor: CodableColor? = nil,
        superscript: Bool = false,
        subscript: Bool = false,
        smallCaps: Bool = false,
        allCaps: Bool = false,
        styleId: String? = nil
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.textColor = textColor
        self.highlightColor = highlightColor
        self.superscript = superscript
        self.`subscript` = `subscript`
        self.smallCaps = smallCaps
        self.allCaps = allCaps
        self.styleId = styleId
    }

    public static let `default` = CharacterAttributes()
}

public enum UnderlineStyle: String, Codable, Sendable {
    case none, single, double, dotted, dashed
}

// MARK: - Атрибуты абзаца

public struct ParagraphAttributes: Codable, Equatable, Sendable {
    public var alignment: TextAlignment
    public var lineSpacing: LineSpacing
    public var spaceBefore: CGFloat
    public var spaceAfter: CGFloat
    public var leftIndent: CGFloat
    public var rightIndent: CGFloat
    public var firstLineIndent: CGFloat
    public var hangingIndent: CGFloat
    public var listInfo: ListInfo?
    public var styleId: String?
    /// v1.5.4: пользовательские позиции табуляции (w:tabs). Пустой массив —
    /// стандартные табы через 1.27 см.
    public var tabStops: [TabStop]
    /// v1.5.5: границы абзаца (w:pBdr); nil — без границ.
    public var border: ParagraphBorder?

    public init(
        alignment: TextAlignment = .left,
        lineSpacing: LineSpacing = .multiple(1.15),
        spaceBefore: CGFloat = 0,
        spaceAfter: CGFloat = 8,
        leftIndent: CGFloat = 0,
        rightIndent: CGFloat = 0,
        firstLineIndent: CGFloat = 0,
        hangingIndent: CGFloat = 0,
        listInfo: ListInfo? = nil,
        styleId: String? = nil,
        tabStops: [TabStop] = [],
        border: ParagraphBorder? = nil
    ) {
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.leftIndent = leftIndent
        self.rightIndent = rightIndent
        self.firstLineIndent = firstLineIndent
        self.hangingIndent = hangingIndent
        self.listInfo = listInfo
        self.styleId = styleId
        self.tabStops = tabStops
        self.border = border
    }

    // Совместимость с моделями без tabStops (автосейвы до v1.5.4).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alignment = try c.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .left
        lineSpacing = try c.decodeIfPresent(LineSpacing.self, forKey: .lineSpacing) ?? .multiple(1.15)
        spaceBefore = try c.decodeIfPresent(CGFloat.self, forKey: .spaceBefore) ?? 0
        spaceAfter = try c.decodeIfPresent(CGFloat.self, forKey: .spaceAfter) ?? 8
        leftIndent = try c.decodeIfPresent(CGFloat.self, forKey: .leftIndent) ?? 0
        rightIndent = try c.decodeIfPresent(CGFloat.self, forKey: .rightIndent) ?? 0
        firstLineIndent = try c.decodeIfPresent(CGFloat.self, forKey: .firstLineIndent) ?? 0
        hangingIndent = try c.decodeIfPresent(CGFloat.self, forKey: .hangingIndent) ?? 0
        listInfo = try c.decodeIfPresent(ListInfo.self, forKey: .listInfo)
        styleId = try c.decodeIfPresent(String.self, forKey: .styleId)
        tabStops = try c.decodeIfPresent([TabStop].self, forKey: .tabStops) ?? []
        border = try c.decodeIfPresent(ParagraphBorder.self, forKey: .border)
    }
}

public enum TextAlignment: String, Codable, Sendable {
    case left, center, right, justify
}

// MARK: - Позиции табуляции (v1.5.4)

/// Таб-стоп абзаца (w:tabs/w:tab в DOCX). position — в пунктах от левого поля
/// текста; decimal на macOS не рендерится — маппится в .right на импорте.
public struct TabStop: Codable, Equatable, Sendable {
    public var position: CGFloat
    public var alignment: TextAlignment   // justify не используется в DOCX табах

    public init(position: CGFloat, alignment: TextAlignment = .left) {
        self.position = position
        self.alignment = alignment
    }
}

// MARK: - Границы абзаца (v1.5.5)

/// Границы абзаца (`<w:pBdr>` в DOCX). Классический кейс — линия под
/// заголовком/колонтитулом (bottom). Только сплошная линия (single) —
/// пунктирные/двойные сводятся к single при импорте.
public struct ParagraphBorder: Codable, Equatable, Sendable {
    public var top: Bool
    public var bottom: Bool
    public var left: Bool
    public var right: Bool
    /// Толщина в пунктах (DOCX хранит в 1/8 pt).
    public var width: CGFloat
    public var color: CodableColor?

    public init(top: Bool = false, bottom: Bool = false, left: Bool = false,
                right: Bool = false, width: CGFloat = 0.5, color: CodableColor? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.width = width
        self.color = color
    }

    public var isEmpty: Bool { !top && !bottom && !left && !right }
}

public enum LineSpacing: Codable, Equatable, Sendable {
    case single                // 1.0
    case onePoint15            // 1.15
    case onePoint5             // 1.5
    case double                // 2.0
    case exact(CGFloat)        // точное значение в пунктах
    case multiple(CGFloat)     // множитель (>= 0.5)
    case atLeast(CGFloat)      // минимум

    public var multiplier: CGFloat {
        switch self {
        case .single: return 1.0
        case .onePoint15: return 1.15
        case .onePoint5: return 1.5
        case .double: return 2.0
        case .exact, .atLeast: return 1.0
        case .multiple(let v): return v
        }
    }
}

// MARK: - Списки

public struct ListInfo: Codable, Equatable, Sendable {
    public var listType: ListType
    public var level: Int
    public var continuation: ListContinuation
    public var formatStyle: ListFormatStyle

    public init(
        listType: ListType,
        level: Int = 0,
        continuation: ListContinuation = .continue,
        formatStyle: ListFormatStyle
    ) {
        self.listType = listType
        self.level = max(0, min(level, 8))
        self.continuation = continuation
        self.formatStyle = formatStyle
    }
}

public enum ListType: String, Codable, Sendable {
    case bulleted, numbered
}

public enum ListContinuation: String, Codable, Sendable {
    case `continue`, restart
}

public enum ListFormatStyle: Codable, Equatable, Sendable {
    case bullet(character: String)               // •, ○, ▪
    case decimal                                 // 1, 2, 3
    case lowerLetter                             // a, b, c
    case upperLetter                             // A, B, C
    case lowerRoman                              // i, ii, iii
    case upperRoman                              // I, II, III
    case decimalEnclosedParen                    // 1), 2), 3)
    case lowerLetterParen                        // a), b), c)
    case lowerRomanParen                         // i), ii), iii)
    case decimalNested                           // 1., 1.1., 1.1.1. (составной номер из счётчиков всех уровней)
}

/// Вариант многоуровневого списка: формат маркера для каждого уровня вложенности
/// (как галерея многоуровневых списков в OOXML-редакторах). Уровни глубже `formats.count`
/// циклически повторяют набор. Пресеты общие для редактора (UI-галерея)
/// и DocxIO (заполнение уровней abstractNum в numbering.xml).
public struct MultilevelListVariant: Identifiable, Equatable, Sendable {
    public let id: String
    /// Отображаемое имя в галерее, например "1.  a.  i.".
    public let title: String
    public let listType: ListType
    public let formats: [ListFormatStyle]

    public init(id: String, title: String, listType: ListType, formats: [ListFormatStyle]) {
        self.id = id
        self.title = title
        self.listType = listType
        self.formats = formats
    }

    /// Формат маркера для уровня вложенности (0-8); циклически повторяется.
    public func format(at level: Int) -> ListFormatStyle {
        formats[max(0, level) % formats.count]
    }

    public static let numberedDefault = MultilevelListVariant(
        id: "num-1ai", title: "1.  a.  i.", listType: .numbered,
        formats: [.decimal, .lowerLetter, .lowerRoman])
    public static let numberedNested = MultilevelListVariant(
        id: "num-nested", title: "1.  1.1.  1.1.1.", listType: .numbered,
        formats: [.decimalNested])
    public static let numberedParen = MultilevelListVariant(
        id: "num-paren", title: "1)  a)  i)", listType: .numbered,
        formats: [.decimalEnclosedParen, .lowerLetterParen, .lowerRomanParen])
    public static let numberedHeadings = MultilevelListVariant(
        id: "num-IA1", title: "I.  A.  1.", listType: .numbered,
        formats: [.upperRoman, .upperLetter, .decimal])
    public static let bulletedDefault = MultilevelListVariant(
        id: "bul-std", title: "•  ○  ▪", listType: .bulleted,
        formats: [.bullet(character: "•"), .bullet(character: "○"), .bullet(character: "▪")])
    public static let bulletedDash = MultilevelListVariant(
        id: "bul-dash", title: "–  •  ◦", listType: .bulleted,
        formats: [.bullet(character: "–"), .bullet(character: "•"), .bullet(character: "◦")])

    /// Все пресеты галереи (дефолтные для типа — первыми, для детекции по формату).
    public static let presets: [MultilevelListVariant] = [
        .numberedDefault, .numberedNested, .numberedParen, .numberedHeadings,
        .bulletedDefault, .bulletedDash,
    ]

    /// Дефолтный вариант для типа списка.
    public static func `default`(for type: ListType) -> MultilevelListVariant {
        type == .bulleted ? .bulletedDefault : .numberedDefault
    }
}

// MARK: - Таблица (минимум для R01, расширение в R03)

public enum TableAlignment: String, Codable, Sendable {
    case left, center, right
}

public struct TableBlock: Codable, Equatable, Sendable {
    public var rows: [TableRow]
    public var columnWidths: [CGFloat]
    public var style: TableStyle
    /// Горизонтальное выравнивание таблицы на странице (v0.1.70, R03).
    /// В DOCX сериализуется как `<w:jc>` в `<w:tblPr>`.
    public var alignment: TableAlignment

    public init(rows: [TableRow], columnWidths: [CGFloat] = [], style: TableStyle = .init(),
                alignment: TableAlignment = .left) {
        self.rows = rows
        self.columnWidths = columnWidths
        self.style = style
        self.alignment = alignment
    }
}

public struct TableRow: Codable, Equatable, Sendable {
    public var cells: [TableCell]
    public var height: CGFloat?
    /// Строка-заголовок таблицы: повторяется на каждой странице при печати (v0.1.85).
    /// В DOCX — `<w:tblHeader/>` внутри `<w:trPr>`.
    public var isHeader: Bool

    public init(cells: [TableCell], height: CGFloat? = nil, isHeader: Bool = false) {
        self.cells = cells
        self.height = height
        self.isHeader = isHeader
    }
}

public struct TableCell: Codable, Equatable, Sendable {
    public var blocks: [Block]
    public var colSpan: Int
    public var rowSpan: Int
    public var width: CGFloat?
    public var backgroundColor: CodableColor?

    public init(
        blocks: [Block] = [.paragraph(.empty)],
        colSpan: Int = 1,
        rowSpan: Int = 1,
        width: CGFloat? = nil,
        backgroundColor: CodableColor? = nil
    ) {
        self.blocks = blocks
        self.colSpan = colSpan
        self.rowSpan = rowSpan
        self.width = width
        self.backgroundColor = backgroundColor
    }
}

public struct TableStyle: Codable, Equatable, Sendable {
    public var hasBorders: Bool
    public var borderColor: CodableColor?
    public var borderWidth: CGFloat

    public init(hasBorders: Bool = true, borderColor: CodableColor? = nil, borderWidth: CGFloat = 0.5) {
        self.hasBorders = hasBorders
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }
}

// MARK: - Стили документа

public struct DocumentStyles: Codable, Equatable, Sendable {
    public var paragraphStyles: [String: ParagraphStyleDef]
    public var characterStyles: [String: CharacterStyleDef]
    public var defaultFontName: String
    public var defaultFontSize: CGFloat

    public init(
        paragraphStyles: [String: ParagraphStyleDef] = [:],
        characterStyles: [String: CharacterStyleDef] = [:],
        defaultFontName: String = "Times New Roman",
        defaultFontSize: CGFloat = 12
    ) {
        self.paragraphStyles = paragraphStyles
        self.characterStyles = characterStyles
        self.defaultFontName = defaultFontName
        self.defaultFontSize = defaultFontSize
    }

    /// Пустые словари: стили НЕ переопределены на уровне документа, поэтому
    /// `effectiveParagraphStyle`/`effectiveCharacterStyle` берут реальные
    /// определения из `StandardParagraphStyle`/`StandardCharacterStyle` (Заголовок 1 —
    /// 26pt синий и т.д.). Раньше здесь лежали «бланковые» defs (только name+basedOn,
    /// размеры/цвета nil), из-за чего каждый стиль резолвился в размер 11 чёрный —
    /// «все стили выглядят одинаково» (фидбек пользователя). Запись сюда появляется
    /// только при (а) правке стиля в диалоге «Стили…», (б) импорте DOCX со своими
    /// определениями стилей.
    public static let defaultStyles = DocumentStyles(
        paragraphStyles: [:],
        characterStyles: [:]
    )
}

public struct ParagraphStyleDef: Codable, Equatable, Sendable {
    public var name: String
    public var basedOn: String?
    /// Семейство шрифта (nil — семейство из «Шрифт «Обычный»» / «Шрифт заголовков» настроек).
    public var fontName: String?
    /// Абсолютный размер шрифта; nil — наследуется от base/default.
    public var fontSize: CGFloat?
    public var bold: Bool?
    public var italic: Bool?
    public var textColor: CodableColor?
    /// Цвет заливки текста (highlight). nil — без заливки.
    public var backgroundColor: CodableColor?
    public var spaceBefore: CGFloat?
    public var spaceAfter: CGFloat?
    /// Выравнивание абзаца стиля; nil — наследуется/по умолчанию (по левому краю).
    public var alignment: TextAlignment?
    /// Уровень заголовка (0-9) для DOCX `<w:outlineLvl>` — базис для оглавления.
    public var outlineLevel: Int?

    public init(
        name: String,
        basedOn: String? = nil,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        textColor: CodableColor? = nil,
        backgroundColor: CodableColor? = nil,
        spaceBefore: CGFloat? = nil,
        spaceAfter: CGFloat? = nil,
        alignment: TextAlignment? = nil,
        outlineLevel: Int? = nil
    ) {
        self.name = name
        self.basedOn = basedOn
        self.fontName = fontName
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.alignment = alignment
        self.outlineLevel = outlineLevel
    }
}

/// Список стандартных стилей абзацев для UI пикера и записи styles.xml.
/// Значения размеров/интервалов приближены к дефолтам OOXML.
public struct StandardParagraphStyle: Identifiable, Sendable {
    public let id: String
    public let def: ParagraphStyleDef
    public var name: String { def.name }
    public init(id: String, def: ParagraphStyleDef) {
        self.id = id
        self.def = def
    }

    // Значения приближены к дефолтам OOXML defaults:
    // Normal: 11pt, чёрный. Heading 1..6: Calibri Light-подобный слой + разные
    // размеры и синие цвета #2E74B5 (Accent1 dark 1) / #1F3864 (Accent1 dark 2).
    // fontName: nil означает «шрифт из настроек» (см. AppPreferences).
    private static let headingBlue     = CodableColor(red: 0x2E/255.0, green: 0x74/255.0, blue: 0xB5/255.0)
    private static let headingDarkBlue = CodableColor(red: 0x1F/255.0, green: 0x38/255.0, blue: 0x64/255.0)

    public static let normal = StandardParagraphStyle(
        id: "Normal",
        def: ParagraphStyleDef(name: "Обычный", basedOn: nil,
                               fontSize: 11, bold: false, italic: false,
                               spaceBefore: 0, spaceAfter: 8))
    public static let heading1 = StandardParagraphStyle(
        id: "Heading1",
        def: ParagraphStyleDef(name: "Заголовок 1", basedOn: "Normal",
                               fontSize: 26, bold: false, italic: false,
                               textColor: headingBlue,
                               spaceBefore: 24, spaceAfter: 0, outlineLevel: 0))
    public static let heading2 = StandardParagraphStyle(
        id: "Heading2",
        def: ParagraphStyleDef(name: "Заголовок 2", basedOn: "Normal",
                               fontSize: 20, bold: false, italic: false,
                               textColor: headingBlue,
                               spaceBefore: 8, spaceAfter: 0, outlineLevel: 1))
    public static let heading3 = StandardParagraphStyle(
        id: "Heading3",
        def: ParagraphStyleDef(name: "Заголовок 3", basedOn: "Normal",
                               fontSize: 16, bold: false, italic: false,
                               textColor: headingBlue,
                               spaceBefore: 4, spaceAfter: 0, outlineLevel: 2))
    public static let heading4 = StandardParagraphStyle(
        id: "Heading4",
        def: ParagraphStyleDef(name: "Заголовок 4", basedOn: "Normal",
                               fontSize: 14, bold: false, italic: true,
                               textColor: headingBlue,
                               spaceBefore: 4, spaceAfter: 0, outlineLevel: 3))
    public static let heading5 = StandardParagraphStyle(
        id: "Heading5",
        def: ParagraphStyleDef(name: "Заголовок 5", basedOn: "Normal",
                               fontSize: 12, bold: false, italic: false,
                               textColor: headingDarkBlue,
                               spaceBefore: 4, spaceAfter: 0, outlineLevel: 4))
    public static let heading6 = StandardParagraphStyle(
        id: "Heading6",
        def: ParagraphStyleDef(name: "Заголовок 6", basedOn: "Normal",
                               fontSize: 12, bold: false, italic: true,
                               textColor: headingDarkBlue,
                               spaceBefore: 4, spaceAfter: 0, outlineLevel: 5))

    public static let all: [StandardParagraphStyle] = [
        normal, heading1, heading2, heading3, heading4, heading5, heading6,
        quote, codeBlock, horizontalRule
    ]

    // v1.4.2 (ADR-049): стили для Markdown-конструкций. Quote — курсив с
    // серым текстом (отступ задаётся на уровне ParagraphAttributes.leftIndent
    // при импорте MD, чтобы не засорять раны); CodeBlock — моноширинный с
    // серой заливкой; HorizontalRule — маркерный стиль пустого абзаца
    /// (линия рисуется DocxLayoutManager, в MD экспортируется как `---`).
    public static let quote = StandardParagraphStyle(
        id: "Quote",
        def: ParagraphStyleDef(name: "Цитата", basedOn: "Normal",
                               italic: true,
                               textColor: CodableColor(red: 0.35, green: 0.35, blue: 0.38),
                               spaceBefore: 4, spaceAfter: 8))
    public static let codeBlock = StandardParagraphStyle(
        id: "CodeBlock",
        def: ParagraphStyleDef(name: "Блок кода", basedOn: "Normal",
                               fontName: "Menlo", fontSize: 11,
                               backgroundColor: CodableColor(red: 0.94, green: 0.94, blue: 0.95),
                               spaceBefore: 4, spaceAfter: 8))
    public static let horizontalRule = StandardParagraphStyle(
        id: "HorizontalRule",
        def: ParagraphStyleDef(name: "Горизонтальная линия", basedOn: "Normal",
                               spaceBefore: 4, spaceAfter: 4))

    public static func find(id: String) -> StandardParagraphStyle? {
        all.first { $0.id == id }
    }
}

public struct CharacterStyleDef: Codable, Equatable, Sendable {
    public var name: String
    public var fontName: String?
    public var fontSize: CGFloat?
    public var bold: Bool
    public var italic: Bool

    public init(
        name: String,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        bold: Bool = false,
        italic: Bool = false
    ) {
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
    }
}

public struct StandardCharacterStyle: Identifiable, Sendable {
    public let id: String
    public let def: CharacterStyleDef

    public init(id: String, def: CharacterStyleDef) {
        self.id = id
        self.def = def
    }

    public static let strong    = StandardCharacterStyle(id: "Strong",
        def: CharacterStyleDef(name: "Сильное", bold: true))
    public static let emphasis  = StandardCharacterStyle(id: "Emphasis",
        def: CharacterStyleDef(name: "Выделение", italic: true))
    public static let code      = StandardCharacterStyle(id: "CodeChar",
        def: CharacterStyleDef(name: "Код", fontName: "Menlo", fontSize: 11))

    public static let all: [StandardCharacterStyle] = [strong, emphasis, code]

    public static func find(id: String) -> StandardCharacterStyle? {
        all.first { $0.id == id }
    }
}

// MARK: - Цвет

/// Codable-обёртка над RGBA, совместимая с Color (SwiftUI) и NSColor (AppKit).
public struct CodableColor: Codable, Equatable, Sendable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public static let black = CodableColor(red: 0, green: 0, blue: 0)
    public static let white = CodableColor(red: 1, green: 1, blue: 1)
    public static let red   = CodableColor(red: 1, green: 0, blue: 0)
    public static let blue  = CodableColor(red: 0, green: 0, blue: 1)
    public static let yellow = CodableColor(red: 1, green: 0.95, blue: 0)

    public static func fromHex(_ hex: String) -> CodableColor? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 || h.count == 8, let val = UInt32(h, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if h.count == 8 {
            r = CGFloat((val >> 24) & 0xFF) / 255
            g = CGFloat((val >> 16) & 0xFF) / 255
            b = CGFloat((val >> 8) & 0xFF) / 255
            a = CGFloat(val & 0xFF) / 255
        } else {
            r = CGFloat((val >> 16) & 0xFF) / 255
            g = CGFloat((val >> 8) & 0xFF) / 255
            b = CGFloat(val & 0xFF) / 255
            a = 1.0
        }
        return CodableColor(red: r, green: g, blue: b, alpha: a)
    }
}
