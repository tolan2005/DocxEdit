import XCTest
import DocxCore
@testable import DocxEdit

/// Неотображаемые свойства таблицы переживают правку в редакторе
/// (модель → NSAttributedString → модель), а не только «открыть → сохранить».
@MainActor
final class TablePassthroughBridgeTests: XCTestCase {
    func testTableCellRowExtrasSurviveBridge() {
        var cell = TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: "A")]))], width: 100)
        cell.textDirection = "tbRl"
        cell.extraProperties = ["w:vAlign": "<w:vAlign w:val=\"center\"></w:vAlign>"]
        let empty = TableCell(blocks: [.paragraph(Paragraph(runs: [Run(text: "")]))], width: 100)
        let row = TableRow(cells: [cell, empty], extraProperties: ["w:gridAfter": "<w:gridAfter w:val=\"1\"></w:gridAfter>"])
        var style = TableStyle(); style.namedStyleId = "LightShading"; style.hasBorders = false
        var m = DocumentModel()
        m.sections = [DocumentSection(blocks: [.table(TableBlock(rows: [row], columnWidths: [100, 100], style: style,
                                                                  tblLook: "<w:tblLook w:val=\"04A0\"></w:tblLook>"))])]
        let back = DocumentModel.from(attributed: m.toAttributedString())
        guard case .table(let t)? = back.sections.first?.blocks.first(where: { if case .table = $0 { return true }; return false })
        else { return XCTFail("нет таблицы") }
        XCTAssertEqual(t.style.namedStyleId, "LightShading")
        XCTAssertFalse(t.style.hasBorders)
        XCTAssertEqual(t.tblLook, "<w:tblLook w:val=\"04A0\"></w:tblLook>")
        XCTAssertEqual(t.rows[0].extraProperties?["w:gridAfter"], "<w:gridAfter w:val=\"1\"></w:gridAfter>")
        XCTAssertEqual(t.rows[0].cells[0].textDirection, "tbRl")
        XCTAssertEqual(t.rows[0].cells[0].extraProperties?["w:vAlign"], "<w:vAlign w:val=\"center\"></w:vAlign>")
    }
}
