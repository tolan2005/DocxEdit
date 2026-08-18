//
//  EncodingDetector.swift
//  EncodingDetector
//
//  Минимальная реализация определения кодировки текстовых файлов (TXT).
//  Используется DocxEdit R01 (MVP) для открытия .txt в разных кодировках.
//

import Foundation
import DocxCore

public struct TextEncoding: Equatable, Sendable, Hashable {
    public let stringEncoding: String.Encoding
    public let name: String
    public let displayName: String
    public let hasBOM: Bool

    public init(stringEncoding: String.Encoding, name: String, displayName: String, hasBOM: Bool = false) {
        self.stringEncoding = stringEncoding
        self.name = name
        self.displayName = displayName
        self.hasBOM = hasBOM
    }

    public static let utf8 = TextEncoding(
        stringEncoding: .utf8, name: "utf-8", displayName: "UTF-8"
    )
    public static let utf8BOM = TextEncoding(
        stringEncoding: .utf8, name: "utf-8-bom", displayName: "UTF-8 (с BOM)", hasBOM: true
    )
    public static let utf16LE = TextEncoding(
        stringEncoding: .utf16LittleEndian, name: "utf-16le", displayName: "UTF-16 LE"
    )
    public static let utf16BE = TextEncoding(
        stringEncoding: .utf16BigEndian, name: "utf-16be", displayName: "UTF-16 BE"
    )
    public static let windows1251 = TextEncoding(
        stringEncoding: .windowsCP1251, name: "windows-1251", displayName: "Windows-1251 (Кириллица)"
    )
    // v0.5.1 (2026-07-13): исправлены сырые raw-коды. Найдено юнит-тестом.
    // Раньше `.koi8r` был замаплен на 0x80000204 (это MacCentralEuropean/ISO Latin 4,
    // а не KOI8-R). Аналогично `.macCyrillic = 0x07` — это UTF-32BE.
    // Правильный путь — CFStringEncodings → NSStringEncoding через CFStringConvert.
    public static let koi8r = TextEncoding(
        stringEncoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0A02)),
        name: "koi8-r", displayName: "KOI8-R (Кириллица)"
    )
    public static let macCyrillic = TextEncoding(
        stringEncoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x07)),
        name: "x-mac-cyrillic", displayName: "Mac Cyrillic"
    )
    public static let ascii = TextEncoding(
        stringEncoding: .ascii, name: "ascii", displayName: "ASCII"
    )
    public static let unknown = TextEncoding(
        stringEncoding: .utf8, name: "unknown", displayName: "Неизвестно"
    )
}

public enum EncodingDetector {

    /// Определяет кодировку по содержимому `Data`.
    public static func detect(data: Data) -> TextEncoding {
        // 1. BOM — самый приоритетный признак.
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return .utf8BOM
        }
        if data.count >= 2 {
            if data[0] == 0xFF && data[1] == 0xFE { return .utf16LE }
            if data[0] == 0xFE && data[1] == 0xFF { return .utf16BE }
        }

        // 2. Пробуем декодировать как UTF-8.
        if let s = String(data: data, encoding: .utf8), !s.contains("\u{FFFD}") {
            return .utf8
        }

        // 3. Кириллические 8-битные кодировки — ДО UTF-16 без BOM.
        // Найден тестом 2026-07-13 (баг с v0.1.0): CP1251-текст "Привет, мир!"
        // (12 байт, все ≥0x20) проходил эвристику UTF-16LE в decodeAsUtf16WithoutBOM
        // и возвращался как UTF-16, порождая мусор. Кириллические проверки
        // строже (доля кириллических букв > 30%), поэтому CP1251/KOI8-R
        // определяются однозначно, а UTF-16 без BOM остаётся как fallback.
        // v0.5.1: комбинированный score для CP1251 vs KOI8-R.
        // На коротком кириллическом тексте `cyrillicRatio` часто = 1.0 для
        // обеих кодировок (оба размещают кириллицу в high-байтах), поэтому
        // добавляем «чистоту декодирования» — долю осмысленных символов
        // (буквы+цифры+пробел+пунктуация). У «неправильного» декода
        // появляется мусор вроде '×' (0x00D7 при cp1251-декоде KOI8-R-байт).
        let cp1251Total = combinedScore(data: data, encoding: .windowsCP1251)
        let koi8Enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0A02))
        let koi8rTotal = combinedScore(data: data, encoding: koi8Enc)
        // Порог 0.05: правильный кириллический декод даёт combined ≈ 0.3
        // (cyrillicRatio ≈ 1.0 × purity ≈ 1.0 × vowelRatio ≈ 0.33); мусорный
        // — около 0.1, но заведомо больше нуля. Разрыв решает.
        if cp1251Total > 0.05 || koi8rTotal > 0.05 {
            return koi8rTotal > cp1251Total ? .koi8r : .windows1251
        }

        // 4. Пробуем UTF-16 без BOM по эвристике.
        if let s = decodeAsUtf16WithoutBOM(data: data) {
            return s
        }

        // 5. ASCII.
        if isAscii(data: data) {
            return .ascii
        }

        return .unknown
    }

    public static func detect(url: URL) throws -> TextEncoding {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentError.ioError(
                "Не удалось прочитать файл: \(error.localizedDescription)"
            )
        }
        return detect(data: data)
    }

    public static func decode(_ data: Data, using encoding: TextEncoding) -> String {
        if encoding == .utf8BOM && data.count >= 3 {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }
        if encoding == .utf16LE || encoding == .utf16BE {
            return String(data: data, encoding: encoding.stringEncoding) ?? ""
        }
        return String(data: data, encoding: encoding.stringEncoding) ?? ""
    }

    public static func encode(_ string: String, using encoding: TextEncoding) -> Data {
        if encoding == .utf8BOM {
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(string.data(using: .utf8) ?? Data())
            return data
        }
        return string.data(using: encoding.stringEncoding) ?? Data()
    }

    // MARK: - Эвристики

    private static func isCyrillic(data: Data, encoding: String.Encoding) -> Bool {
        cyrillicRatio(data: data, encoding: encoding) > 0.3
    }

    /// v0.5.1: комбинированный score — кириллица × чистота × «нормальность».
    /// «Чистота» = доля осмысленных символов (буквы/цифры/пробел/пунктуация).
    /// «Нормальность» = доля гласных среди кириллических букв. В русском
    /// тексте гласные (а-у-и-е-ё-о-ы-э-ю-я) занимают ~30-45%, в мусоре
    /// (декоде «не той» кодировки — вроде "рТЙЧЕФ" при чтении KOI8-R как
    /// CP1251) — обычно <20%. Разница решающая при коротких кириллических
    /// строках, где cyrillicRatio+purity одинаковые у обоих декодов.
    private static func combinedScore(data: Data, encoding: String.Encoding) -> Double {
        guard let s = String(data: data.prefix(8192), encoding: encoding) else { return 0 }
        if s.isEmpty { return 0 }
        let vowels: Set<Character> = ["а","е","ё","и","о","у","ы","э","ю","я",
                                       "А","Е","Ё","И","О","У","Ы","Э","Ю","Я"]
        var cyrillicCount = 0
        var vowelCount = 0
        var totalLetters = 0
        var goodChars = 0
        var totalChars = 0
        for c in s {
            totalChars += 1
            if c.isLetter {
                totalLetters += 1
                goodChars += 1
                if (0x0400...0x04FF).contains(c.unicodeScalars.first?.value ?? 0) {
                    cyrillicCount += 1
                    if vowels.contains(c) { vowelCount += 1 }
                }
            } else if c.isNumber || c.isWhitespace || c.isPunctuation {
                goodChars += 1
            }
        }
        let cyrillicRatio = totalLetters > 0 ? Double(cyrillicCount) / Double(totalLetters) : 0
        let purity = Double(goodChars) / Double(totalChars)
        let normality = cyrillicCount > 0 ? Double(vowelCount) / Double(cyrillicCount) : 0
        return cyrillicRatio * purity * normality
    }

    /// v0.5.1: доля кириллических букв — от 0 до 1. Оставлена для isCyrillic
    /// (обратная совместимость), но detect() использует combinedScore.
    private static func cyrillicRatio(data: Data, encoding: String.Encoding) -> Double {
        guard let s = String(data: data.prefix(8192), encoding: encoding) else { return 0 }
        if s.isEmpty { return 0 }
        var cyrillicCount = 0
        var letterCount = 0
        for c in s {
            if c.isLetter {
                letterCount += 1
                if (0x0400...0x04FF).contains(c.unicodeScalars.first?.value ?? 0) {
                    cyrillicCount += 1
                }
            }
        }
        return letterCount > 0 ? Double(cyrillicCount) / Double(letterCount) : 0
    }

    private static func isAscii(data: Data) -> Bool {
        for byte in data.prefix(8192) {
            if byte > 0x7E && byte != 0x0A && byte != 0x0D && byte != 0x09 { return false }
        }
        return true
    }

    private static func decodeAsUtf16WithoutBOM(data: Data) -> TextEncoding? {
        if data.count < 2 || data.count % 2 != 0 { return nil }
        // Попытка LE
        if let s = String(data: data, encoding: .utf16LittleEndian) {
            if !s.contains("\u{FFFD}") && s.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x0A || $0.value == 0x0D || $0.value == 0x09 }) {
                return .utf16LE
            }
        }
        // Попытка BE
        if let s = String(data: data, encoding: .utf16BigEndian) {
            if !s.contains("\u{FFFD}") && s.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x0A || $0.value == 0x0D || $0.value == 0x09 }) {
                return .utf16BE
            }
        }
        return nil
    }
}
