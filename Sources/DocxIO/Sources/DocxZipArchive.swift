//
//  Распил монолита DocxIO.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Типы перемещены без изменения кода; private → internal (file-scope
//  private в общем файле был de-facto fileprivate, типы нужны кросс-файл).
//

import Foundation
import ZIPFoundation
import DocxCore

// MARK: - ZIP-архив

func buildArchive(parts: [String: Data]) throws -> Data {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DocxEdit-\(UUID().uuidString)", isDirectory: true)
    let stagingDir = tempDir.appendingPathComponent("staging", isDirectory: true)
    let zipURL    = tempDir.appendingPathComponent("output.zip")

    defer { try? FileManager.default.removeItem(at: tempDir) }

    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

    for (path, data) in parts {
        let fileURL = stagingDir.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
    }

    guard let archive = try? Archive(url: zipURL, accessMode: .create) else {
        throw DocumentError.ioError("Не удалось создать ZIP-архив")
    }
    try addDirectoryToArchive(archive: archive, baseURL: stagingDir, directory: stagingDir, prefix: "")
    return try Data(contentsOf: zipURL)
}

func addDirectoryToArchive(archive: Archive, baseURL: URL, directory: URL, prefix: String) throws {
    let fm = FileManager.default
    for item in try fm.contentsOfDirectory(atPath: directory.path) {
        let itemURL   = directory.appendingPathComponent(item)
        let entryPath = prefix.isEmpty ? item : "\(prefix)/\(item)"
        var isDir: ObjCBool = false
        fm.fileExists(atPath: itemURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            try addDirectoryToArchive(archive: archive, baseURL: baseURL, directory: itemURL, prefix: entryPath)
        } else {
            // relativeTo — корень staging: ZIPFoundation читает файл по baseURL+entryPath.
            // Раньше передавался каталог файла → путь задваивался (docProps/docProps/core.xml).
            try archive.addEntry(
                with: entryPath,
                relativeTo: baseURL,
                compressionMethod: .deflate
            )
        }
    }
}

// v0.5.2: OOXML `w:u w:val=…` ↔ UnderlineStyle.
// До v0.5.2 варианты double/dotted/dashed молча схлопывались в .single и на
// парсере, и на writer — теряя стиль подчёркивания при DOCX round-trip.
enum OoxmlUnderlineMapper {
    static func parse(_ val: String) -> UnderlineStyle {
        switch val {
        case "none":          return .none
        case "double", "doubleThick": return .double
        case "dotted", "dottedThick", "dotDash", "dotDotDash": return .dotted
        case "dash", "dashed", "dashLong", "dashLongHeavy", "dashDotHeavy", "dashDotDotHeavy": return .dashed
        default:              return .single
        }
    }
}
