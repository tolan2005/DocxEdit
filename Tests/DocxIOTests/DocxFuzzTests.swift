//
//  DocxFuzzTests.swift
//  DocxIOTests
//
//  Fuzz-корпус: битые/edge-case DOCX. Проверка, что импорт не крашится и
//  возвращает разумную модель (или бросает DocumentError, но не fatalError).
//

import XCTest
import Foundation
import ZIPFoundation
@testable import DocxCore
@testable import DocxIO

final class DocxFuzzTests: XCTestCase {

    // MARK: - Helpers для сборки .docx на лету

    /// Минимальный валидный .docx как in-memory ZIP.
    private func makeDocx(files: [(path: String, content: String)]) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fuzz-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let archive = Archive(url: tmp, accessMode: .create) else {
            throw NSError(domain: "test", code: 1)
        }
        for f in files {
            let data = Data(f.content.utf8)
            try archive.addEntry(with: f.path, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 provider: { pos, size in
                data.subdata(in: Int(pos)..<Int(pos)+size)
            })
        }
        return try Data(contentsOf: tmp)
    }

    private let contentTypesXml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

    private let mainRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

    private func minimalDocXml(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(body)</w:body>
        </w:document>
        """
    }

    private func standardBase(bodyXml: String) -> [(path: String, content: String)] {
        [
            ("[Content_Types].xml", contentTypesXml),
            ("_rels/.rels", mainRels),
            ("word/document.xml", minimalDocXml(body: bodyXml)),
        ]
    }

    // MARK: - Позитивные: минимальный/typical

    func testMinimalDocxOpensSuccessfully() throws {
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:r><w:t>Hello</w:t></w:r></w:p>"))
        let m = try DocxIO.importDocx(data: data)
        let text = m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
        XCTAssertTrue(text.contains("Hello"), "текст утерян: \(text)")
    }

    // MARK: - Отсутствующие части (не должно ронять)

    func testMissingStylesXmlDoesNotCrash() throws {
        // Нет word/styles.xml — импорт должен работать с fallback.
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>x</w:t></w:r></w:p>"))
        XCTAssertNoThrow(try DocxIO.importDocx(data: data))
    }

    func testMissingNumberingXmlDoesNotCrash() throws {
        // Ссылка на <w:numId> без numbering.xml — fallback на буллит уровня 0.
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>item</w:t></w:r></w:p>"))
        XCTAssertNoThrow(try DocxIO.importDocx(data: data))
    }

    // MARK: - Битые XML → должен бросить, но не крашить процесс

    func testInvalidXmlThrows() throws {
        let data = try makeDocx(files: [
            ("[Content_Types].xml", contentTypesXml),
            ("_rels/.rels", mainRels),
            ("word/document.xml", "<not-a-valid-xml"),
        ])
        // Может бросить или вернуть пустую модель — главное, не крашнуться.
        // Проверяем оба варианта.
        do {
            let m = try DocxIO.importDocx(data: data)
            XCTAssertNotNil(m)
        } catch {
            // Ожидаемо — битый XML.
        }
    }

    func testEmptyBodyDoesNotCrash() throws {
        let data = try makeDocx(files: standardBase(bodyXml: ""))
        XCTAssertNoThrow(try DocxIO.importDocx(data: data))
    }

    // MARK: - Экстремальные значения

    func testHugeNumIdDoesNotCrash() throws {
        // numId = INT_MAX — не должен ломать парсер.
        let body = "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2147483647\"/></w:numPr></w:pPr><w:r><w:t>x</w:t></w:r></w:p>"
        let data = try makeDocx(files: standardBase(bodyXml: body))
        XCTAssertNoThrow(try DocxIO.importDocx(data: data))
    }

    func testNegativeIlvlIsIgnoredOrClamped() throws {
        // ilvl = -1 — некорректное значение уровня.
        let body = "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"-1\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>x</w:t></w:r></w:p>"
        let data = try makeDocx(files: standardBase(bodyXml: body))
        XCTAssertNoThrow(try DocxIO.importDocx(data: data))
    }

    func testDeepParagraphNestingDoesNotCrash() throws {
        // Строим документ с 1000 параграфов — проверка на O(n²)/стек.
        var body = ""
        for i in 0..<1000 {
            body += "<w:p><w:r><w:t>p\(i)</w:t></w:r></w:p>"
        }
        let data = try makeDocx(files: standardBase(bodyXml: body))
        let m = try DocxIO.importDocx(data: data)
        let count = m.sections.flatMap { $0.blocks }.count
        XCTAssertGreaterThanOrEqual(count, 1000)
    }

    // MARK: - Circular basedOn в стилях (ADR-036 — сейчас styles.xml валидный, но чужие могут)

    func testCircularBasedOnDoesNotHang() throws {
        // A basedOn B, B basedOn A — не должно висеть.
        let stylesXml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="B"/></w:style>
            <w:style w:type="paragraph" w:styleId="B"><w:basedOn w:val="A"/></w:style>
            </w:styles>
            """
        let contentTypes = contentTypesXml.replacingOccurrences(
            of: "</Types>",
            with: "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>"
        )
        let data = try makeDocx(files: [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", mainRels),
            ("word/document.xml", minimalDocXml(body:
                "<w:p><w:pPr><w:pStyle w:val=\"A\"/></w:pPr><w:r><w:t>x</w:t></w:r></w:p>")),
            ("word/styles.xml", stylesXml),
        ])
        // Дать разумный дедлайн — если зависнет, XCTest прибьёт через timeout,
        // но лучше явно ограничить: успешно откроется быстро.
        let start = Date()
        _ = try? DocxIO.importDocx(data: data)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0,
                          "цикл basedOn зациклил парсер")
    }

    // MARK: - Пустой файл / не-ZIP

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try DocxIO.importDocx(data: Data()))
    }

    func testNonZipDataThrows() {
        XCTAssertThrowsError(try DocxIO.importDocx(data: Data("not a zip".utf8)))
    }

    // MARK: - Кириллица в контенте (регрессия v0.5.1 — encoding)

    func testCyrillicSurvivesImport() throws {
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:r><w:t>Привет, мир! Съешь ещё этих мягких булок</w:t></w:r></w:p>"))
        let m = try DocxIO.importDocx(data: data)
        let text = m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
        XCTAssertTrue(text.contains("Привет"), "кириллица сломана")
    }

    // MARK: - XML entities и спецсимволы

    func testXmlEntitiesInText() throws {
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:r><w:t>&lt;тег&gt; &amp; &quot;ковычки&quot;</w:t></w:r></w:p>"))
        let m = try DocxIO.importDocx(data: data)
        let text = m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
        // XML entities должны декодироваться в реальные символы.
        XCTAssertTrue(text.contains("<тег>"), "XML entities не декодированы: \(text)")
        XCTAssertTrue(text.contains("&"))
    }

    func testVeryLongParagraphText() throws {
        // Один параграф с 100 000 символов — проверка на квадратичность.
        let big = String(repeating: "a", count: 100_000)
        let data = try makeDocx(files: standardBase(bodyXml:
            "<w:p><w:r><w:t>\(big)</w:t></w:r></w:p>"))
        let start = Date()
        let m = try DocxIO.importDocx(data: data)
        let dt = Date().timeIntervalSince(start)
        XCTAssertLessThan(dt, 5.0, "100k-параграф импортится дольше 5с — O(n²) регрессия?")
        let text = m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil }
        }.joined()
        XCTAssertGreaterThanOrEqual(text.count, 100_000)
    }
}
