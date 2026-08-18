//
//  RtfIO.swift
//  RtfIO
//
//  Минимальная реализация импорта/экспорта RTF для DocxEdit R01 (MVP).
//  Использует NSAttributedString (AppKit) как промежуточное представление.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import DocxCore

public enum RtfIO {

    // MARK: - Импорт

    public static func importRTF(data: Data) throws -> DocumentModel {
        let attributed: NSAttributedString
        var info: NSDictionary?
        do {
            attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: &info
            )
        } catch {
            throw DocumentError.invalidDocument(
                "Не удалось разобрать RTF: \(error.localizedDescription)"
            )
        }
        let swiftInfo: [NSAttributedString.DocumentAttributeKey: Any] = (info as? [NSAttributedString.DocumentAttributeKey: Any]) ?? [:]
        return buildModel(from: attributed, documentAttributes: swiftInfo)
    }

    public static func importRTF(url: URL) throws -> DocumentModel {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentError.ioError(
                "Не удалось прочитать файл \(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
        return try importRTF(data: data)
    }

    // MARK: - Экспорт

    public static func exportRTF(_ document: DocumentModel) throws -> Data {
        let attributed = buildAttributedString(from: document)
        let page = document.pageSettings
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf,
            .paperSize: page.pageSizeInPoints,
            .topMargin: page.margins.top,
            .bottomMargin: page.margins.bottom,
            .leftMargin: page.margins.left,
            .rightMargin: page.margins.right,
        ]
        do {
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: attrs
            )
            return data
        } catch {
            throw DocumentError.encodingError(
                "Не удалось сериализовать RTF: \(error.localizedDescription)"
            )
        }
    }

    public static func exportRTF(_ document: DocumentModel, to url: URL) throws {
        let data = try exportRTF(document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Импорт: NSAttributedString → DocumentModel

private func buildModel(
    from attributed: NSAttributedString,
    documentAttributes: [NSAttributedString.DocumentAttributeKey: Any]
) -> DocumentModel {
    let pageSettings = pageSettingsFromAttrs(documentAttributes)
    let metadata = metadataFromAttrs(documentAttributes)
    let blocks = splitParagraphs(attributed)
    return DocumentModel(
        metadata: metadata,
        pageSettings: pageSettings,
        sections: [DocumentSection(blocks: blocks)]
    )
}

private func pageSettingsFromAttrs(
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
        paperSize: inferPaperSize(paper),
        orientation: orientation,
        margins: PageMargins(
            top: CGFloat(top),
            bottom: CGFloat(bottom),
            left: CGFloat(left),
            right: CGFloat(right)
        )
    )
}

private func inferPaperSize(_ size: CGSize?) -> PaperSize {
    guard let size = size else { return .a4 }
    for kind in PaperSize.allCases {
        let ref = kind.sizeInPoints
        if abs(ref.width - size.width) < 2 && abs(ref.height - size.height) < 2 { return kind }
        if abs(ref.height - size.width) < 2 && abs(ref.width - size.height) < 2 { return kind }
    }
    return .custom
}

private func metadataFromAttrs(
    _ attrs: [NSAttributedString.DocumentAttributeKey: Any]
) -> DocumentMetadata {
    var md = DocumentMetadata()
    if let v = attrs[.title] as? String { md.title = v }
    if let v = attrs[.author] as? String { md.author = v }
    if let v = attrs[.subject] as? String { md.subject = v }
    if let v = attrs[.keywords] as? [String] { md.keywords = v }
    if let v = attrs[NSAttributedString.DocumentAttributeKey(rawValue: "CocoaRTFDocumentCreated")] as? Date {
        md.createdAt = v
    }
    if let v = attrs[NSAttributedString.DocumentAttributeKey(rawValue: "CocoaRTFDocumentLastSaved")] as? Date {
        md.modifiedAt = v
    }
    return md
}

private func splitParagraphs(_ attributed: NSAttributedString) -> [Block] {
    let full = attributed.string as NSString
    let length = full.length
    var blocks: [Block] = []
    var cursor = 0

    while cursor <= length {
        let searchRange = NSRange(location: cursor, length: length - cursor)
        let newlineRange = full.range(of: "\n", options: [], range: searchRange)
        let end = (newlineRange.location == NSNotFound) ? length : newlineRange.location
        let paragraphRange = NSRange(location: cursor, length: end - cursor)
        if paragraphRange.length > 0 {
            blocks.append(.paragraph(makeParagraph(in: attributed, range: paragraphRange)))
        } else {
            blocks.append(.paragraph(Paragraph.empty))
        }
        if newlineRange.location == NSNotFound { break }
        cursor = newlineRange.location + newlineRange.length
    }

    if blocks.isEmpty {
        blocks.append(.paragraph(Paragraph.empty))
    }
    return blocks
}

private func makeParagraph(
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
        runs.append(Run(text: text, attributes: charAttrsFromPlatformAttrs(attrs)))
        position = clampedEnd
    }

    return Paragraph(runs: runs, attributes: paragraphAttrsFromPlatform(at: range.location, in: attributed))
}

private func charAttrsFromPlatformAttrs(_ attrs: [NSAttributedString.Key: Any]) -> CharacterAttributes {
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
            red: CGFloat(rgb.redComponent),
            green: CGFloat(rgb.greenComponent),
            blue: CGFloat(rgb.blueComponent),
            alpha: CGFloat(rgb.alphaComponent)
        )
    }
    if let bg = attrs[.backgroundColor] as? NSColor {
        let rgb = bg.usingColorSpace(.sRGB) ?? bg
        result.highlightColor = CodableColor(
            red: CGFloat(rgb.redComponent),
            green: CGFloat(rgb.greenComponent),
            blue: CGFloat(rgb.blueComponent),
            alpha: CGFloat(rgb.alphaComponent)
        )
    }
    if let raw = attrs[.underlineStyle] as? Int, raw != 0 {
        result.underline = .single
    }
    if let raw = attrs[.strikethroughStyle] as? Int, raw != 0 {
        result.strikethrough = true
    }
    #endif
    return result
}

private func paragraphAttrsFromPlatform(
    at index: Int,
    in attributed: NSAttributedString
) -> ParagraphAttributes {
    var pa = ParagraphAttributes()
    let attrs = attributed.attributes(at: index, effectiveRange: nil)
    #if canImport(AppKit)
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

private func buildAttributedString(from document: DocumentModel) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for section in document.sections {
        for (idx, block) in section.blocks.enumerated() {
            switch block {
            case .paragraph(let p):
                result.append(makeAttributedString(from: p, in: document))
            case .table(let t):
                result.append(makeAttributedString(from: t))
            }
            if idx < section.blocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
    }
    return result
}

private func makeAttributedString(
    from paragraph: Paragraph,
    in document: DocumentModel
) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let defaultFontName = document.styles.defaultFontName
    let defaultFontSize = document.styles.defaultFontSize

    if paragraph.runs.isEmpty {
        #if canImport(AppKit)
        result.append(NSAttributedString(
            string: " ",
            attributes: [
                .font: NSFont(name: defaultFontName, size: defaultFontSize)
                    ?? NSFont.systemFont(ofSize: defaultFontSize),
                .paragraphStyle: makePlatformParagraphStyle(from: paragraph.attributes),
            ]
        ))
        #endif
        return result
    }

    for run in paragraph.runs {
        #if canImport(AppKit)
        let attrs = platformAttributes(
            from: run.attributes,
            defaultFontName: defaultFontName,
            defaultFontSize: defaultFontSize
        )
        result.append(NSAttributedString(string: run.text, attributes: attrs))
        #else
        result.append(NSAttributedString(string: run.text))
        #endif
    }
    let range = NSRange(location: 0, length: result.length)
    if range.length > 0 {
        #if canImport(AppKit)
        result.addAttribute(
            .paragraphStyle,
            value: makePlatformParagraphStyle(from: paragraph.attributes),
            range: range
        )
        #endif
    }
    return result
}

private func makeAttributedString(from table: TableBlock) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (rowIdx, row) in table.rows.enumerated() {
        for (cellIdx, cell) in row.cells.enumerated() {
            if cellIdx > 0 { result.append(NSAttributedString(string: "\t")) }
            for case let .paragraph(p) in cell.blocks {
                result.append(makeAttributedString(from: p, in: DocumentModel()))
            }
        }
        if rowIdx < table.rows.count - 1 {
            result.append(NSAttributedString(string: "\n"))
        }
    }
    return result
}

#if canImport(AppKit)
private func platformAttributes(
    from attrs: CharacterAttributes,
    defaultFontName: String,
    defaultFontSize: CGFloat
) -> [NSAttributedString.Key: Any] {
    let name = attrs.fontName ?? defaultFontName
    let size = attrs.fontSize ?? defaultFontSize
    var font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    var traits: NSFontDescriptor.SymbolicTraits = []
    if attrs.bold { traits.insert(.bold) }
    if attrs.italic { traits.insert(.italic) }
    if !traits.isEmpty {
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        if let styled = NSFont(descriptor: descriptor, size: size) {
            font = styled
        }
    }
    var result: [NSAttributedString.Key: Any] = [.font: font]
    if let color = attrs.textColor {
        result[.foregroundColor] = NSColor(
            calibratedRed: color.red, green: color.green,
            blue: color.blue, alpha: color.alpha
        )
    }
    if let bg = attrs.highlightColor {
        result[.backgroundColor] = NSColor(
            calibratedRed: bg.red, green: bg.green,
            blue: bg.blue, alpha: bg.alpha
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

private func makePlatformParagraphStyle(from attrs: ParagraphAttributes) -> NSParagraphStyle {
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
    case .exact(let v):
        style.lineHeightMultiple = 1.0
        style.lineSpacing = v
    case .atLeast(let v):
        style.lineHeightMultiple = 1.0
        style.lineSpacing = v
    }
    style.paragraphSpacingBefore = attrs.spaceBefore
    style.paragraphSpacing = attrs.spaceAfter
    style.headIndent = attrs.leftIndent
    style.tailIndent = -attrs.rightIndent
    style.firstLineHeadIndent = attrs.firstLineIndent
    if attrs.listInfo != nil {
        style.textLists = [NSTextList(markerFormat: .disc, options: 0)]
    }
    return style
}
#endif
