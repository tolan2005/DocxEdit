//
//  EncodingEdgeTests.swift
//  DocxCoreTests
//
//  Расширенное покрытие EncodingDetector: edge cases и матрица кодировок.
//

import XCTest
@testable import DocxCore
@testable import EncodingDetector
import Foundation

final class EncodingEdgeTests: XCTestCase {

    // MARK: - Матрица «реальные тексты» × кодировки

    private let russianText = "Съешь ещё этих мягких французских булок, да выпей чаю. " +
        "Привет, мир! Раз, два, три, четыре, пять — вышел зайчик погулять."

    private let englishText = "The quick brown fox jumps over the lazy dog. " +
        "Sphinx of black quartz, judge my vow."

    private let mixedText = "Hello Привет こんにちは 你好"

    // MARK: - UTF-8

    func testUtf8DetectsRussian() {
        let data = russianText.data(using: .utf8)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf8)
    }

    func testUtf8DetectsEnglish() {
        let data = englishText.data(using: .utf8)!
        let enc = EncodingDetector.detect(data: data)
        // Может определиться как ASCII или UTF-8 — оба валидны.
        XCTAssertTrue([TextEncoding.utf8, .ascii].contains(enc), "got \(enc)")
    }

    func testUtf8WithBOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(russianText.data(using: .utf8)!)
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf8BOM)
    }

    func testUtf8Mixed() {
        let data = mixedText.data(using: .utf8)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf8)
    }

    // MARK: - UTF-16

    func testUtf16LEWithBOM() {
        var data = Data([0xFF, 0xFE])
        data.append(russianText.data(using: .utf16LittleEndian)!)
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf16LE)
    }

    func testUtf16BEWithBOM() {
        var data = Data([0xFE, 0xFF])
        data.append(russianText.data(using: .utf16BigEndian)!)
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf16BE)
    }

    // MARK: - Кириллические 8-битки

    func testWindows1251() {
        let data = russianText.data(using: .windowsCP1251)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .windows1251,
                       "CP1251 не должна больше приниматься за UTF-16 без BOM (регрессия v0.1.0)")
    }

    func testWindows1251_ShortText() {
        // Короткий текст — эвристикам сложнее.
        let data = "Привет".data(using: .windowsCP1251)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .windows1251)
    }

    func testKOI8R() {
        // v0.5.1 фикс: KOI8-R раньше stringEncoding был MacCentralEuropean (0x80000204).
        // Foundation.String.data(using:) не принимает произвольный raw encoding, поэтому
        // кодируем через CFString API.
        let cfEnc = CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        // KOI8-R не покрывает em-dash (—) — берём чисто-кириллический текст.
        let koiText = "Привет мир Съешь ещё этих мягких булок"
        let cfStr = koiText as CFString
        guard let cfData = CFStringCreateExternalRepresentation(nil, cfStr, cfEnc, 0) else {
            XCTFail("CFStringCreateExternalRepresentation не смогла закодировать в KOI8-R")
            return
        }
        _ = nsEnc  // подавить unused, оставили для документации
        let data = cfData as Data
        let detected = EncodingDetector.detect(data: data)
        XCTAssertEqual(detected, .koi8r, "KOI8-R не различается от CP1251 (v0.5.1 регрессия)")
    }

    // MARK: - Пустые/крошечные данные

    func testEmptyData() {
        let enc = EncodingDetector.detect(data: Data())
        // Пустое — либо unknown, либо utf8 по умолчанию, не должно ронять.
        XCTAssertTrue([TextEncoding.unknown, .utf8, .ascii].contains(enc), "got \(enc)")
    }

    func testSingleByteAscii() {
        let data = Data("A".utf8)
        let enc = EncodingDetector.detect(data: data)
        XCTAssertTrue([TextEncoding.ascii, .utf8].contains(enc), "got \(enc)")
    }

    // MARK: - Decode/encode round-trip

    func testCP1251RoundTrip() {
        let data = EncodingDetector.encode(russianText, using: .windows1251)
        let back = EncodingDetector.decode(data, using: .windows1251)
        XCTAssertEqual(back, russianText)
    }

    func testUtf8RoundTrip() {
        let data = EncodingDetector.encode(mixedText, using: .utf8)
        let back = EncodingDetector.decode(data, using: .utf8)
        XCTAssertEqual(back, mixedText)
    }

    // MARK: - Ложные срабатывания

    func testPureAsciiNotMisdetectedAsCyrillic() {
        // Английский текст не должен приниматься за CP1251/KOI8-R.
        let data = englishText.data(using: .ascii)!
        let enc = EncodingDetector.detect(data: data)
        XCTAssertFalse([TextEncoding.windows1251, .koi8r, .macCyrillic].contains(enc),
                       "английский принят за кириллицу: \(enc)")
    }

    func testBinaryDataNotCrashDetection() {
        // Случайные байты — детектор не должен падать.
        var data = Data(count: 512)
        for i in 0..<data.count { data[i] = UInt8.random(in: 0...255) }
        let enc = EncodingDetector.detect(data: data)
        XCTAssertNotNil(enc)  // главное — не крашнулось
    }

    // MARK: - Длинные тексты

    func testLongCyrillicUtf8() {
        let long = String(repeating: russianText + " ", count: 500)
        let data = long.data(using: .utf8)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .utf8)
    }

    func testLongCyrillicCP1251() {
        let long = String(repeating: russianText + " ", count: 500)
        let data = long.data(using: .windowsCP1251)!
        XCTAssertEqual(EncodingDetector.detect(data: data), .windows1251)
    }
}
