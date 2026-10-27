import XCTest
import PDFKit
@testable import DocxEdit

/// v1.10.6: экспорт Markdown в PDF в гибридном виде.
@MainActor
final class HybridPDFTests: XCTestCase {
    func testPDFHasRenderedTextWithoutMarkup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hybrid-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var md = "## Заголовок отчёта\n\nОбычный **жирный** текст.\n\n- пункт один\n- пункт два\n\n| Имя | Цена |\n|---|--:|\n| Яблоко | 5 |\n"
        for i in 1...80 { md += "\nСтрока \(i)" }   // на несколько страниц
        try MarkdownSourceView.exportHybridPDF(md, baseURL: nil, to: url)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("Заголовок отчёта"))
        XCTAssertTrue(text.contains("жирный"))
        XCTAssertFalse(text.contains("##"))
        XCTAssertFalse(text.contains("**"))
        if let keep = ProcessInfo.processInfo.environment["HYBRID_PDF_OUT"] {
            try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: keep))
        }
    }
}
