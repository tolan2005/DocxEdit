import XCTest
@testable import DocxCore
@testable import DocxIO

/// Символ табуляции `<w:tab/>` в тексте: раньше при открытии пропадал
/// (в оглавлении склеивались заголовок и номер страницы).
final class TabCharacterRoundTripTests: XCTestCase {
    func testTabInTextSurvives() throws {
        var m = DocumentModel()
        m.sections = [DocumentSection(blocks: [.paragraph(Paragraph(runs: [Run(text: "Глава\t5")]))])]
        let r = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        guard case .paragraph(let p) = r.sections[0].blocks[0] else { return XCTFail() }
        XCTAssertEqual(p.runs.map(\.text).joined(), "Глава\t5")
    }

    func testFixtureTocKeepsTabs() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/21.docx")
        let m = try DocxIO.importDocx(url: url)
        let text = m.sections.flatMap(\.blocks).compactMap { b -> String? in
            if case .paragraph(let p) = b { return p.runs.map(\.text).joined() } else { return nil }
        }.joined(separator: "\n")
        XCTAssertTrue(text.contains("ЧТО ТАКОЕ SYNDAG™?\t"), "табуляция после заголовка в оглавлении")
        let xml = String(decoding: try DocxIO.exportDocx(m), as: UTF8.self)
        _ = xml   // zip — проверяем через повторный импорт
        let again = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let text2 = again.sections.flatMap(\.blocks).compactMap { b -> String? in
            if case .paragraph(let p) = b { return p.runs.map(\.text).joined() } else { return nil }
        }.joined(separator: "\n")
        XCTAssertEqual(text2.filter { $0 == "\t" }.count, text.filter { $0 == "\t" }.count)
    }
}

/// Оглавление-поле TOC из Word (fldChar через несколько абзацев) остаётся полем.
final class TocFieldRoundTripTests: XCTestCase {
    func testFixtureTocFieldSurvives() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/21.docx")
        let m = try DocxIO.importDocx(url: url)
        let paras = m.sections.flatMap(\.blocks).compactMap { b -> Paragraph? in
            if case .paragraph(let p) = b { return p } else { return nil }
        }
        let toc = paras.filter { $0.runs.contains { $0.tocBlock?.hasPrefix("TOC") == true } }
        XCTAssertGreaterThanOrEqual(toc.count, 10, "строки оглавления помечены инструкцией поля")
        let again = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let toc2 = again.sections.flatMap(\.blocks).compactMap { b -> Paragraph? in
            if case .paragraph(let p) = b { return p } else { return nil }
        }.filter { $0.runs.contains { $0.tocBlock?.hasPrefix("TOC") == true } }
        XCTAssertEqual(toc2.count, toc.count)
        XCTAssertEqual(toc2.first?.runs.filter { !$0.text.isEmpty }.compactMap(\.tocBlock).first,
                       toc.first?.runs.filter { !$0.text.isEmpty }.compactMap(\.tocBlock).first)
        XCTAssertEqual(toc2.flatMap(\.runs).compactMap(\.fieldInstr).filter { $0.hasPrefix("PAGEREF") }.count,
                       toc.flatMap(\.runs).compactMap(\.fieldInstr).filter { $0.hasPrefix("PAGEREF") }.count)
    }
}
