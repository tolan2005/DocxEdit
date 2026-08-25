import XCTest
import AppKit
@testable import DocxEdit

/// v1.6.6: умная вставка Markdown — эвристика «похож ли plain-text на MD»,
/// санитайзер артефактов ИИ-чатов и интеграция вставки через контроллер.
final class SmartMarkdownPasteTests: XCTestCase {

    // MARK: - Санитайзер

    /// Пробел перед закрывающим разделителем — типовой артефакт ChatGPT:
    /// `***Текст заголовка ***` не парсится CommonMark, звёздочки остаются
    /// буквами. Санитайзер должен подтянуть разделитель к слову.
    func testSanitizeFixesTrailingSpaceInEmphasis() {
        XCTAssertEqual(MarkdownPasteSupport.sanitize("***Текст ***"), "***Текст***")
        XCTAssertEqual(MarkdownPasteSupport.sanitize("**жирный **"), "**жирный**")
        XCTAssertEqual(MarkdownPasteSupport.sanitize("*курсив *"), "*курсив*")
    }

    func testSanitizeRemovesZeroWidthCharacters() {
        let dirty = "te\u{200B}xt\u{FEFF}**bo\u{200C}ld **"
        XCTAssertEqual(MarkdownPasteSupport.sanitize(dirty), "text**bold**")
    }

    func testSanitizeKeepsHealthyMarkdownUntouched() {
        let ok = "# Заголовок\n\n**жирный** и *курсив* — ок."
        XCTAssertEqual(MarkdownPasteSupport.sanitize(ok), ok)
    }

    // MARK: - Эвристика: позитивы

    func testLooksLikeMarkdownChatAnswer() {
        // Типовой ответ из ИИ-чата с артефактами.
        let chat = """
        ### Преимущества подхода

        **Производительность.** Алгоритм работает за O(n log n) *в среднем *.

        - Быстрая сортировка
        - Стабильная память
        - Простая реализация

        1. Подготовить данные
        2. Запустить тесты

        Подробнее в [документации](https://example.com).
        """
        XCTAssertTrue(MarkdownPasteSupport.looksLikeMarkdown(chat))
    }

    func testLooksLikeMarkdownTable() {
        let table = """
        | Колонка | Значение |
        |---|---|
        | A | 1 |
        | B | 2 |
        """
        XCTAssertTrue(MarkdownPasteSupport.looksLikeMarkdown(table))
    }

    func testLooksLikeMarkdownCodeFence() {
        XCTAssertTrue(MarkdownPasteSupport.looksLikeMarkdown("Пример:\n```swift\nlet x = 1\n```"))
    }

    // MARK: - Эвристика: негативы

    func testPlainRussianParagraphIsNotMarkdown() {
        XCTAssertFalse(MarkdownPasteSupport.looksLikeMarkdown(
            "Просто обычный текст письма без какой-либо разметки, набранный вручную."))
    }

    func testSingleAsteriskIsNotMarkdown() {
        XCTAssertFalse(MarkdownPasteSupport.looksLikeMarkdown(
            "Умножение 3 * 4 = 12 и сноска* в конце предложения."))
    }

    func testShortTextIsNotMarkdown() {
        XCTAssertFalse(MarkdownPasteSupport.looksLikeMarkdown("- пункт"))
    }

    // MARK: - Интеграция: insertMarkdownText через контроллер

    @MainActor
    private func makeController() -> DocumentController {
        let controller = DocumentController()
        controller.textView = NSTextView(frame: .zero)
        return controller
    }

    /// Вставка Markdown-исходника даёт форматированный текст: заголовок
    /// получает styleId Heading1, жирный — bold-трейт шрифта.
    @MainActor
    func testInsertMarkdownTextAppliesFormatting() {
        let controller = makeController()
        let inserted = controller.insertMarkdownText("# Заголовок\n\nОбычный текст и **жирный**.")
        XCTAssertTrue(inserted)
        guard let storage = controller.textView?.textStorage else { return XCTFail("нет storage") }
        XCTAssertEqual(storage.string, "Заголовок\nОбычный текст и жирный.")

        let headingStyle = storage.attribute(.docxEditStyleId, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(headingStyle, "Heading1")

        var boldFound = false
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.bold) {
                boldFound = true; stop.pointee = true
            }
        }
        XCTAssertTrue(boldFound, "жирный-ран не найден")
    }

    /// Мусорный текст не вставляется умным путём (эвристика отрицательна).
    @MainActor
    func testTrySmartPasteRejectsPlainText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Совершенно обычный текст без разметки, длиннее восьми символов.",
                                       forType: .string)
        let controller = makeController()
        XCTAssertFalse(controller.trySmartMarkdownPaste())
    }

    /// Похожий на Markdown текст вставляется умным путём одним шагом.
    @MainActor
    func testTrySmartPasteAcceptsMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("### Выводы\n\n- первый\n- второй", forType: .string)
        let controller = makeController()
        XCTAssertTrue(controller.trySmartMarkdownPaste())
        XCTAssertEqual(controller.textView?.textStorage?.string, "Выводы\n• первый\n• второй")
    }
}
