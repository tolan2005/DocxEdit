import XCTest
import AppKit
@testable import DocxEdit

/// Разовая оффскрин-проверка подсветки Markdown (v1.6.0): рендерит
/// подсвеченный storage в PNG на рабочий стол для глазного контроля.
/// Не snapshot-тест — артефакт пишется в /tmp и проверяется человеком.
final class MarkdownHighlighterRenderCheck: XCTestCase {

    func testRenderHighlightToPng() throws {
        let md = """
        # Заголовок 1
        ## Заголовок 2

        Обычный текст с **жирным**, *курсивом*, ~~зачёркнутым~~ и `кодом`.

        > Цитата: строка первая
        > и вторая

        - маркированный пункт
        1. нумерованный пункт

        [ссылка](https://example.com) и [[ВикиСсылка]]

        ```swift
        let x = 1 // fenced block
        ```

        ---
        """
        let storage = NSTextStorage(string: md)
        let base = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        MarkdownSyntaxHighlighter.highlight(storage, baseFont: base)

        let size = NSSize(width: 560, height: 430)
        let tv = NSTextView(frame: NSRect(origin: .zero, size: size))
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textStorage?.setAttributedString(storage)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        guard let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else {
            return XCTFail("no bitmap")
        }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no png")
        }
        let url = URL(fileURLWithPath: "/tmp/md-highlight-check.png")
        try png.write(to: url)
        print("PNG записан: \(url.path)")
    }
}
