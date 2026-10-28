import XCTest
import AppKit
@testable import DocxCore
@testable import DocxEdit

/// Удаление пункта нумерованного списка перенумеровывает блок.
@MainActor
final class ListDeleteRenumberTests: XCTestCase {
    func testDeletingItemRenumbers() {
        let info = ListInfo(listType: .numbered, level: 0, continuation: .continue, formatStyle: .decimal)
        var pa = ParagraphAttributes(); pa.listInfo = info
        let model = DocumentModel(sections: [DocumentSection(blocks: ["один", "два", "три"].map {
            .paragraph(Paragraph(runs: [Run(text: $0)], attributes: pa))
        })])
        let controller = DocumentController()
        let tv = NSTextView(frame: .zero)
        controller.textView = tv
        tv.textStorage?.setAttributedString(model.toAttributedString(defaultFont: .systemFont(ofSize: 12)))
        let text = tv.string as NSString
        XCTAssertTrue(tv.string.hasPrefix("1. один\n2. два\n3. три"), tv.string)
        // Выделяем пункт «2. два\n» целиком и удаляем.
        let item = text.paragraphRange(for: text.range(of: "два"))
        controller.noteListStructureChange(range: item, replacement: "")
        tv.textStorage?.replaceCharacters(in: item, with: "")
        tv.setSelectedRange(NSRange(location: item.location, length: 0))
        if controller.consumePendingListRenumber() { controller.renumberCurrentListBlock() }
        XCTAssertTrue(tv.string.hasPrefix("1. один\n2. три"), tv.string)
    }

    func testTypingInsideItemDoesNotRenumber() {
        let controller = DocumentController()
        controller.noteListStructureChange(range: NSRange(location: 0, length: 0), replacement: "x")
        XCTAssertFalse(controller.consumePendingListRenumber())
    }
}
