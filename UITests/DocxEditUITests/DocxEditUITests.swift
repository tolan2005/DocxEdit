import XCTest

final class DocxEditUITests: XCTestCase {
    private var app: XCUIApplication!

    // Тестовый bundle id стартует с пустыми настройками: глушим модальный баннер обновления и welcome.
    private static let quietLaunch = ["-pref.updateCheckFrequency", "never", "-pref.showWelcomeOnLaunch", "<false/>"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = Self.quietLaunch
    }

    override func tearDown() {
        app.terminate()
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/DocxIOTests/Fixtures/\(name)")
    }

    private func documentWindows(titled title: String) -> XCUIElementQuery {
        app.windows.matching(NSPredicate(format: "title == %@", title))
    }

    private func newDocumentViaMenu() {
        app.menuBars.menuBarItems["Файл"].click()
        app.menuBars.menuItems["Новый"].click()
    }

    // ADR-062: cold-start с файлом (Apple Event open, как из Finder) даёт ровно одно окно документа.
    func testColdStartWithFileOpensSingleWindow() {
        app.open(fixture("21.docx"))
        XCTAssertTrue(documentWindows(titled: "21.docx").firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'docx-window'")).count, 1)
    }

    func testTypingInNewDocument() {
        app.launch()
        newDocumentViaMenu()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))
        // Центр NSTextView (лист A4) ниже края окна — кликаем в верх видимой части.
        textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).click()
        textView.typeText("Hello DocxEdit")
        XCTAssertTrue((textView.value as? String ?? "").contains("Hello DocxEdit"))
    }

    func testNewDocumentFromMenuOpensSecondWindow() {
        app.open(fixture("21.docx"))
        XCTAssertTrue(documentWindows(titled: "21.docx").firstMatch.waitForExistence(timeout: 15))
        newDocumentViaMenu()
        XCTAssertTrue(documentWindows(titled: "Без имени").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(documentWindows(titled: "21.docx").firstMatch.exists)
    }
}
