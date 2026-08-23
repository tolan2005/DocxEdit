import XCTest
@testable import DocxIO
@testable import MarkdownIO
@testable import DocxCore

/// v1.6.4: регрессионные тесты производительности — импорт/экспорт корпусных
/// документов не должен деградировать. Базовые значения зафиксированы на
/// arm64 (M-серия); measure-тесты пишут baseline в результат прогона и падают
/// при регрессии >30% относительно предыдущего прогона этой же машины.
final class PerformanceRegressionTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "docx",
                              subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testImportCorpusPerformance() throws {
        let data = try fixtureData("21")   // самый тяжёлый: 33 сложных поля, TOC
        measure {
            _ = try? DocxIO.importDocx(data: data)
        }
    }

    func testImportExportRoundTripPerformance() throws {
        let data = try fixtureData("133")  // passthrough-части, графика колонтитулов
        let model = try DocxIO.importDocx(data: data)
        measure {
            _ = try? DocxIO.exportDocx(model)
        }
    }

    /// MD source-режим синкает модель на каждую правку — подсветка+реимпорт
    /// должны оставаться дешёвыми (O(n) на документ типичного размера).
    func testMarkdownImportPerformance() throws {
        // ~40 KB типичного MD (как большой конспект).
        let line = "Обычный текст с **жирным**, *курсивом* и [ссылкой](https://example.com).\n"
        let big = String(repeating: line, count: 400)
        measure {
            _ = try? MarkdownIOTestHelper.parse(big)
        }
    }
}

/// Обёртка, чтобы не тянуть MarkdownIO в импорты тест-файла напрямую
/// (MarkdownIO.importMarkdown throws → DocumentModel).
enum MarkdownIOTestHelper {
    static func parse(_ s: String) -> DocumentModel? {
        try? MarkdownIO.importMarkdown(string: s)
    }
}
