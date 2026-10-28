import XCTest
import DocxCore
@testable import DocxEdit

/// Фигура (`Run.rawObject`) переживает правку в редакторе.
@MainActor
final class RawObjectBridgeTests: XCTestCase {
    func testRawObjectSurvivesBridge() {
        var shape = Run(text: "\u{FFFC}")
        shape.rawObject = "<w:pict><v:shape><w:t>Надпись</w:t></v:shape></w:pict>"
        var m = DocumentModel()
        m.sections = [DocumentSection(blocks: [.paragraph(Paragraph(runs: [Run(text: "До "), shape, Run(text: " после")]))])]
        let attr = NSMutableAttributedString(attributedString: m.toAttributedString())
        attr.append(NSAttributedString(string: "!", attributes: attr.attributes(at: attr.length - 1, effectiveRange: nil)))
        let back = DocumentModel.from(attributed: attr)
        guard case .paragraph(let p)? = back.sections.first?.blocks.first else { return XCTFail() }
        XCTAssertEqual(p.runs.compactMap(\.rawObject), [shape.rawObject!])
        XCTAssertEqual(p.runs.map(\.text).joined(), "До \u{FFFC} после!")
    }
}
