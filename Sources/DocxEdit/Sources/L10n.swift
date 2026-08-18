//
//  L10n.swift
//  DocxEdit (v0.6.2, R09 «Beta»)
//
//  Хелпер локализации. Строки хранятся в `Sources/Resources/{lang}.lproj/Localizable.strings`,
//  SPM пакует их в resource bundle `DocxEdit_DocxEdit.bundle` (см. Package.swift
//  и build.sh — bundle копируется в .app/Contents/Resources).
//
//  Использование: `L10n("menu.file.save")` вместо литеральной строки.
//  Fallback: если ключ не найден, возвращается сам ключ (Foundation-поведение
//  по умолчанию), — визуально бросается в глаза и указывает, что перевод отсутствует.
//
//  **Статус R09**: инфраструктура заложена, но по проекту всё ещё сотни
//  русских литералов в SwiftUI-вьюхах. Полный sweep — задача R10 «Release».
//  До того момента приложение остаётся преимущественно русскоязычным даже с
//  системным языком English.
//

import Foundation

func L10n(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: comment)
}
