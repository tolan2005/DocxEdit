import XCTest
@testable import DocxEdit

/// v1.10.5: позиция курсора по файлу.
final class CaretMemoryTests: XCTestCase {
    func testRemembersLatestPositionPerFileWithLimit() throws {
        let suite = "CaretMemoryTests-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let a = URL(fileURLWithPath: "/tmp/a b.md"), b = URL(fileURLWithPath: "/tmp/b.docx")
        XCTAssertNil(CaretMemory.location(for: a, defaults: d))
        CaretMemory.remember(a, 10, defaults: d)
        CaretMemory.remember(b, 7, defaults: d)
        CaretMemory.remember(a, 42, defaults: d)
        XCTAssertEqual(CaretMemory.location(for: a, defaults: d), 42)
        XCTAssertEqual(CaretMemory.location(for: b, defaults: d), 7)
        XCTAssertEqual(d.stringArray(forKey: CaretMemory.key)?.count, 2)
        for i in 0..<60 { CaretMemory.remember(URL(fileURLWithPath: "/tmp/f\(i).md"), i, defaults: d) }
        XCTAssertEqual(d.stringArray(forKey: CaretMemory.key)?.count, CaretMemory.limit)
        XCTAssertNil(CaretMemory.location(for: a, defaults: d))   // вытеснен
    }
}
