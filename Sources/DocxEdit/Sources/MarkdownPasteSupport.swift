import Foundation

/// v1.6.6: умная вставка Markdown из буфера (Typora-поведение).
/// Кнопка «копировать» в ИИ-чатах (ChatGPT/Perplexity) кладёт в буфер
/// исходник Markdown как plain text; здесь решаем, похож ли текст на
/// Markdown, и чистим типовые артефакты чатов до парсинга.
enum MarkdownPasteSupport {

    // MARK: - Санитайзер

    /// Чистит типовые артефакты копирования из ИИ-чатов:
    /// - zero-width символы (\u{200B}/\u{200C}/\u{FEFF});
    /// - пробел перед закрывающим разделителем начертаний
    ///   (`**текст **` → `**текст**`, `***текст ***` → `***текст***`,
    ///   `*текст *` → `*текст*`) — CommonMark не закрывает выделение,
    ///   если перед разделителем пробел, и звёздочки остаются буквами.
    static func sanitize(_ source: String) -> String {
        var text = source
        for ch in ["\u{200B}", "\u{200C}", "\u{FEFF}"] {
            text = text.replacingOccurrences(of: ch, with: "")
        }
        // Тройные (жирный курсив) — раньше двойных/одинарных, чтобы не оставить хвостов.
        text = text.replacingOccurrences(
            of: "\\*\\*\\*([^*\n]+?)\\s+\\*\\*\\*",
            with: "***$1***", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "\\*\\*([^*\n]+?)\\s+\\*\\*",
            with: "**$1**", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "(?<!\\*)\\*([^*\n]+?)\\s+\\*(?!\\*)",
            with: "*$1*", options: .regularExpression)
        return text
    }

    // MARK: - Эвристика

    /// Похож ли plain-text на Markdown-исходник. Консервативно: обычный
    /// абзац с одной случайной звёздочкой не должен триггерить конвертацию.
    static func looksLikeMarkdown(_ raw: String) -> Bool {
        let text = sanitize(raw)
        guard text.count >= 8 else { return false }

        var score = 0
        var lines = 0
        var markedLines = 0

        enum Regexes {
            static let heading = try! NSRegularExpression(pattern: "^#{1,6}\\s+\\S")
            static let bullet = try! NSRegularExpression(pattern: "^\\s*[-*+]\\s+\\S")
            static let ordered = try! NSRegularExpression(pattern: "^\\s*\\d+[.)]\\s+\\S")
            static let quote = try! NSRegularExpression(pattern: "^\\s*>\\s")
            static let hr = try! NSRegularExpression(pattern: "^(---+|\\*\\*\\*+|___+)\\s*$")
            static let tableRow = try! NSRegularExpression(pattern: "^\\s*\\|.+.\\|\\s*$")
            static let tableSeparator = try! NSRegularExpression(pattern: "^\\s*\\|?[\\s:-]*-{3,}[\\s:|-]*$")
            static let fence = try! NSRegularExpression(pattern: "^```|^~~~")
            static let bold = try! NSRegularExpression(pattern: "\\*\\*[^*\n]{2,}?\\*\\*")
            static let italic = try! NSRegularExpression(pattern: "(?<!\\*)\\*[^*\n]{2,}?\\*(?!\\*)")
            static let code = try! NSRegularExpression(pattern: "`[^`\n]+`")
            static let link = try! NSRegularExpression(pattern: "\\[[^]\n]+\\]\\([^)\n]+\\)")
        }

        func count(_ regex: NSRegularExpression, in line: String) -> Int {
            regex.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line))
        }

        for line in text.components(separatedBy: .newlines) {
            lines += 1
            var lineMarked = false
            if count(Regexes.heading, in: line) > 0 { score += 2; lineMarked = true }
            if count(Regexes.bullet, in: line) > 0 { score += 1; lineMarked = true }
            if count(Regexes.ordered, in: line) > 0 { score += 1; lineMarked = true }
            if count(Regexes.quote, in: line) > 0 { score += 1; lineMarked = true }
            if count(Regexes.hr, in: line) > 0 { score += 2; lineMarked = true }
            if count(Regexes.tableSeparator, in: line) > 0 && line.contains("|") {
                score += 3; lineMarked = true
            } else if count(Regexes.tableRow, in: line) > 0 {
                score += 1; lineMarked = true
            }
            if count(Regexes.fence, in: line) > 0 { score += 3; lineMarked = true }
            let inline = count(Regexes.bold, in: line) * 1
                + count(Regexes.italic, in: line) * 1
                + count(Regexes.code, in: line) * 1
                + count(Regexes.link, in: line) * 2
            if inline > 0 { score += min(inline, 4); lineMarked = true }
            if lineMarked { markedLines += 1 }
        }
        guard lines > 0 else { return false }
        let density = Double(markedLines) / Double(lines)
        // Порог 4: одинокий «### Заголовок» или пара буллитов из чата
        // тоже заслуживают конвертации; случайная звёздочка в тексте (score ≤ 2) — нет.
        return score >= 4 && density >= 0.25
    }
}
