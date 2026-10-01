import XCTest

final class DocxEditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
    }

    private func fixture(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/DocxIOTests/Fixtures/\(name)").path
    }

    private func documentWindows(titled title: String) -> XCUIElementQuery {
        app.windows.matching(NSPredicate(format: "title == %@", title))
    }

    // ADR-062: cold-start с файлом даёт ровно одно окно документа.
    func testColdStartWithFileOpensSingleWindow() {
        app.launchArguments = [fixture("21.docx")]
        app.launch()
        XCTAssertTrue(documentWindows(titled: "21.docx").firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(documentWindows(titled: "21.docx").count, 1)
    }

    func testTypingInNewDocument() {
        app.launch()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        textView.click()
        textView.typeText("Hello DocxEdit")
        XCTAssertTrue((textView.value as? String ?? "").contains("Hello DocxEdit"))
    }

    func testNewDocumentFromMenuOpensSecondWindow() {
        app.launchArguments = [fixture("21.docx")]
        app.launch()
        XCTAssertTrue(documentWindows(titled: "21.docx").firstMatch.waitForExistence(timeout: 10))
        let before = app.windows.count
        app.menuBars.menuBarItems["Файл"].click()
        app.menuBars.menuItems["Новый"].click()
        let grew = expectation(for: NSPredicate(format: "count > %d", before), evaluatedWith: app.windows)
        wait(for: [grew], timeout: 10)
    }
}
