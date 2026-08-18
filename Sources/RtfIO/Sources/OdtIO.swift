//
//  OdtIO.swift
//  RtfIO (v0.6.1, R09 «Beta»)
//
//  Импорт/экспорт OpenDocument Text (`.odt`) через
//  `NSAttributedString.DocumentType.openDocument`. AppKit сам умеет читать
//  и писать этот формат с macOS 10.14+, поэтому реализация симметрична RtfIO
//  и живёт в том же модуле (шарит внутренние helpers).
//
//  Ограничения (унаследованы от NSAttributedString bridge):
//   - таблицы восстанавливаются как параграфы с табами (как в RtfIO);
//   - track-changes и комментарии не поддерживаются форматом на уровне
//     NSAttributedString — теряются при round-trip;
//   - изображения проходят через NSTextAttachment (визуально работают,
//     но `Run.image.altText` теряется).
//
//  Полный native-writer OOXML-style (со всеми возможностями DocumentModel) —
//  задача R09/R10 при появлении реального спроса на редактирование ODT.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import DocxCore

public enum OdtIO {

    // MARK: - Импорт

    public static func importODT(data: Data) throws -> DocumentModel {
        let attributed: NSAttributedString
        var info: NSDictionary?
        do {
            attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.openDocument],
                documentAttributes: &info
            )
        } catch {
            throw DocumentError.invalidDocument(
                "Не удалось разобрать ODT: \(error.localizedDescription)"
            )
        }
        let swiftInfo: [NSAttributedString.DocumentAttributeKey: Any] =
            (info as? [NSAttributedString.DocumentAttributeKey: Any]) ?? [:]
        return odtBuildModel(from: attributed, documentAttributes: swiftInfo)
    }

    public static func importODT(url: URL) throws -> DocumentModel {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentError.ioError(
                "Не удалось прочитать файл \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        return try importODT(data: data)
    }

    // MARK: - Экспорт

    public static func exportODT(_ document: DocumentModel) throws -> Data {
        let attributed = odtBuildAttributedString(from: document)
        let page = document.pageSettings
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.openDocument,
            .paperSize: page.pageSizeInPoints,
            .topMargin: page.margins.top,
            .bottomMargin: page.margins.bottom,
            .leftMargin: page.margins.left,
            .rightMargin: page.margins.right,
        ]
        do {
            return try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: attrs
            )
        } catch {
            throw DocumentError.encodingError(
                "Не удалось сериализовать ODT: \(error.localizedDescription)"
            )
        }
    }

    public static func exportODT(_ document: DocumentModel, to url: URL) throws {
        let data = try exportODT(document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Internal helpers

// Мы намеренно дублируем buildModel/buildAttributedString с RtfIO, а не шарим
// напрямую: у RtfIO это file-private символы, и делать их internal ради одного
// потребителя — хуже, чем короткая копия. Если появится третий формат через
// NSAttributedString, вынесем в отдельный `NsAttrDocumentBridge`.

private func odtBuildModel(
    from attributed: NSAttributedString,
    documentAttributes: [NSAttributedString.DocumentAttributeKey: Any]
) -> DocumentModel {
    let pageSettings = odtPageSettings(documentAttributes)
    let metadata = odtMetadata(documentAttributes)
    let blocks = odtSplitParagraphs(attributed)
    return DocumentModel(
        metadata: metadata,
        pageSettings: pageSettings,
        sections: [DocumentSection(blocks: blocks)]
    )
}

private func odtPageSettings(
    _ attrs: [NSAttributedString.DocumentAttributeKey: Any]
) -> PageSettings {
    let paper = (attrs[.paperSize] as? NSValue)?.sizeValue
    let top = (attrs[.topMargin] as? NSNumber)?.doubleValue ?? Double(PageMargins.standard.top)
    let bottom = (attrs[.bottomMargin] as? NSNumber)?.doubleValue ?? Double(PageMargins.standard.bottom)
    let left = (attrs[.leftMargin] as? NSNumber)?.doubleValue ?? Double(PageMargins.standard.left)
    let right = (attrs[.rightMargin] as? NSNumber)?.doubleValue ?? Double(PageMargins.standard.right)
    let orientation: PageOrientation = {
        guard let s = paper else { return .portrait }
        return s.width > s.height ? .landscape : .portrait
    }()
    return PageSettings(
        paperSize: odtInferPaperSize(paper),
        orientation: orientation,
        margins: PageMargins(
            top: CGFloat(top), bottom: CGFloat(bottom),
            left: CGFloat(left), right: CGFloat(right)
        )
    )
}

private func odtInferPaperSize(_ size: CGSize?) -> PaperSize {
    guard let size = size else { return .a4 }
    for kind in PaperSize.allCases {
        let ref = kind.sizeInPoints
        if abs(ref.width - size.width) < 2 && abs(ref.height - size.height) < 2 { return kind }
        if abs(ref.height - size.width) < 2 && abs(ref.width - size.height) < 2 { return kind }
    }
    return .custom
}

private func odtMetadata(
    _ attrs: [NSAttributedString.DocumentAttributeKey: Any]
) -> DocumentMetadata {
    var md = DocumentMetadata()
    if let v = attrs[.title] as? String { md.title = v }
    if let v = attrs[.author] as? String { md.author = v }
    if let v = attrs[.subject] as? String { md.subject = v }
    if let v = attrs[.keywords] as? [String] { md.keywords = v }
    return md
}

private func odtSplitParagraphs(_ attributed: NSAttributedString) -> [Block] {
    let full = attributed.string as NSString
    let length = full.length
    var blocks: [Block] = []
    var cursor = 0
    while cursor <= length {
        let searchRange = NSRange(location: cursor, length: length - cursor)
        let newlineRange = full.range(of: "\n", options: [], range: searchRange)
        let end = (newlineRange.location == NSNotFound) ? length : newlineRange.location
        let paraRange = NSRange(location: cursor, length: end - cursor)
        if paraRange.length > 0 {
            blocks.append(.paragraph(odtMakeParagraph(in: attributed, range: paraRange)))
        } else {
            blocks.append(.paragraph(Paragraph.empty))
        }
        if newlineRange.location == NSNotFound { break }
        cursor = newlineRange.location + newlineRange.length
    }
    if blocks.isEmpty { blocks.append(.paragraph(Paragraph.empty)) }
    return blocks
}

private func odtMakeParagraph(
    in attributed: NSAttributedString,
    range: NSRange
) -> Paragraph {
    var runs: [Run] = []
    var position = range.location
    let end = range.location + range.length
    while position < end {
        var effective = NSRange(location: position, length: 0)
        let attrs = attributed.attributes(at: position, effectiveRange: &effective)
        let clampedEnd = min(effective.location + effective.length, end)
        let runLength = clampedEnd - position
        if runLength <= 0 { break }
        let text = (attributed.string as NSString).substring(
            with: NSRange(location: position, length: runLength)
        )
        runs.append(Run(text: text, attributes: odtCharAttrs(attrs)))
        position = clampedEnd
    }
    return Paragraph(runs: runs, attributes: odtParaAttrs(at: range.location, in: attributed))
}

private func odtCharAttrs(_ attrs: [NSAttributedString.Key: Any]) -> CharacterAttributes {
    var result = CharacterAttributes()
    #if canImport(AppKit)
    if let font = attrs[.font] as? NSFont {
        result.fontName = font.fontName
        result.fontSize = font.pointSize
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) { result.bold = true }
        if traits.contains(.italic) { result.italic = true }
    }
    if let color = attrs[.foregroundColor] as? NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        result.textColor = CodableColor(
            red: CGFloat(rgb.redComponent), green: CGFloat(rgb.greenComponent),
            blue: CGFloat(rgb.blueComponent), alpha: CGFloat(rgb.alphaComponent)
        )
    }
    if let raw = attrs[.underlineStyle] as? Int, raw != 0 { result.underline = .single }
    if let raw = attrs[.strikethroughStyle] as? Int, raw != 0 { result.strikethrough = true }
    #endif
    return result
}

private func odtParaAttrs(
    at index: Int, in attributed: NSAttributedString
) -> ParagraphAttributes {
    var pa = ParagraphAttributes()
    #if canImport(AppKit)
    let attrs = attributed.attributes(at: index, effectiveRange: nil)
    if let style = attrs[.paragraphStyle] as? NSParagraphStyle {
        switch style.alignment {
        case .center: pa.alignment = .center
        case .right: pa.alignment = .right
        case .justified: pa.alignment = .justify
        default: pa.alignment = .left
        }
        if style.lineHeightMultiple > 0 {
            pa.lineSpacing = .multiple(style.lineHeightMultiple)
        }
        pa.spaceBefore = style.paragraphSpacingBefore
        pa.spaceAfter = style.paragraphSpacing
        pa.leftIndent = style.headIndent
        pa.rightIndent = -style.tailIndent
        pa.firstLineIndent = style.firstLineHeadIndent
    }
    #endif
    return pa
}

// MARK: - Экспорт: DocumentModel → NSAttributedString

private func odtBuildAttributedString(from document: DocumentModel) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for section in document.sections {
        for (idx, block) in section.blocks.enumerated() {
            switch block {
            case .paragraph(let p): result.append(odtMakeAttributed(from: p, in: document))
            case .table(let t):     result.append(odtMakeAttributed(from: t))
            }
            if idx < section.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
    }
    return result
}

private func odtMakeAttributed(
    from paragraph: Paragraph, in document: DocumentModel
) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let defaultFontName = document.styles.defaultFontName
    let defaultFontSize = document.styles.defaultFontSize
    for run in paragraph.runs {
        #if canImport(AppKit)
        result.append(NSAttributedString(
            string: run.text,
            attributes: odtPlatformAttrs(from: run.attributes,
                                          defaultFontName: defaultFontName,
                                          defaultFontSize: defaultFontSize)
        ))
        #else
        result.append(NSAttributedString(string: run.text))
        #endif
    }
    #if canImport(AppKit)
    if result.length > 0 {
        result.addAttribute(
            .paragraphStyle,
            value: odtPlatformPara(from: paragraph.attributes),
            range: NSRange(location: 0, length: result.length)
        )
    }
    #endif
    return result
}

private func odtMakeAttributed(from table: TableBlock) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (rowIdx, row) in table.rows.enumerated() {
        for (cellIdx, cell) in row.cells.enumerated() {
            if cellIdx > 0 { result.append(NSAttributedString(string: "\t")) }
            for case let .paragraph(p) in cell.blocks {
                result.append(odtMakeAttributed(from: p, in: DocumentModel()))
            }
        }
        if rowIdx < table.rows.count - 1 {
            result.append(NSAttributedString(string: "\n"))
        }
    }
    return result
}

#if canImport(AppKit)
private func odtPlatformAttrs(
    from attrs: CharacterAttributes,
    defaultFontName: String, defaultFontSize: CGFloat
) -> [NSAttributedString.Key: Any] {
    let name = attrs.fontName ?? defaultFontName
    let size = attrs.fontSize ?? defaultFontSize
    var font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    var traits: NSFontDescriptor.SymbolicTraits = []
    if attrs.bold { traits.insert(.bold) }
    if attrs.italic { traits.insert(.italic) }
    if !traits.isEmpty {
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        if let styled = NSFont(descriptor: descriptor, size: size) { font = styled }
    }
    var result: [NSAttributedString.Key: Any] = [.font: font]
    if let color = attrs.textColor {
        result[.foregroundColor] = NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha
        )
    }
    if attrs.underline != .none {
        result[.underlineStyle] = NSUnderlineStyle.single.rawValue
    }
    if attrs.strikethrough {
        result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    return result
}

private func odtPlatformPara(from attrs: ParagraphAttributes) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    switch attrs.alignment {
    case .left: style.alignment = .left
    case .center: style.alignment = .center
    case .right: style.alignment = .right
    case .justify: style.alignment = .justified
    }
    switch attrs.lineSpacing {
    case .single: style.lineHeightMultiple = 1.0
    case .onePoint15: style.lineHeightMultiple = 1.15
    case .onePoint5: style.lineHeightMultiple = 1.5
    case .double: style.lineHeightMultiple = 2.0
    case .multiple(let v): style.lineHeightMultiple = v
    case .exact(let v): style.lineHeightMultiple = 1.0; style.lineSpacing = v
    case .atLeast(let v): style.lineHeightMultiple = 1.0; style.lineSpacing = v
    }
    style.paragraphSpacingBefore = attrs.spaceBefore
    style.paragraphSpacing = attrs.spaceAfter
    style.headIndent = attrs.leftIndent
    style.tailIndent = -attrs.rightIndent
    style.firstLineHeadIndent = attrs.firstLineIndent
    return style
}
#endif
