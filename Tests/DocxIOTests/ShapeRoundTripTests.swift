import XCTest
import ZIPFoundation
@testable import DocxCore
@testable import DocxIO

/// Фигуры и надписи без ссылок `r:` сохраняются как есть (раньше текст
/// надписи уходил в поток, рамка терялась).
final class ShapeRoundTripTests: XCTestCase {
    private func documentXml(_ data: Data) throws -> String {
        let archive = try Archive(data: data, accessMode: .read)
        var out = Data()
        _ = try archive.extract(archive["word/document.xml"]!) { out.append($0) }
        return String(decoding: out, as: UTF8.self)
    }

    func testFixtureTextBoxSurvives() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/21.docx")
        let m = try DocxIO.importDocx(url: url)
        let raws = m.sections.flatMap(\.blocks).flatMap { b -> [Run] in
            if case .paragraph(let p) = b { return p.runs } else { return [] }
        }.compactMap(\.rawObject)
        XCTAssertEqual(raws.count, 1)
        XCTAssertTrue(raws[0].hasPrefix("<mc:AlternateContent"))
        XCTAssertTrue(raws[0].contains("xmlns:wps="), "пространства имён корня объявлены на объекте")

        let xml = try documentXml(try DocxIO.exportDocx(m))
        XCTAssertEqual(xml.components(separatedBy: "prst=\"star5\"").count, 2)
        XCTAssertEqual(xml.components(separatedBy: "<mc:Fallback>").count, 2)
        XCTAssertNoThrow(try XMLDocument(xmlString: xml), "document.xml корректен")
        // Повторное открытие — тот же объект.
        let again = try DocxIO.importDocx(data: try DocxIO.exportDocx(m))
        let raws2 = again.sections.flatMap(\.blocks).flatMap { b -> [Run] in
            if case .paragraph(let p) = b { return p.runs } else { return [] }
        }.compactMap(\.rawObject)
        XCTAssertEqual(raws2, raws)
    }

    func testObjectWithRelationshipIsNotCaptured() {
        let xml = #"<w:r><w:drawing><a:blip r:embed="rId5"/></w:drawing></w:r><w:r><w:pict><v:shape/></w:pict></w:r>"#
        XCTAssertEqual(OoxmlDocumentParser.scanRawObjects(Data(xml.utf8)), [false, true])
    }
}
