import XCTest
@testable import DocxEdit

/// Вход в source/гибрид не должен переписывать .md через модель (теряются задачи, нумерация).
final class MarkdownSourceFidelityTests: XCTestCase {
    private let raw = "- [ ] купить\n- [x] готово\n\n1. один\n2. два\n"

    @MainActor
    private func session() -> DocumentSession {
        let s = DocumentSession()
        s.mode = .markdown
        s.loadMarkdownSource(raw)
        return s
    }

    @MainActor
    func testHybridKeepsOriginalFileText() {
        let s = session()
        s.enterMarkdownHybridMode()
        XCTAssertEqual(s.markdownSource, raw)
    }

    @MainActor
    func testSourceAndSplitKeepOriginalFileText() {
        let s = session()
        s.enterMarkdownSourceMode()
        XCTAssertEqual(s.markdownSource, raw)
        s.exitMarkdownSourceMode()
        s.enterMarkdownSplitMode()
        XCTAssertEqual(s.markdownSource, raw)
    }

    @MainActor
    func testVisualEditRegeneratesSourceFromModel() {
        let s = session()
        s.applyAttributed(NSAttributedString(string: "новый текст\n"))
        s.enterMarkdownSourceMode()
        XCTAssertTrue(s.markdownSource.contains("новый текст"))
    }
}

final class MarkdownDefaultHybridTests: XCTestCase {
    @MainActor
    func testMarkdownModeDefaultsToHybrid() {
        let s = DocumentSession()
        s.mode = .docx
        XCTAssertFalse(s.isMarkdownHybrid)
        s.mode = .markdown
        XCTAssertTrue(s.isMarkdownHybrid)
        XCTAssertTrue(s.isMarkdownSourceMode)
    }

    @MainActor
    func testExplicitVisualChoiceSticksUntilModeChanges() {
        let s = DocumentSession()
        s.mode = .markdown
        s.exitMarkdownSourceMode()
        XCTAssertFalse(s.isMarkdownHybrid)
        XCTAssertFalse(s.isMarkdownSourceMode)
    }
}
