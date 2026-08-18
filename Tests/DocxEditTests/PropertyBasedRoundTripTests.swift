//
//  PropertyBasedRoundTripTests.swift
//  DocxEditTests
//
//  Property-based тесты: генератор случайных DocumentModel → round-trip через
//  мост (DocumentModel → NSAttributedString → DocumentModel) должен сохранять
//  наблюдаемые свойства. Стохастические тесты ловят комбинаторные баги, которые
//  пропускают вручную выписанные примеры.
//
//  Без SwiftCheck — свой мини-генератор с фиксированным seed для воспроизводимости.
//

import XCTest
import AppKit
@testable import DocxCore
@testable import DocxEdit

final class PropertyBasedRoundTripTests: XCTestCase {

    // Простой seedable PRNG — SystemRandomNumberGenerator не сидируется.
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    // MARK: - Генератор

    private func randomCharacterAttrs(_ rng: inout SeededRNG) -> CharacterAttributes {
        CharacterAttributes(
            fontName: Bool.random(using: &rng) ? "Helvetica" : nil,
            fontSize: Bool.random(using: &rng) ? CGFloat(Int.random(in: 8...48, using: &rng)) : nil,
            bold: Bool.random(using: &rng),
            italic: Bool.random(using: &rng),
            underline: [.none, .single, .double, .dotted, .dashed].randomElement(using: &rng)!,
            strikethrough: Bool.random(using: &rng),
            textColor: Bool.random(using: &rng) ? randomColor(&rng) : nil,
            highlightColor: Bool.random(using: &rng) ? randomColor(&rng) : nil,
            superscript: false,   // superscript+subscript исключают друг друга — генерируем отдельно
            subscript: false
        )
    }

    private func randomColor(_ rng: inout SeededRNG) -> CodableColor {
        // Круглые 51-е доли — избегаем rounding-drift в hex round-trip.
        // 0, 51, 102, 153, 204, 255 → 0, 0.2, 0.4, 0.6, 0.8, 1.0
        let vals: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1.0]
        return CodableColor(
            red: vals.randomElement(using: &rng)!,
            green: vals.randomElement(using: &rng)!,
            blue: vals.randomElement(using: &rng)!
        )
    }

    private func randomParagraph(_ rng: inout SeededRNG) -> Paragraph {
        let numRuns = Int.random(in: 1...3, using: &rng)
        let runs = (0..<numRuns).map { i in
            Run(text: "text\(i) ", attributes: randomCharacterAttrs(&rng))
        }
        var attrs = ParagraphAttributes()
        attrs.alignment = [.left, .center, .right, .justify].randomElement(using: &rng)!
        return Paragraph(runs: runs, attributes: attrs)
    }

    private func randomDocument(_ rng: inout SeededRNG, paragraphs: Int) -> DocumentModel {
        let blocks: [Block] = (0..<paragraphs).map { _ in
            .paragraph(randomParagraph(&rng))
        }
        return DocumentModel(sections: [DocumentSection(blocks: blocks)])
    }

    // MARK: - Property: полный текст сохраняется

    func testPropertyTextPreservedAcrossRoundTrip() {
        var rng = SeededRNG(state: 0xC0DE_C0DE)
        for iter in 0..<50 {
            let m = randomDocument(&rng, paragraphs: Int.random(in: 1...5, using: &rng))
            let originalText = allText(m)
            let back = DocumentModel.from(attributed: m.toAttributedString())
            let backText = allText(back)
            XCTAssertEqual(originalText, backText,
                           "iter=\(iter): текст не совпал\noriginal=\(originalText.debugDescription)\nback=\(backText.debugDescription)")
        }
    }

    // MARK: - Property: bold/italic/underline присутствие сохраняется на уровне документа

    func testPropertyFormattingFlagsPreserved() {
        var rng = SeededRNG(state: 0xBEEF_BEEF)
        for iter in 0..<50 {
            let m = randomDocument(&rng, paragraphs: 3)
            let back = DocumentModel.from(attributed: m.toAttributedString())

            let origBold = anyRun(m) { $0.attributes.bold }
            let backBold = anyRun(back) { $0.attributes.bold }
            XCTAssertEqual(origBold, backBold, "iter=\(iter): bold пропал")

            let origItalic = anyRun(m) { $0.attributes.italic }
            let backItalic = anyRun(back) { $0.attributes.italic }
            XCTAssertEqual(origItalic, backItalic, "iter=\(iter): italic пропал")

            let origStrike = anyRun(m) { $0.attributes.strikethrough }
            let backStrike = anyRun(back) { $0.attributes.strikethrough }
            XCTAssertEqual(origStrike, backStrike, "iter=\(iter): strike пропал")
        }
    }

    // MARK: - Property: количество параграфов сохраняется

    func testPropertyParagraphCountPreserved() {
        var rng = SeededRNG(state: 0xABCD_1234)
        for iter in 0..<30 {
            let n = Int.random(in: 1...10, using: &rng)
            let m = randomDocument(&rng, paragraphs: n)
            let back = DocumentModel.from(attributed: m.toAttributedString())
            let backCount = back.sections.flatMap { $0.blocks }.filter {
                if case .paragraph = $0 { return true } else { return false }
            }.count
            XCTAssertEqual(backCount, n, "iter=\(iter): число параграфов")
        }
    }

    // MARK: - Property: идемпотентность (round-trip дважды == round-trip один раз)

    func testPropertyIdempotence() {
        var rng = SeededRNG(state: 0xDEAD_BEEF)
        for iter in 0..<20 {
            let m = randomDocument(&rng, paragraphs: 3)
            let once = DocumentModel.from(attributed: m.toAttributedString())
            let twice = DocumentModel.from(attributed: once.toAttributedString())
            XCTAssertEqual(allText(once), allText(twice), "iter=\(iter): не идемпотентно")
        }
    }

    // MARK: - Helpers

    private func allText(_ m: DocumentModel) -> String {
        m.sections.flatMap { $0.blocks }.compactMap {
            if case let .paragraph(p) = $0 {
                return p.runs.map(\.text).joined()
            } else { return nil }
        }.joined(separator: "\n")
    }

    private func anyRun(_ m: DocumentModel, _ pred: (Run) -> Bool) -> Bool {
        m.sections.flatMap { $0.blocks }.contains { block in
            if case let .paragraph(p) = block {
                return p.runs.contains(where: pred)
            }
            return false
        }
    }
}
