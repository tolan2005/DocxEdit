import XCTest
import AppKit
@testable import DocxCore
@testable import DocxEdit

/// v1.6.5: перемещение разделов из навигатора — логика диапазонов и
/// атомарной перестановки в attributed string (headless, без окна).
final class NavigatorSectionMoveTests: XCTestCase {

    private func heading(_ text: String, level: Int) -> Paragraph {
        var attrs = ParagraphAttributes()
        attrs.styleId = "Heading\(level)"
        return Paragraph(runs: [Run(text: text, attributes: .init())], attributes: attrs)
    }

    private func body(_ text: String) -> Paragraph {
        Paragraph(runs: [Run(text: text, attributes: .init())])
    }

    @MainActor
    private func makeStorage() -> (NSTextStorage, DocumentController) {
        let model = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(heading("Глава 1", level: 1)),
            .paragraph(body("текст главы 1")),
            .paragraph(heading("Раздел 1.1", level: 2)),
            .paragraph(body("текст подраздела")),
            .paragraph(heading("Глава 2", level: 1)),
            .paragraph(body("текст главы 2")),
        ])])
        let attributed = model.toAttributedString(defaultFont: .systemFont(ofSize: 12))
        let storage = NSTextStorage(attributedString: attributed)
        let controller = DocumentController()
        controller.textView = NSTextView(frame: .zero)
        controller.textView?.textStorage?.setAttributedString(storage)
        return (storage, controller)
    }

    /// Раздел «Глава 2» перемещается выше «Раздела 1.1» — но НЕ выше
    /// «Главы 1» (граница раздела — по уровню).
    @MainActor
    func testSectionRangeRespectsLevel() throws {
        let (storage, controller) = makeStorage()
        let headings = controller.navigatorHeadings()
        XCTAssertEqual(headings.map(\.text), ["Глава 1", "Раздел 1.1", "Глава 2"])

        // Раздел «Глава 1» должен заканчиваться перед «Раздел 1.1»? НЕТ:
        // «Раздел 1.1» — уровень 2 > 1, значит входит в «Главу 1».
        let h1 = headings[0]
        let ns = storage.string as NSString
        let range1 = controller.sectionRange(of: h1, in: storage)
        let text1 = ns.substring(with: range1)
        XCTAssertTrue(text1.contains("текст подраздела"),
                      "подраздел должен входить в раздел Главы 1: \(text1)")

        // «Глава 2» — только её собственный текст.
        let range2 = controller.sectionRange(of: headings[2], in: storage)
        XCTAssertEqual(ns.substring(with: range2).contains("Раздел 1.1"), false)
    }

    /// Перемещение «Главы 2» вверх — один undo-шаг, текст не дублируется.
    @MainActor
    func testMoveSectionReordersText() throws {
        let (_, controller) = makeStorage()
        // ВАЖНО: берём storage самого textView — setAttributedString копирует
        // содержимое, и внешний инстанс не увидит правок.
        let storage = try XCTUnwrap(controller.textView?.textStorage)
        let before = storage.string

        controller.moveSection(from: 2, to: 0)

        let after = storage.string as NSString
        // Порядок заголовков сменился.
        let h1 = after.range(of: "Глава 2").location
        let h2 = after.range(of: "Глава 1").location
        XCTAssertLessThan(h1, h2, "Глава 2 должна встать выше Главы 1")
        // Ничего не потеряно и не задублировано.
        XCTAssertEqual(after.replacingOccurrences(of: "\n", with: "").count,
                       (before as NSString).replacingOccurrences(of: "\n", with: "").count)
    }
}
