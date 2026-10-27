import XCTest
@testable import DocxCore
@testable import DocxIO

/// Свойства ячеек, которые модель не разбирает (рамки ячейки, вертикальное
/// выравнивание, «не переносить»…), переживают «открыть → сохранить».
final class TableCellExtrasRoundTripTests: XCTestCase {
    private func xml(_ data: Data) throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", tmp.path, "word/document.xml"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
    private func count(_ s: String, _ tag: String) -> Int {
        ["<\(tag)>", "<\(tag) ", "<\(tag)/>"].reduce(0) { $0 + s.components(separatedBy: $1).count - 1 }
    }

    func testFixtureCellPropertiesSurvive() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in ["21.docx", "24.docx"] {
            let src = try Data(contentsOf: dir.appendingPathComponent(name))
            let before = try xml(src)
            let after = try xml(try DocxIO.exportDocx(try DocxIO.importDocx(data: src)))
            for tag in ["w:tcBorders", "w:vAlign", "w:noWrap", "w:hideMark", "w:tblLook", "w:gridAfter", "w:wAfter"] {
                XCTAssertEqual(count(after, tag), count(before, tag), "\(name): \(tag)")
            }
        }
    }

    func testCapturedXmlIsWrittenInSchemaOrder() throws {
        var cell = TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: "x")]))])
        cell.backgroundColor = CodableColor(red: 1, green: 0, blue: 0)
        cell.extraProperties = ["w:vAlign": "<w:vAlign w:val=\"center\"></w:vAlign>",
                                "w:tcBorders": "<w:tcBorders><w:top w:val=\"single\"></w:top></w:tcBorders>"]
        var m = DocumentModel()
        m.sections = [DocumentSection(blocks: [.table(TableBlock(rows: [TableRow(cells: [cell])], columnWidths: [100]))])]
        let out = try xml(try DocxIO.exportDocx(m))
        let b = out.range(of: "<w:tcBorders>")!.lowerBound, shd = out.range(of: "<w:shd")!.lowerBound,
            v = out.range(of: "<w:vAlign")!.lowerBound
        XCTAssertTrue(b < shd && shd < v, "tcBorders → shd → vAlign")
        XCTAssertEqual(try DocxIO.importDocx(data: try DocxIO.exportDocx(m)).sections[0].blocks.first.flatMap {
            if case .table(let t) = $0 { return t.rows[0].cells[0].extraProperties?["w:vAlign"] } else { return nil } },
            "<w:vAlign w:val=\"center\"></w:vAlign>")
    }
}
