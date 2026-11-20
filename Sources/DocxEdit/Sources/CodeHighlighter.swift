//
//  CodeHighlighter.swift
//  DocxEdit
//
//  Подсветка синтаксиса в блоках кода Markdown (```язык). Regex-правила,
//  без разбора кода. Меняются только цвета, текст не трогается.
//

import AppKit

enum CodeHighlighter {
    struct Language {
        let keywords: Set<String>
        let lineComment: String?      // regex начала однострочного комментария
        let blockComment: Bool        // /* … */
        let tripleQuotes: Bool        // """ … """
    }

    static let keywordColor = NSColor.systemPink
    static let stringColor = NSColor.systemRed
    static let commentColor = NSColor.systemGreen
    static let numberColor = NSColor.systemBlue

    private static let cLike = ["if", "else", "for", "while", "do", "return", "break", "continue",
                                "switch", "case", "default", "true", "false", "null", "new", "class",
                                "try", "catch", "throw", "import", "in"]

    static let languages: [String: Language] = {
        let swift = Language(keywords: Set(cLike + ["func", "let", "var", "struct", "enum", "protocol",
            "extension", "guard", "nil", "self", "Self", "static", "private", "public", "internal",
            "fileprivate", "init", "deinit", "where", "as", "is", "async", "await", "throws", "rethrows",
            "some", "any", "inout", "override", "final", "mutating", "defer", "repeat", "typealias"]),
            lineComment: "//", blockComment: true, tripleQuotes: true)
        let python = Language(keywords: ["def", "class", "return", "if", "elif", "else", "for", "while",
            "in", "not", "and", "or", "is", "None", "True", "False", "import", "from", "as", "with",
            "try", "except", "finally", "raise", "lambda", "yield", "pass", "break", "continue",
            "global", "nonlocal", "async", "await", "del", "assert"],
            lineComment: "#", blockComment: false, tripleQuotes: true)
        let js = Language(keywords: Set(cLike + ["function", "const", "let", "var", "this", "undefined",
            "typeof", "instanceof", "export", "from", "async", "await", "yield", "extends", "super",
            "interface", "type", "implements", "of", "finally", "delete", "void", "static",
            "public", "private", "readonly", "enum", "as"]),
            lineComment: "//", blockComment: true, tripleQuotes: false)
        let json = Language(keywords: ["true", "false", "null"],
            lineComment: nil, blockComment: false, tripleQuotes: false)
        let bash = Language(keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
            "case", "esac", "in", "function", "return", "export", "local", "echo", "exit", "cd", "set"],
            lineComment: "#", blockComment: false, tripleQuotes: false)
        let yaml = Language(keywords: ["true", "false", "null", "yes", "no"],
            lineComment: "#", blockComment: false, tripleQuotes: false)
        let sql = Language(keywords: Set(["select", "from", "where", "and", "or", "not", "insert", "into",
            "values", "update", "set", "delete", "create", "table", "drop", "alter", "join", "left",
            "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "as", "null",
            "is", "in", "distinct", "union", "primary", "key", "index", "asc", "desc", "count"]
            .flatMap { [$0, $0.uppercased()] }),
            lineComment: "--", blockComment: true, tripleQuotes: false)
        return ["swift": swift, "python": python, "py": python,
                "js": js, "javascript": js, "ts": js, "typescript": js, "jsx": js, "tsx": js,
                "json": json, "bash": bash, "sh": bash, "shell": bash, "zsh": bash,
                "yaml": yaml, "yml": yaml, "sql": sql]
    }()

    /// Язык из строки-открытия блока: «```swift» → swift.
    static func language(fromFence fence: String) -> Language? {
        let tag = fence.drop(while: { $0 == "`" }).trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "{" }).first.map { $0.lowercased() } ?? ""
        return languages[tag]
    }

    /// Раскрашивает `body` (содержимое блока без строк ```).
    static func highlight(_ storage: NSTextStorage, body: NSRange, language lang: Language) {
        guard body.length > 0 else { return }
        let text = storage.string
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: body)
        func each(_ pattern: String, _ f: (NSTextCheckingResult) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            re.enumerateMatches(in: text, range: body) { m, _, _ in if let m { f(m) } }
        }
        each(#"\b\d+(?:\.\d+)?\b"#) { storage.addAttribute(.foregroundColor, value: numberColor, range: $0.range) }
        each(#"\b[A-Za-z_]\w*\b"#) { m in
            if lang.keywords.contains((text as NSString).substring(with: m.range)) {
                storage.addAttribute(.foregroundColor, value: keywordColor, range: m.range)
            }
        }
        // Строки и комментарии — одним проходом: что началось раньше, то и действует
        // («//» внутри строки не комментарий, кавычка в комментарии не строка).
        var alts: [String] = []
        if lang.blockComment { alts.append(#"(?<c1>/\*[\s\S]*?(?:\*/|\z))"#) }
        if let lc = lang.lineComment { alts.append("(?<c2>\(NSRegularExpression.escapedPattern(for: lc)).*)") }
        if lang.tripleQuotes { alts.append(#"(?<s1>"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z))"#) }
        let commentGroups = (lang.blockComment ? ["c1"] : []) + (lang.lineComment != nil ? ["c2"] : [])
        alts.append(#"(?<s2>"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?|`(?:\\.|[^`\\])*`?)"#)
        each(alts.joined(separator: "|")) { m in
            let isComment = commentGroups.contains { m.range(withName: $0).location != NSNotFound }
            storage.addAttribute(.foregroundColor, value: isComment ? commentColor : stringColor, range: m.range)
        }
    }

    /// Все блоки ```язык в тексте: раскрашивает содержимое известных языков.
    static func highlightFences(_ storage: NSTextStorage) {
        let text = storage.string
        guard let re = try? NSRegularExpression(pattern: #"(?ms)^(```[^\n]*)\n(.*?)^```[ \t]*$"#) else { return }
        for m in re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            guard let lang = language(fromFence: (text as NSString).substring(with: m.range(at: 1))) else { continue }
            highlight(storage, body: m.range(at: 2), language: lang)
        }
    }
}
