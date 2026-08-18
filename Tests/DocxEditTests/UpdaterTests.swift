//
//  UpdaterTests.swift
//  DocxEditTests (v1.1.0)
//
//  Юнит-тесты Semver-компаратора и SHA256Verifier.
//  UI/сетевые тесты не входят — покрытие через ручную проверку.
//

import XCTest
@testable import DocxEdit

final class UpdaterTests: XCTestCase {

    // MARK: - Semver

    func testSemverEqual() {
        XCTAssertEqual(Semver.compare("1.0.0", "1.0.0"), 0)
        XCTAssertEqual(Semver.compare("v1.0.0", "1.0.0"), 0)
        XCTAssertEqual(Semver.compare("1.0.0", "v1.0.0"), 0)
    }

    func testSemverNewer() {
        XCTAssertGreaterThan(Semver.compare("1.0.1", "1.0.0"), 0)
        XCTAssertGreaterThan(Semver.compare("1.1.0", "1.0.9"), 0)
        XCTAssertGreaterThan(Semver.compare("2.0.0", "1.99.99"), 0)
        XCTAssertGreaterThan(Semver.compare("v1.1.0", "v1.0.0"), 0)
    }

    func testSemverOlder() {
        XCTAssertLessThan(Semver.compare("1.0.0", "1.0.1"), 0)
        XCTAssertLessThan(Semver.compare("1.0.0", "1.1.0"), 0)
        XCTAssertLessThan(Semver.compare("0.9.9", "1.0.0"), 0)
    }

    func testSemverPreReleaseIgnored() {
        // v1 явно игнорирует pre-release суффиксы (задокументированное ограничение).
        XCTAssertEqual(Semver.compare("1.0.0-rc.1", "1.0.0"), 0)
        XCTAssertEqual(Semver.compare("1.0.0-beta.5", "1.0.0"), 0)
    }

    func testSemverShortForms() {
        // Отсутствующие компоненты трактуются как 0.
        XCTAssertGreaterThan(Semver.compare("2", "1.99.99"), 0)
        XCTAssertEqual(Semver.compare("1", "1.0"), 0)
        XCTAssertEqual(Semver.compare("1.0", "1.0.0"), 0)
    }

    func testSemverNormalize() {
        XCTAssertEqual(Semver.normalize("v1.2.3"), "1.2.3")
        XCTAssertEqual(Semver.normalize("1.2.3"), "1.2.3")
        XCTAssertEqual(Semver.normalize("v1.2.3-rc.1"), "1.2.3-rc.1")
    }

    // MARK: - SHA256Verifier — parsing SHA256SUMS

    func testExpectedHashParsesStandardFormat() {
        let sums = """
        abc123def456  DocxEdit-1.1.0.dmg
        deadbeef00  DocxEdit-1.1.0.app.zip
        """
        XCTAssertEqual(SHA256Verifier.expectedHash(for: "DocxEdit-1.1.0.dmg", sumsFileContents: sums), "abc123def456")
        XCTAssertEqual(SHA256Verifier.expectedHash(for: "DocxEdit-1.1.0.app.zip", sumsFileContents: sums), "deadbeef00")
    }

    func testExpectedHashReturnsNilForMissing() {
        let sums = "abc123  DocxEdit-1.0.0.dmg"
        XCTAssertNil(SHA256Verifier.expectedHash(for: "DocxEdit-2.0.0.dmg", sumsFileContents: sums))
    }

    func testExpectedHashHandlesEmpty() {
        XCTAssertNil(SHA256Verifier.expectedHash(for: "any.dmg", sumsFileContents: ""))
    }

    func testExpectedHashLowercase() {
        // shasum(1) выводит lowercase; результат тоже lowercase для сравнения без case-issues.
        let sums = "ABC123DEF  file.dmg"
        XCTAssertEqual(SHA256Verifier.expectedHash(for: "file.dmg", sumsFileContents: sums), "abc123def")
    }

    // MARK: - UpdateCheckFrequency

    func testUpdateFrequencyIntervalNever() {
        XCTAssertNil(UpdateCheckFrequency.never.interval)
    }

    func testUpdateFrequencyIntervalDaily() {
        XCTAssertEqual(UpdateCheckFrequency.daily.interval, 24 * 60 * 60)
    }

    func testUpdateFrequencyIntervalWeekly() {
        XCTAssertEqual(UpdateCheckFrequency.weekly.interval, 7 * 24 * 60 * 60)
    }
}
