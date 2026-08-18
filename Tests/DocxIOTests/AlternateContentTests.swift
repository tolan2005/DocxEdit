import XCTest
import ZIPFoundation
@testable import DocxIO
@testable import DocxCore

/// v1.5.7: mc:AlternateContent в теле документа — текст mc:Fallback подавляем
/// (дубль mc:Choice), картинку-превью v:imagedata извлекаем как inline image.
final class AlternateContentTests: XCTestCase {

    /// Минимальный валидный .docx как in-memory ZIP (хелпер как в DocxFuzzTests).
    private func makeDocx(files: [(path: String, data: Data)]) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ac-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let archive = Archive(url: tmp, accessMode: .create) else {
            throw NSError(domain: "test", code: 1)
        }
        for f in files {
            try archive.addEntry(with: f.path, type: .file,
                                 uncompressedSize: Int64(f.data.count),
                                 provider: { pos, size in
                f.data.subdata(in: Int(pos)..<Int(pos)+size)
            })
        }
        return try Data(contentsOf: tmp)
    }

    /// 1×1 прозрачный PNG.
    private let tinyPng = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!

    private func base(bodyXml: String) throws -> Data {
        let contentTypes = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Default Extension="png" ContentType="image/png"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """
        let mainRels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """
        let docRels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
            </Relationships>
            """
        let doc = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                        xmlns:v="urn:schemas-microsoft-com:vml"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <w:body>\(bodyXml)</w:body>
            </w:document>
            """
        return try makeDocx(files: [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(mainRels.utf8)),
            ("word/document.xml", Data(doc.utf8)),
            ("word/_rels/document.xml.rels", Data(docRels.utf8)),
            ("word/media/image1.png", tinyPng),
        ])
    }

    /// Текстбокс в mc:Choice + его VML-дубль в mc:Fallback → текст один раз.
    func testFallbackTextNotDuplicated() throws {
        let body = """
            <w:p><w:r><mc:AlternateContent>
            <mc:Choice Requires="wps"><w:drawing><wp:inline><wp:extent cx="100" cy="100"/>
            <wps:txbx xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><w:txbxContent>
            <w:p><w:r><w:t>Оригинал</w:t></w:r></w:p>
            </w:txbxContent></wps:txbx></wp:inline></w:drawing></mc:Choice>
            <mc:Fallback><w:pict><v:shape style="width:100pt;height:50pt"><v:textbox><w:txbxContent>
            <w:p><w:r><w:t>Оригинал</w:t></w:r></w:p>
            </w:txbxContent></v:textbox></v:shape></w:pict></mc:Fallback>
            </mc:AlternateContent></w:r></w:p>
            """
        let model = try DocxIO.importDocx(data: base(bodyXml: body))
        let allText = model.sections.flatMap { $0.blocks }.compactMap { block -> String? in
            if case .paragraph(let p) = block { return p.runs.map(\.text).joined() }
            return nil
        }.joined()
        XCTAssertEqual(allText, "Оригинал", "текст Fallback не должен дублироваться")
    }

    /// SmartArt/диаграмма: в mc:Fallback лежит v:imagedata-превью → картинка.
    func testFallbackImageExtracted() throws {
        let body = """
            <w:p><w:r><mc:AlternateContent>
            <mc:Choice Requires="wps"><w:drawing><wp:inline><wp:extent cx="100" cy="100"/>
            <wpg:wgp xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"/>
            </wp:inline></w:drawing></mc:Choice>
            <mc:Fallback><w:pict>
            <v:shape style="width:93.65pt;height:33.5pt"><v:imagedata r:id="rId5"/></v:shape>
            </w:pict></mc:Fallback>
            </mc:AlternateContent></w:r></w:p>
            """
        let model = try DocxIO.importDocx(data: base(bodyXml: body))
        let images = model.sections.flatMap { $0.blocks }.flatMap { block -> [Run] in
            if case .paragraph(let p) = block { return p.runs }
            return []
        }.compactMap(\.image)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first.map { Double($0.displayWidth) } ?? 0, 93.65, accuracy: 0.01)
        XCTAssertEqual(images.first.map { Double($0.displayHeight) } ?? 0, 33.5, accuracy: 0.01)
        XCTAssertEqual(images.first?.format, .png)
    }
}
