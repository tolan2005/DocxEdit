//
//  HeaderFooterPassthroughTests.swift
//  DocxIOTests
//
//  v1.5.1 (DESIGN_HEADER_FOOTER.md): lossless passthrough колонтитулов —
//  графика/текстбоксы/рамки переживают open→save, слоты резолвятся по rels,
//  сложное содержимое отражается в ImportReport.
//  Fixture 133.docx — реальный файл пользователя с графикой и текстбоксами
//  в first/even/default колонтитулах (не удалять).
//

import XCTest
import ZIPFoundation
@testable import DocxCore
@testable import DocxIO

final class HeaderFooterPassthroughTests: XCTestCase {

    private var fixture133: Data {
        let url = Bundle.module.url(forResource: "133", withExtension: "docx",
                                    subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    private func zipEntries(_ data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        var out: [String: Data] = [:]
        for entry in archive {
            var buf = Data()
            _ = try archive.extract(entry) { buf.append($0) }
            out[entry.path] = buf
        }
        return out
    }

    // MARK: - Слоты резолвятся по rels, а не по имени файла

    func testSlotsResolvedViaRels() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        // В 133.docx: header1.xml=even (плейсхолдеры «[Escriba texto]»),
        // header2.xml=default (ТОЛЬКО графика, без текста),
        // header3.xml=first (текстбокс со странами).
        XCTAssertTrue(model.headerFooter.evenHeaderText.contains("[Escriba texto]"),
                      "even-слот должен прийти из header1.xml: \(model.headerFooter.evenHeaderText)")
        XCTAssertTrue(model.headerFooter.firstHeaderText.contains("Argentina"),
                      "first-слот должен прийти из header3.xml")
        XCTAssertTrue(model.headerFooter.headerText.isEmpty,
                      "default-слот (header2.xml) — только графика, текста нет: \(model.headerFooter.headerText)")
    }

    // MARK: - ImportReport видит сложные колонтитулы

    func testImportReportCoversHeaders() throws {
        let (_, report) = try DocxIO.importDocxWithReport(data: fixture133)
        let hfEntries = report.entries.filter { $0.category == "Колонтитулы" }
        XCTAssertFalse(hfEntries.isEmpty, "отчёт об открытии должен видеть сложные колонтитулы")
        XCTAssertTrue(hfEntries.contains { $0.element == "Графика в колонтитулах" })
        XCTAssertTrue(hfEntries.contains { $0.element == "Текстовые фреймы в колонтитулах" })
    }

    // MARK: - Passthrough: байты частей и media переживают экспорт

    func testHeaderGraphicsSurviveRoundTrip() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        XCTAssertFalse(model.preservedHeaderFooter.isEmpty)
        XCTAssertFalse(model.headerFooterEdited)

        let exported = try DocxIO.exportDocx(model)
        let entries = try zipEntries(exported)

        // Слот default = header2.xml оригинала — байты должны совпасть.
        let original = try zipEntries(fixture133)
        let preserved = model.preservedHeaderFooter["headerDefault"]
        XCTAssertEqual(preserved?.partName, "header2.xml")
        XCTAssertEqual(entries["word/header2.xml"], original["word/header2.xml"],
                       "header default должен писаться сырыми байтами")

        // Media из колонтитула — под переписанными именами hfp_*.
        let media = entries.keys.filter { $0.hasPrefix("word/media/hfp_") }
        XCTAssertFalse(media.isEmpty, "media колонтитулов потеряны: \(entries.keys.sorted())")

        // Rels части сохранены.
        XCTAssertNotNil(entries["word/_rels/header2.xml.rels"])
        // И target'ы переписаны на hfp_.
        let rels = String(data: entries["word/_rels/header2.xml.rels"]!, encoding: .utf8)!
        XCTAssertTrue(rels.contains("media/hfp_"), rels)

        // Повторный импорт экспортированного файла — тот же текст колонтитула.
        let (reopened, _) = try DocxIO.importDocxWithReport(data: exported)
        XCTAssertEqual(reopened.headerFooter.headerText, model.headerFooter.headerText)
    }

    // MARK: - Редактирование колонтитула отключает passthrough

    func testEditDisablesPassthrough() throws {
        var (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        model.headerFooter.headerText = "Новый колонтитул"
        model.headerFooterEdited = true

        let exported = try DocxIO.exportDocx(model)
        let entries = try zipEntries(exported)

        // Части регенерированы: наш writer пишет header1.xml для default.
        let xml = String(data: try XCTUnwrap(entries["word/header1.xml"]), encoding: .utf8)!
        XCTAssertTrue(xml.contains("Новый колонтитул"), xml)
        XCTAssertFalse(xml.contains("<w:drawing"), "при редактировании часть регенерируется")
        XCTAssertFalse(entries.keys.contains { $0.hasPrefix("word/media/hfp_") })
    }

    // MARK: - Codable (autorecover JSON)

    func testPreservedPartsSurviveCodable() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        let data = try JSONEncoder().encode(model)
        let back = try JSONDecoder().decode(DocumentModel.self, from: data)
        XCTAssertEqual(back.preservedHeaderFooter, model.preservedHeaderFooter)
        XCTAssertEqual(back.headerFooterEdited, model.headerFooterEdited)
    }

    // MARK: - Свои файлы (без графики) — поведение не изменилось

    func testOwnFileRoundTripUnchanged() throws {
        var hf = HeaderFooter()
        hf.headerText = "Отчёт"
        let model = DocumentModel(headerFooter: hf)
        let exported = try DocxIO.exportDocx(model)
        let entries = try zipEntries(exported)
        let xml = String(data: try XCTUnwrap(entries["word/header1.xml"]), encoding: .utf8)!
        XCTAssertTrue(xml.contains("Отчёт"))
        let (reopened, _) = try DocxIO.importDocxWithReport(data: exported)
        XCTAssertEqual(reopened.headerFooter.headerText, "Отчёт")
    }

    // MARK: - v1.5.2: дедупликация текстбоксов (mc:AlternateContent)

    func testTextboxTextNotDuplicated() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        // Текстбокс со странами в mc:AlternateContent (Choice + VML-Fallback)
        // раньше читался дважды: «ArgentinaAustralia…Ukraine Argentina…».
        let first = model.headerFooter.firstHeaderText
        let occurrences = first.components(separatedBy: "Argentina").count - 1
        XCTAssertEqual(occurrences, 1, "текстбокс задвоен: \(first)")
        // Соседние «абзацы» текстбокса разделены пробелом, а не склеены.
        XCTAssertTrue(first.contains("Argentina Australia"), first)
    }

    // MARK: - v1.5.2: passthrough неизвестных частей пакета

    func testUnknownPartsSurvive() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        // В 133.docx есть customXml, theme1.xml, fontTable.xml, webSettings.xml,
        // endnotes.xml, docProps/app.xml.
        XCTAssertNotNil(model.preservedParts["word/theme/theme1.xml"])
        XCTAssertNotNil(model.preservedParts["word/fontTable.xml"])
        XCTAssertNotNil(model.preservedParts["word/webSettings.xml"])
        XCTAssertNotNil(model.preservedParts["word/endnotes.xml"])
        XCTAssertNotNil(model.preservedParts["docProps/app.xml"])
        XCTAssertNotNil(model.preservedParts["customXml/item1.xml"])
        XCTAssertNotNil(model.preservedSettingsXml)

        let exported = try DocxIO.exportDocx(model)
        let out = try zipEntries(exported)
        let orig = try zipEntries(fixture133)
        for key in ["word/theme/theme1.xml", "word/fontTable.xml",
                    "word/webSettings.xml", "word/endnotes.xml",
                    "docProps/app.xml", "customXml/item1.xml",
                    "customXml/itemProps1.xml", "customXml/_rels/item1.xml.rels",
                    "word/settings.xml"] {
            XCTAssertEqual(out[key], orig[key], "часть \(key) не пережила round-trip")
        }
        // Content_Types покрывает preserved-части.
        let ct = String(data: try XCTUnwrap(out["[Content_Types].xml"]), encoding: .utf8)!
        XCTAssertTrue(ct.contains("theme1.xml"), ct)
        XCTAssertTrue(ct.contains("fontTable.xml"), ct)
        XCTAssertTrue(ct.contains("settings.xml"), ct)
    }

    // MARK: - v1.5.2: evenAndOddHeaders инжектится в оригинальный settings.xml

    func testEvenOddInjectedIntoPreservedSettings() throws {
        var (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        XCTAssertNotNil(model.preservedSettingsXml)
        model.headerFooter.differentOddEven = true
        let exported = try DocxIO.exportDocx(model)
        let out = try zipEntries(exported)
        let settings = String(data: try XCTUnwrap(out["word/settings.xml"]), encoding: .utf8)!
        XCTAssertTrue(settings.contains("<w:evenAndOddHeaders/>"), settings)
        // Оригинальное содержимое (напр. w:zoom или compat) не потеряно.
        let origSettings = String(data: try XCTUnwrap(zipEntries(fixture133)["word/settings.xml"]), encoding: .utf8)!
        if origSettings.contains("<w:zoom") {
            XCTAssertTrue(settings.contains("<w:zoom"), "оригинальный settings.xml потерян")
        }
    }

    // MARK: - v1.5.4: passthrough extras sectPr (w:cols / w:docGrid / w:pgNumType)

    func testSectPrExtrasSurvive() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        // 133.docx: <w:pgNumType w:start="1"/><w:cols w:space="720"/><w:docGrid w:linePitch="326"/>
        let extras = try XCTUnwrap(model.preservedSectPrExtras)
        XCTAssertTrue(extras.contains("<w:pgNumType"), extras)
        XCTAssertTrue(extras.contains("<w:cols"), extras)
        XCTAssertTrue(extras.contains("<w:docGrid"), extras)
        // Обработанные нами дети в extras не попадают.
        XCTAssertFalse(extras.contains("headerReference"), extras)
        XCTAssertFalse(extras.contains("<w:pgSz"), extras)
        XCTAssertFalse(extras.contains("<w:pgMar"), extras)

        let exported = try DocxIO.exportDocx(model)
        let out = try zipEntries(exported)
        let docXml = String(data: try XCTUnwrap(out["word/document.xml"]), encoding: .utf8)!
        XCTAssertTrue(docXml.contains(#"<w:cols w:space="720"/>"#), "w:cols потерян при экспорте")
        XCTAssertTrue(docXml.contains("<w:docGrid"), docXml.suffix(800).description)
        XCTAssertTrue(docXml.contains(#"<w:pgNumType w:start="1"/>"#))
    }

    // MARK: - v1.5.3: плавающие изображения колонтитулов (позиции для рендера)

    func testHeaderImagePlacementsParsed() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        // header2.xml (default) содержит wp:anchor-картинку логотипа
        // (extent 2171700×718185 EMU ≈ 171×57 pt, rId1 → media/image2.png).
        let def = try XCTUnwrap(model.preservedHeaderFooter["headerDefault"])
        XCTAssertEqual(def.images.count, 1, "ожидалась одна плавающая картинка: \(def.images)")
        let img = def.images[0]
        XCTAssertEqual(img.cxEMU, 2171700)
        XCTAssertEqual(img.cyEMU, 718185)
        XCTAssertTrue(img.mediaName.hasPrefix("hfp_headerDefault_"), img.mediaName)
        XCTAssertNotNil(def.media[img.mediaName], "media для картинки должна быть сохранена")
        // Codable round-trip placements (autorecover).
        let back = try JSONDecoder().decode(DocumentModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(back.preservedHeaderFooter["headerDefault"]?.images, def.images)
    }

    // MARK: - v1.5.14: водяные знаки (VML w:pict в колонтитулах)
    /// Собирает минимальный docx с header1.xml, содержащим заданный w:pict.
    private func makeDocxWithWatermarkHeader(_ pict: String) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wm-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let archive = Archive(url: tmp, accessMode: .create) else {
            throw NSError(domain: "test", code: 1)
        }
        func add(_ path: String, _ content: String) throws {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 provider: { pos, size in
                data.subdata(in: Int(pos)..<Int(pos)+size)
            })
        }
        try add("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
            </Types>
            """)
        try add("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """)
        try add("word/_rels/document.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rIdH1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
            </Relationships>
            """)
        try add("word/document.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <w:body><w:p><w:r><w:t>Текст</w:t></w:r></w:p>
            <w:sectPr><w:headerReference w:type="default" r:id="rIdH1"/></w:sectPr></w:body>
            </w:document>
            """)
        try add("word/header1.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                   xmlns:v="urn:schemas-microsoft-com:vml"
                   xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <w:p><w:r>\(pict)</w:r></w:p>
            </w:hdr>
            """)
        return try Data(contentsOf: tmp)
    }

    /// WordArt-водяной знак (v:textpath) парсится с текстом/позицией/поворотом.
    func testTextWatermarkParsed() throws {
        let pict = """
            <w:pict><v:shapetype id="_x0000_t136" coordsize="21600,21600" o:spt="136"
             adj="10800" path="m@7,0l@8,0m@5,21600l@6,21600e">
             <v:formulas></v:formulas></v:shapetype>
            <v:shape id="PowerPlusWaterMarkObject1" o:spid="_x0000_s2049" type="#_x0000_t136"
             style="position:absolute;margin-left:0;margin-top:0;width:468pt;height:117pt;rotation:315;z-index:-251654144"
             fillcolor="#C0C0C0">
             <v:textpath on="t" string="КОНФИДЕНЦИАЛЬНО" style="font-family:&quot;Calibri&quot;;font-size:1pt"/>
            </v:shape></w:pict>
            """
        let (model, _) = try DocxIO.importDocxWithReport(
            data: makeDocxWithWatermarkHeader(pict))
        let def = try XCTUnwrap(model.preservedHeaderFooter["headerDefault"])
        let wm = try XCTUnwrap(def.watermarks.first, "водяной знак не распознан")
        XCTAssertEqual(wm.text, "КОНФИДЕНЦИАЛЬНО")
        XCTAssertEqual(wm.rotation, 315)
        XCTAssertEqual(wm.wPt, 468, accuracy: 0.1)
        XCTAssertEqual(wm.hPt, 117, accuracy: 0.1)
        XCTAssertEqual(wm.colorHex, "#C0C0C0")
        // Passthrough: часть колонтитула пишется обратно как есть.
        let out = try zipEntries(DocxIO.exportDocx(model))
        let hdr = String(data: try XCTUnwrap(out["word/header1.xml"]), encoding: .utf8)!
        XCTAssertTrue(hdr.contains("КОНФИДЕНЦИАЛЬНО"), hdr)
    }

    /// w:pict внутри mc:Fallback (VML-дубль текстбокса) — НЕ водяной знак.
    func testFallbackPictNotWatermark() throws {
        let (model, _) = try DocxIO.importDocxWithReport(data: fixture133)
        for (slot, part) in model.preservedHeaderFooter {
            XCTAssertTrue(part.watermarks.isEmpty,
                          "fallback-VML в \(slot) не должен попадать в водяные знаки")
        }
    }
}
