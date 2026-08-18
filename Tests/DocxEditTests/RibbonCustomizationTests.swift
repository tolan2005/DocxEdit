//
//  RibbonCustomizationTests.swift
//  DocxEditTests (v1.2.0)
//
//  Целостность каталога настройки ribbon: уникальность id, валидность вкладок.
//

import XCTest
@testable import DocxEdit

final class RibbonCustomizationTests: XCTestCase {

    func testGroupIDsUnique() {
        let ids = RibbonGroupDef.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Дублирующиеся id групп ribbon")
    }

    func testCommandIDsUnique() {
        let ids = RibbonCommandDef.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Дублирующиеся id команд ribbon")
    }

    func testGroupTabsMatchKnownTabs() {
        let knownTabs: Set<String> = ["Главная", "Вставка", "Разметка", "Таблица", "Обзор", "Вид"]
        for g in RibbonGroupDef.all {
            XCTAssertTrue(knownTabs.contains(g.tab), "Группа \(g.id) ссылается на неизвестную вкладку «\(g.tab)»")
        }
    }

    func testEveryTabHasAtLeastOneGroup() {
        for tab in ["Главная", "Вставка", "Разметка", "Таблица", "Обзор", "Вид"] {
            XCTAssertFalse(RibbonGroupDef.groups(forTab: tab).isEmpty, "Вкладка «\(tab)» без групп")
        }
    }

    func testFindCommandByID() {
        XCTAssertNotNil(RibbonCommandDef.find(id: "pageBreak"))
        XCTAssertNil(RibbonCommandDef.find(id: "no-such-command"))
    }

    /// v1.5.9: группа «Панели» (стили/комментарии/сноски) на вкладке «Вид».
    func testPanelsGroupExists() {
        let g = RibbonGroupDef.all.first { $0.id == "view.panels" }
        XCTAssertNotNil(g)
        XCTAssertEqual(g?.tab, "Вид")
    }
}
