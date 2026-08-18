//
//  MdModeTests.swift
//  DocxEditTests
//
//  v1.4.0 (ADR-049): режим документа DOCX/Markdown — маппинг расширений,
//  параметры сохранения по умолчанию, настройка новых документов.
//

import XCTest
@testable import DocxEdit

final class MdModeTests: XCTestCase {

    // MARK: - Расширение → режим

    func testModeFromUrl_MarkdownExtensions() {
        XCTAssertEqual(DocumentMode.from(url: URL(fileURLWithPath: "/tmp/a.md")), .markdown)
        XCTAssertEqual(DocumentMode.from(url: URL(fileURLWithPath: "/tmp/a.markdown")), .markdown)
        XCTAssertEqual(DocumentMode.from(url: URL(fileURLWithPath: "/tmp/a.MD")), .markdown)
    }

    func testModeFromUrl_OtherExtensionsAreDocx() {
        for ext in ["docx", "doc", "rtf", "odt", "txt", ""] {
            let url = URL(fileURLWithPath: "/tmp/a.\(ext)")
            XCTAssertEqual(DocumentMode.from(url: url), .docx, "расширение \(ext)")
        }
    }

    // MARK: - Параметры сохранения

    func testSaveExtension() {
        XCTAssertEqual(DocumentMode.docx.saveExtension, "docx")
        XCTAssertEqual(DocumentMode.markdown.saveExtension, "md")
    }

    func testDefaultSaveName() {
        XCTAssertEqual(DocumentMode.docx.defaultSaveName, "Без имени.docx")
        XCTAssertEqual(DocumentMode.markdown.defaultSaveName, "Без имени.md")
    }

    func testDisplayName() {
        XCTAssertEqual(DocumentMode.docx.displayName, "DOCX")
        XCTAssertEqual(DocumentMode.markdown.displayName, "Markdown")
    }

    // MARK: - Сессия

    @MainActor
    func testSessionModeFollowsPreferenceOnInit() {
        let prefs = AppPreferences.shared
        let old = prefs.newDocumentMode
        defer { prefs.newDocumentMode = old }
        prefs.newDocumentMode = .markdown
        XCTAssertEqual(DocumentSession().mode, .markdown)
        prefs.newDocumentMode = .docx
        XCTAssertEqual(DocumentSession().mode, .docx)
    }

    @MainActor
    func testSessionResetRestoresPreferenceMode() {
        let prefs = AppPreferences.shared
        let old = prefs.newDocumentMode
        defer { prefs.newDocumentMode = old }
        prefs.newDocumentMode = .docx
        let s = DocumentSession()
        s.mode = .markdown
        s.reset()
        XCTAssertEqual(s.mode, .docx)
    }

    // MARK: - Настройка (UserDefaults round-trip)

    @MainActor
    func testNewDocumentModePreferenceRoundTrip() {
        let prefs = AppPreferences.shared
        let old = prefs.newDocumentMode
        defer { prefs.newDocumentMode = old }
        prefs.newDocumentMode = .markdown
        XCTAssertEqual(UserDefaults.standard.string(forKey: "pref.newDocumentMode"), "markdown")
        prefs.newDocumentMode = .docx
        XCTAssertEqual(UserDefaults.standard.string(forKey: "pref.newDocumentMode"), "docx")
    }

    // MARK: - Ограничение инструментов (v1.4.1)

    /// Все id в markdownHiddenRibbonGroups должны существовать в каталоге групп.
    func testMarkdownHiddenGroupsExistInCatalog() {
        let known = Set(RibbonGroupDef.all.map(\.id))
        for id in DocumentMode.markdownHiddenRibbonGroups {
            XCTAssertTrue(known.contains(id), "неизвестная группа ribbon: \(id)")
        }
    }

    /// Все id в markdownAllowedCommands должны существовать в каталоге команд.
    func testMarkdownAllowedCommandsExistInCatalog() {
        let known = Set(RibbonCommandDef.all.map(\.id))
        for id in DocumentMode.markdownAllowedCommands {
            XCTAssertTrue(known.contains(id), "неизвестная команда ribbon: \(id)")
        }
    }

    /// Группа «Шрифт» не должна быть полностью скрыта в MD — там живут B/I/U/S.
    func testMarkdownKeepsCoreGroups() {
        XCTAssertFalse(DocumentMode.markdownHiddenRibbonGroups.contains("home.font"))
        XCTAssertFalse(DocumentMode.markdownHiddenRibbonGroups.contains("home.paragraph"))
        XCTAssertFalse(DocumentMode.markdownHiddenRibbonGroups.contains("home.styles"))
        XCTAssertFalse(DocumentMode.markdownHiddenRibbonGroups.contains("view.zoom"))
    }

    // MARK: - Читаемая колонка (v1.5.8)

    func testMarkdownColumnWidthPresets() {
        XCTAssertEqual(MarkdownColumnWidth.narrow.points, 600)
        XCTAssertEqual(MarkdownColumnWidth.medium.points, 720)
        XCTAssertEqual(MarkdownColumnWidth.wide.points, 900)
        XCTAssertNil(MarkdownColumnWidth.full.points)
        // rawValue-стабильность (персист в UserDefaults).
        XCTAssertEqual(MarkdownColumnWidth(rawValue: "medium"), .medium)
        XCTAssertNil(MarkdownColumnWidth(rawValue: "bogus"))
    }

    /// Дефолт настройки — средняя колонка; запись в UserDefaults работает.
    @MainActor
    func testMarkdownColumnWidthDefaults() {
        let key = "pref.markdownColumnWidth"
        let old = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        // Свежий инстанс читать нельзя (singleton) — проверяем round-trip
        // через установку значения в shared.
        AppPreferences.shared.markdownColumnWidth = .wide
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "wide")
        AppPreferences.shared.markdownColumnWidth = .medium
    }
}
