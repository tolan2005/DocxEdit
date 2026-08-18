//
//  BridgeSnapshotTests.swift
//  Snapshot-тесты рендера DocumentModel через мост в NSAttributedString.
//  Каждый тест рендерит фиксированный документ в PNG на NSTextView и сравнивает
//  с эталоном в __Snapshots__/. При первой сборке эталоны создаются и тест
//  падает с сообщением «recorded snapshot at …» — далее сборки сравнивают.
//
//  Первая запись эталонов: установи isRecording = true, прогони, откати.
//

import XCTest
import AppKit
import SnapshotTesting
@testable import DocxCore
@testable import DocxEdit

final class BridgeSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Установи isRecording = true для перезаписи эталонов; после — вернуть на false.
        // isRecording = true
    }

    // MARK: - Инфраструктура рендера

    /// Рендерит `NSAttributedString` в offscreen-NSTextView фиксированного размера
    /// и возвращает как NSView, готовый к snapshot-сравнению.
    private func render(_ attributed: NSAttributedString, size: CGSize = CGSize(width: 400, height: 300)) -> NSView {
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(attributed)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return textView
    }

    private func snapshotStrategy(_ size: CGSize = CGSize(width: 400, height: 300)) -> Snapshotting<NSView, NSImage> {
        // precision 0.98 — микро-различия в анти-алиасинге между машинами допустимы.
        return .image(perceptualPrecision: 0.98, size: size)
    }

    // MARK: - Простые сцены

    func testPlainTextSnapshot() {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "Snapshot test: plain text",
                    attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18))
            ]))
        ])])
        let view = render(m.toAttributedString())
        assertSnapshot(of: view, as: snapshotStrategy())
    }

    func testBoldItalicUnderlineSnapshot() {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "bold ", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18, bold: true)),
                Run(text: "italic ", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18, italic: true)),
                Run(text: "underline", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18, underline: .single)),
            ]))
        ])])
        let view = render(m.toAttributedString())
        assertSnapshot(of: view, as: snapshotStrategy())
    }

    func testAllUnderlineVariantsSnapshot() {
        // Регрессия v0.5.2: .double/.dotted/.dashed схлопывались в .single.
        // Snapshot гарантирует, что 4 варианта визуально различны.
        let font = "Helvetica"
        let size: CGFloat = 20
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "single\n", attributes: CharacterAttributes(fontName: font, fontSize: size, underline: .single)),
            ])),
            .paragraph(Paragraph(runs: [
                Run(text: "double\n", attributes: CharacterAttributes(fontName: font, fontSize: size, underline: .double)),
            ])),
            .paragraph(Paragraph(runs: [
                Run(text: "dotted\n", attributes: CharacterAttributes(fontName: font, fontSize: size, underline: .dotted)),
            ])),
            .paragraph(Paragraph(runs: [
                Run(text: "dashed", attributes: CharacterAttributes(fontName: font, fontSize: size, underline: .dashed)),
            ])),
        ])])
        let view = render(m.toAttributedString(), size: CGSize(width: 400, height: 200))
        assertSnapshot(of: view, as: snapshotStrategy(CGSize(width: 400, height: 200)))
    }

    func testAlignmentSnapshot() {
        let mk: (String, DocxCore.TextAlignment) -> Block = { text, a in
            var p = ParagraphAttributes(); p.alignment = a
            return .paragraph(Paragraph(runs: [
                Run(text: text, attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 16))
            ], attributes: p))
        }
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            mk("Left aligned line", .left),
            mk("Center aligned line", .center),
            mk("Right aligned line", .right),
        ])])
        let view = render(m.toAttributedString(), size: CGSize(width: 500, height: 150))
        assertSnapshot(of: view, as: snapshotStrategy(CGSize(width: 500, height: 150)))
    }

    func testColoredTextSnapshot() {
        // Регрессия v0.5.2: цвета дрейфовали (#FF0000 → #FF2600).
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "red ", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18,
                    textColor: CodableColor.fromHex("#FF0000")!)),
                Run(text: "green ", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18,
                    textColor: CodableColor.fromHex("#00CC00")!)),
                Run(text: "blue", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18,
                    textColor: CodableColor.fromHex("#0000FF")!)),
            ]))
        ])])
        let view = render(m.toAttributedString())
        assertSnapshot(of: view, as: snapshotStrategy())
    }

    func testHighlightedTextSnapshot() {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "plain ", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18)),
                Run(text: "HIGHLIGHTED", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18,
                    highlightColor: CodableColor.fromHex("#FFFF00")!)),
                Run(text: " tail", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 18)),
            ]))
        ])])
        let view = render(m.toAttributedString())
        assertSnapshot(of: view, as: snapshotStrategy())
    }

    func testSubSuperscriptSnapshot() {
        let m = DocumentModel(sections: [DocumentSection(blocks: [
            .paragraph(Paragraph(runs: [
                Run(text: "H", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 24)),
                Run(text: "2", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 24, subscript: true)),
                Run(text: "O + E = mc", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 24)),
                Run(text: "2", attributes: CharacterAttributes(fontName: "Helvetica", fontSize: 24, superscript: true)),
            ]))
        ])])
        let view = render(m.toAttributedString(), size: CGSize(width: 400, height: 100))
        assertSnapshot(of: view, as: snapshotStrategy(CGSize(width: 400, height: 100)))
    }
}
