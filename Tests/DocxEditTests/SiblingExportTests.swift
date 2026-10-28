import XCTest
@testable import DocxEdit

/// «Копия рядом с файлом»: то же имя, другое расширение; не поверх самого документа.
@MainActor
final class SiblingExportTests: XCTestCase {
    func testSiblingURL() {
        let md = URL(fileURLWithPath: "/tmp/Отчёт.md")
        XCTAssertEqual(AppDelegate.siblingURL(of: md, ext: "pdf")?.path, "/tmp/Отчёт.pdf")
        XCTAssertEqual(AppDelegate.siblingURL(of: md, ext: "docx")?.path, "/tmp/Отчёт.docx")
        XCTAssertNil(AppDelegate.siblingURL(of: URL(fileURLWithPath: "/tmp/a.docx"), ext: "docx"))
    }
}
