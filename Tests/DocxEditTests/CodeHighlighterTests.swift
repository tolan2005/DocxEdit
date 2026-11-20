import XCTest
import AppKit
@testable import DocxEdit

final class CodeHighlighterTests: XCTestCase {
    private func color(_ s: NSTextStorage, _ needle: String) -> NSColor? {
        let r = (s.string as NSString).range(of: needle)
        return s.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor
    }

    func testSwiftBlockSourceMode() {
        let md = "Текст if\n```swift\nlet url = \"http://x\" // коммент\nreturn 42\n```\n"
        let s = NSTextStorage(string: md)
        MarkdownSyntaxHighlighter.highlight(s, baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular))
        XCTAssertEqual(color(s, "let"), CodeHighlighter.keywordColor)
        XCTAssertEqual(color(s, "http"), CodeHighlighter.stringColor)   // «//» в строке — не комментарий
        XCTAssertEqual(color(s, "// коммент"), CodeHighlighter.commentColor)
        XCTAssertEqual(color(s, "42"), CodeHighlighter.numberColor)
        XCTAssertNotEqual(color(s, "if"), CodeHighlighter.keywordColor) // вне блока не трогаем
        XCTAssertEqual(s.string, md)
    }

    func testHybridAndUnknownLanguage() {
        let md = "```python\ndef f(): # c\n```\n\n```\ndef g\n```\n"
        let s = NSTextStorage(string: md)
        MarkdownHybridRenderer.render(s, baseFont: .systemFont(ofSize: 14), active: NSRange(location: md.utf16.count, length: 0))
        XCTAssertEqual(color(s, "def f"), CodeHighlighter.keywordColor)
        XCTAssertEqual(color(s, "# c"), CodeHighlighter.commentColor)
        XCTAssertNotEqual(color(s, "def g"), CodeHighlighter.keywordColor)
        XCTAssertEqual(s.string, md)
    }
}
