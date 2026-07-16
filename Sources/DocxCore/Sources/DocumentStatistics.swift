//
//  DocumentStatistics.swift
//  DocxCore
//
//  Подсчёт статистики документа (слова, символы, абзацы, страницы).
//

import Foundation

public struct DocumentStatistics: Equatable, Sendable {
    public var characters: Int           // всего символов (с пробелами)
    public var charactersNoSpaces: Int   // без пробелов
    public var words: Int                // количество слов
    public var paragraphs: Int           // количество абзацев
    public var lines: Int                // количество строк
    public var pages: Int                // оценка количества страниц

    public init(
        characters: Int = 0,
        charactersNoSpaces: Int = 0,
        words: Int = 0,
        paragraphs: Int = 0,
        lines: Int = 0,
        pages: Int = 0
    ) {
        self.characters = characters
        self.charactersNoSpaces = charactersNoSpaces
        self.words = words
        self.paragraphs = paragraphs
        self.lines = lines
        self.pages = pages
    }

    public static let empty = DocumentStatistics()

    public var description: String {
        "Слов: \(words), символов: \(characters) (без пробелов: \(charactersNoSpaces)), абзацев: \(paragraphs)"
    }
}

public enum DocumentStatisticsCalculator {

    /// Вычисляет статистику для всего документа.
    public static func calculate(_ document: DocumentModel) -> DocumentStatistics {
        var characters = 0
        var charactersNoSpaces = 0
        var words = 0
        var paragraphs = 0

        for section in document.sections {
            for block in section.blocks {
                if case .paragraph(let p) = block {
                    paragraphs += 1
                    for run in p.runs {
                        let text = run.text
                        characters += text.count
                        charactersNoSpaces += text.filter { !$0.isWhitespace && !$0.isNewline }.count
                        words += countWords(in: text)
                    }
                }
            }
        }
        return DocumentStatistics(
            characters: characters,
            charactersNoSpaces: charactersNoSpaces,
            words: words,
            paragraphs: paragraphs,
            lines: 0,
            pages: 0
        )
    }

    /// Грубый подсчёт слов по правилу: последовательность Unicode-букв/цифр,
    /// разделённая пробелами/знаками пунктуации.
    public static func countWords(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var inWord = false
        for char in text {
            if char.isLetter || char.isNumber {
                if !inWord {
                    inWord = true
                    count += 1
                }
            } else {
                inWord = false
            }
        }
        return count
    }
}
