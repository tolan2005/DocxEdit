import XCTest
import ZIPFoundation
@testable import DocxIO

/// Диагностика: что теряется при «открыть → сохранить без правок» на реальных .docx.
/// Только печатает; включается переменной окружения DOCX_RT_OUT (папка для копий).
final class RoundTripLossDiagnostics: XCTestCase {
    func testPrintLosses() throws {
        guard let out = ProcessInfo.processInfo.environment["DOCX_RT_OUT"] else { throw XCTSkip("DOCX_RT_OUT не задан") }
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".docx") {
            let src = dir.appendingPathComponent(name)
            let saved = URL(fileURLWithPath: out).appendingPathComponent("rt-" + name)
            try DocxIO.exportDocx(try DocxIO.importDocx(url: src), to: saved)
            let a = try parts(src), b = try parts(saved)
            print("=== \(name)")
            print("  потеряны части:", a.keys.filter { b[$0] == nil }.sorted())
            if let x = a["word/document.xml"], let y = b["word/document.xml"] {
                let ta = tags(x), tb = tags(y)
                let lost = ta.filter { tb[$0.key, default: 0] < $0.value }
                    .map { "\($0.key) \($0.value)→\(tb[$0.key, default: 0])" }.sorted()
                print("  document.xml, меньше элементов:", lost)
            }
        }
    }

    private func parts(_ url: URL) throws -> [String: Data] {
        let archive = try Archive(url: url, accessMode: .read)
        var out: [String: Data] = [:]
        for entry in archive where entry.type == .file {
            var data = Data(); _ = try archive.extract(entry) { data.append($0) }
            out[entry.path] = data
        }
        return out
    }

    private func tags(_ xml: Data) -> [String: Int] {
        let s = String(decoding: xml, as: UTF8.self)
        let re = try! NSRegularExpression(pattern: #"<([a-zA-Z0-9]+:[a-zA-Z0-9]+)[\s/>]"#)
        var counts: [String: Int] = [:]
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            counts[(s as NSString).substring(with: m.range(at: 1)), default: 0] += 1
        }
        return counts
    }
}
