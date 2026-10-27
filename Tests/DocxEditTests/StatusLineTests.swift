import XCTest
@testable import DocxEdit

/// v1.10.5: счётчик в статусбаре — «N из M» при выделении.
@MainActor
final class StatusLineTests: XCTestCase {
    func testWholeDocumentWithoutSelection() {
        XCTAssertEqual(DocumentController.statusLine(words: 340, characters: 2105, selection: "", language: "ru-RU"),
                       "Слов: 340 · Символов: 2105 · ru-RU")
    }

    func testSelectionCountsOutOfTotal() {
        XCTAssertEqual(DocumentController.statusLine(words: 340, characters: 2105,
                                                     selection: "Два слова", language: "ru-RU"),
                       "Слов: 2 из 340 · Символов: 9 из 2105 · ru-RU")
    }
}
