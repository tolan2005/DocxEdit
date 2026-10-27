import XCTest
@testable import DocxCore
@testable import DocxIO

/// Закладки и внутренние ссылки (`w:anchor`) переживают «открыть → сохранить».
/// Раньше закладки жили только в редакторе — DOCX их не читал и не писал.
final class BookmarkRoundTripTests: XCTestCase {
    private func roundTrip(_ m: DocumentModel) throws -> DocumentModel {
        try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
    }

    func testBookmarkAndInternalLinkSurvive() throws {
        var m = DocumentModel()
        var target = Run(text: "Глава 1"); target.bookmark = "_Toc1"
        let link = Run(text: "см. главу", hyperlink: "#_Toc1")
        m.sections = [DocumentSection(blocks: [.paragraph(Paragraph(runs: [target])),
                                               .paragraph(Paragraph(runs: [link]))])]
        let r = try roundTrip(m)
        let runs = r.sections[0].blocks.compactMap { b -> [Run]? in
            if case .paragraph(let p) = b { return p.runs } else { return nil } }.flatMap { $0 }
        XCTAssertEqual(runs.first { $0.text == "Глава 1" }?.bookmark, "_Toc1")
        XCTAssertEqual(runs.first { $0.text == "см. главу" }?.hyperlink, "#_Toc1")
    }

    func testRealFixtureKeepsBookmarksAndAnchors() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/21.docx")
        let out = try DocxIO.exportDocx(try DocxIO.importDocx(url: url))
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try out.write(to: tmp); defer { try? FileManager.default.removeItem(at: tmp) }
        let xml = String(decoding: try documentXml(tmp), as: UTF8.self)
        XCTAssertGreaterThanOrEqual(xml.components(separatedBy: "<w:bookmarkStart").count - 1, 10)
        XCTAssertGreaterThanOrEqual(xml.components(separatedBy: "w:anchor=\"_Toc").count - 1, 10)
        XCTAssertFalse(xml.contains("_GoBack"))
    }

    private func documentXml(_ url: URL) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, "word/document.xml"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return d
    }
}
