import XCTest
import DocxCore
@testable import DocxEdit

/// v1.10.7: ⌘S пишет файл в формате его расширения (раньше .rtf/.odt/.txt становились DOCX).
@MainActor
final class SaveFormatTests: XCTestCase {
    private func model(_ text: String) -> DocumentModel {
        var m = DocumentModel()
        m.sections = [DocumentSection(blocks: [.paragraph(Paragraph(runs: [Run(text: text, attributes: .init())]))])]
        return m
    }

    func testEachExtensionKeepsItsFormat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func head(_ name: String) throws -> Data {
            let url = dir.appendingPathComponent(name)
            try AppDelegate.writeDocument(model("Привет"), to: url)
            return try Data(contentsOf: url).prefix(5)
        }
        XCTAssertEqual(String(decoding: try head("a.rtf"), as: UTF8.self), "{\\rtf")
        _ = try head("a.txt")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("a.txt"), encoding: .utf8), "Привет")
        XCTAssertEqual(Array(try head("a.docx").prefix(2)), [0x50, 0x4B])   // ZIP (DOCX)
        XCTAssertEqual(Array(try head("a.odt").prefix(2)), [0x50, 0x4B])    // ZIP (ODT)
        let odt = try Data(contentsOf: dir.appendingPathComponent("a.odt"))
        XCTAssertNotNil(odt.range(of: Data("application/vnd.oasis.opendocument.text".utf8)))
    }
}
