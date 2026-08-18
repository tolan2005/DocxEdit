//
//  RealDocxCorpusTests.swift
//  DocxIOTests
//
//  Тесты на реальных .docx-файлах (пользовательский корпус: 21-24.docx).
//  Цель: убедиться, что импорт не падает, выдаёт непустую модель, и что
//  export→reimport (двойной round-trip) стабилен по видимому тексту и
//  количеству параграфов.
//

import XCTest
import Foundation
@testable import DocxCore
@testable import DocxIO

final class RealDocxCorpusTests: XCTestCase {

    /// Все fixture-файлы корпуса. Bundle.module даёт доступ к ресурсам testTarget.
    private var fixtures: [(name: String, data: Data)] {
        let names = ["21", "22", "23", "24"]
        return names.compactMap { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "docx",
                                               subdirectory: "Fixtures"),
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return (name, data)
        }
    }

    // MARK: - Импорт не падает и не пустой

    func testAllFixturesImportWithoutError() throws {
        XCTAssertEqual(fixtures.count, 4, "fixtures не подтянулись — проверь Package.swift resources")
        for (name, data) in fixtures {
            do {
                let m = try DocxIO.importDocx(data: data)
                let blocks = m.sections.flatMap { $0.blocks }.count
                XCTAssertGreaterThan(blocks, 0, "\(name).docx: 0 блоков — импорт вернул пустой документ")
            } catch {
                XCTFail("\(name).docx: import упал с \(error)")
            }
        }
    }

    // MARK: - Не пустой текст

    func testAllFixturesHaveVisibleText() throws {
        for (name, data) in fixtures {
            let m = try DocxIO.importDocx(data: data)
            let text = allText(m)
            XCTAssertGreaterThan(text.count, 0,
                                 "\(name).docx: нулевой текст — парсер потерял всё содержимое")
        }
    }

    // MARK: - Двойной round-trip: import → export → import → тот же текст

    func testDoubleRoundTripStableText() throws {
        for (name, data) in fixtures {
            let m1 = try DocxIO.importDocx(data: data)
            let data2 = try DocxIO.exportDocx(m1)
            let m2 = try DocxIO.importDocx(data: data2)

            let t1 = normalizedText(m1)
            let t2 = normalizedText(m2)
            XCTAssertEqual(t1, t2,
                           "\(name).docx: после export→reimport текст изменился\n" +
                           "  len(t1)=\(t1.count) len(t2)=\(t2.count)")
        }
    }

    // MARK: - Двойной round-trip: количество блоков стабильно

    func testDoubleRoundTripStableBlockCount() throws {
        for (name, data) in fixtures {
            let m1 = try DocxIO.importDocx(data: data)
            let data2 = try DocxIO.exportDocx(m1)
            let m2 = try DocxIO.importDocx(data: data2)

            let c1 = m1.sections.flatMap { $0.blocks }.count
            let c2 = m2.sections.flatMap { $0.blocks }.count
            XCTAssertEqual(c1, c2,
                           "\(name).docx: число блоков изменилось \(c1)→\(c2)")
        }
    }

    // MARK: - ImportReport не пустой (диагностика непокрытых элементов)

    /// Диагностический тест — не фейлит, но печатает отчёт об импорте.
    /// Полезно для развития парсера: показывает, какие OOXML-элементы пока
    /// пропускаются в реальных файлах пользователя.
    func testImportReportsForCorpus() throws {
        for (name, data) in fixtures {
            let (_, report) = try DocxIO.importDocxWithReport(data: data)
            if !report.isEmpty {
                print("=== \(name).docx import report ===")
                for entry in report.entries.prefix(10) {
                    print("  [\(entry.category)] \(entry.element) × \(entry.count): \(entry.explanation)")
                }
                if report.entries.count > 10 {
                    print("  ... + \(report.entries.count - 10) more entries")
                }
            }
        }
    }

    // MARK: - Экспорт не роняет

    func testAllFixturesRoundTripDoesNotThrow() throws {
        for (name, data) in fixtures {
            let m = try DocxIO.importDocx(data: data)
            XCTAssertNoThrow(try DocxIO.exportDocx(m), "\(name).docx: export упал")
        }
    }

    // MARK: - Performance sanity: каждый файл должен парситься быстро

    func testImportPerformance() throws {
        for (name, data) in fixtures {
            let start = Date()
            _ = try DocxIO.importDocx(data: data)
            let dt = Date().timeIntervalSince(start)
            // 2 секунды — щедрый бюджет для документа ~200 КБ.
            XCTAssertLessThan(dt, 2.0,
                              "\(name).docx: импорт \(String(format: "%.2f", dt))с — потенциальная O(n²) регрессия")
        }
    }

    // MARK: - Helpers

    private func allText(_ m: DocumentModel) -> String {
        var parts: [String] = []
        for section in m.sections {
            for block in section.blocks {
                switch block {
                case .paragraph(let p):
                    parts.append(p.runs.map(\.text).joined())
                case .table(let t):
                    for row in t.rows {
                        for cell in row.cells {
                            for b in cell.blocks {
                                if case let .paragraph(p) = b {
                                    parts.append(p.runs.map(\.text).joined())
                                }
                            }
                        }
                    }
                }
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Нормализованный текст для сравнения: убираем множественные пробелы и
    /// пустые строки, которые могут по-разному сериализоваться, не меняя смысл.
    private func normalizedText(_ m: DocumentModel) -> String {
        let raw = allText(m)
        return raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
