//
//  PdfExporter.swift
//  PdfExporter
//
//  Минимальная реализация экспорта DocumentModel в PDF для DocxEdit R01 (MVP).
//  Использует CoreText для рендеринга attributed string в PDF-страницы.
//

import Foundation
import AppKit
import CoreText
import CoreGraphics
import PDFKit
import DocxCore

public enum PdfExporter {

    public static func exportToPDF(_ document: DocumentModel) throws -> Data {
        let attributed = buildAttributedString(from: document)
        let page = document.pageSettings
        let pageSize = page.pageSizeInPoints
        let margins = page.margins

        // Media box в пунктах (1 pt = 1/72 inch).
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else {
            throw DocumentError.ioError("Не удалось создать PDF consumer")
        }
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentError.ioError("Не удалось создать PDF-контекст")
        }

        // Рабочая область страницы.
        // В CoreText координаты Y идут сверху, в CoreGraphics — снизу.
        let textBounds = CGRect(
            x: margins.left,
            y: margins.top,
            width: pageSize.width - margins.left - margins.right,
            height: pageSize.height - margins.top - margins.bottom
        )
        let path = CGPath(rect: textBounds, transform: nil)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentRange = CFRange(location: 0, length: 0)
        let total = attributed.length

        while currentRange.location < total {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, ctx)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length <= 0 {
                ctx.endPDFPage()
                break
            }
            currentRange.location += visibleRange.length
            ctx.endPDFPage()
        }

        ctx.closePDF()
        return pdfData as Data
    }

    public static func exportToPDF(_ document: DocumentModel, to url: URL) throws {
        let data = try exportToPDF(document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DocumentError.ioError(
                "Не удалось записать файл: \(error.localizedDescription)"
            )
        }
    }

    public static func makePrintOperation(for document: DocumentModel) -> NSPrintOperation {
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = document.pageSettings.pageSizeInPoints
        printInfo.topMargin = document.pageSettings.margins.top
        printInfo.bottomMargin = document.pageSettings.margins.bottom
        printInfo.leftMargin = document.pageSettings.margins.left
        printInfo.rightMargin = document.pageSettings.margins.right
        printInfo.orientation = document.pageSettings.orientation == .landscape
            ? .landscape
            : .portrait
        let view = DocumentPrintView(document: document)
        view.frame = NSRect(origin: .zero, size: document.pageSettings.pageSizeInPoints)
        return NSPrintOperation(view: view, printInfo: printInfo)
    }

    // MARK: - Сборка AttributedString

    private static func buildAttributedString(from document: DocumentModel) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let defaultFontName = document.styles.defaultFontName
        let defaultFontSize = document.styles.defaultFontSize

        for section in document.sections {
            for (idx, block) in section.blocks.enumerated() {
                switch block {
                case .paragraph(let p):
                    for run in p.runs {
                        let font = NSFont(
                            name: run.attributes.fontName ?? defaultFontName,
                            size: run.attributes.fontSize ?? defaultFontSize
                        ) ?? NSFont.systemFont(ofSize: run.attributes.fontSize ?? defaultFontSize)
                        let style = NSMutableParagraphStyle()
                        style.alignment = {
                            switch p.attributes.alignment {
                            case .left: return .left
                            case .center: return .center
                            case .right: return .right
                            case .justify: return .justified
                            }
                        }()
                        style.lineHeightMultiple = p.attributes.lineSpacing.multiplier
                        style.paragraphSpacingBefore = p.attributes.spaceBefore
                        style.paragraphSpacing = p.attributes.spaceAfter
                        style.headIndent = p.attributes.leftIndent
                        style.tailIndent = -p.attributes.rightIndent
                        style.firstLineHeadIndent = p.attributes.firstLineIndent
                        var attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .paragraphStyle: style,
                        ]
                        if let c = run.attributes.textColor {
                            attrs[.foregroundColor] = NSColor(
                                calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha
                            )
                        }
                        if run.attributes.underline != .none {
                            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        }
                        if run.attributes.strikethrough {
                            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        }
                        result.append(NSAttributedString(string: run.text, attributes: attrs))
                    }
                    if p.runs.isEmpty {
                        result.append(NSAttributedString(
                            string: " ",
                            attributes: [.font: NSFont(name: defaultFontName, size: defaultFontSize)
                                ?? NSFont.systemFont(ofSize: defaultFontSize)]
                        ))
                    }
                case .table(let t):
                    for row in t.rows {
                        for (c, cell) in row.cells.enumerated() {
                            if c > 0 { result.append(NSAttributedString(string: "\t")) }
                            for case let .paragraph(p) in cell.blocks {
                                for run in p.runs {
                                    result.append(NSAttributedString(
                                        string: run.text,
                                        attributes: [.font: NSFont.systemFont(ofSize: defaultFontSize)]
                                    ))
                                }
                            }
                        }
                        result.append(NSAttributedString(string: "\n"))
                    }
                }
                if idx < section.blocks.count - 1 {
                    result.append(NSAttributedString(string: "\n"))
                }
            }
        }
        return result
    }
}

/// Простой NSView для печати документа.
final class DocumentPrintView: NSView {
    let document: DocumentModel

    init(document: DocumentModel) {
        self.document = document
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let text = NSAttributedString(string: document.plainText)
        text.draw(in: bounds)
    }
}
