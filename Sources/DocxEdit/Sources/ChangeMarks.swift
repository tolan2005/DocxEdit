//
//  ChangeMarks.swift
//  DocxEdit
//
//  Отметки изменённых строк Markdown-документа (как полоски изменений на полях
//  в VS Code): что поменялось на диске с момента «прочитано». Индексы — строки
//  текущего текста. Свои правки отметок не дают и только сдвигают чужие.
//

import Foundation

struct ChangeMarks: Equatable {
    enum Kind { case added, changed }
    /// Новая или изменённая строка.
    var lines: [Int: Kind] = [:]
    /// Перед этой строкой удалены строки (индекс == числу строк — удалено в конце).
    var deletedBefore: Set<Int> = []

    var isEmpty: Bool { lines.isEmpty && deletedBefore.isEmpty }

    /// Первая строка каждого места (подряд идущие отмеченные строки — одно место).
    var groupStarts: [Int] {
        let all = Set(lines.keys).union(deletedBefore).sorted()
        return all.enumerated().compactMap { i, l in i == 0 || all[i - 1] != l - 1 ? l : nil }
    }

    static func split(_ s: String) -> [Substring] {
        s.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Файл изменён на диске: old (что было на экране) → new. Старые отметки
    /// переносятся на совпавшие строки, новые и изменённые строки отмечаются.
    mutating func applyDiskChange(old: String, new: String) {
        let o = Self.split(old), n = Self.split(new)
        let diff = n.difference(from: o)
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in diff {
            switch c {
            case .remove(let off, _, _): removed.insert(off)
            case .insert(let off, _, _): inserted.insert(off)
            }
        }
        var nl: [Int: Kind] = [:]
        var nd = Set<Int>()
        var i = 0, j = 0
        while i < o.count || j < n.count {
            if i < o.count, j < n.count, !removed.contains(i), !inserted.contains(j) {
                if let k = lines[i] { nl[j] = k }
                if deletedBefore.contains(i) { nd.insert(j) }
                i += 1; j += 1
                continue
            }
            let i0 = i, j0 = j
            while i < o.count, removed.contains(i) { i += 1 }
            while j < n.count, inserted.contains(j) { j += 1 }
            if j > j0 {
                for x in j0..<j { nl[x] = i > i0 ? .changed : .added }
            } else if i > i0 {
                nd.insert(j)
            } else {
                break
            }
        }
        if deletedBefore.contains(o.count) { nd.insert(n.count) }
        lines = nl
        deletedBefore = nd
    }

    /// Своя правка old → new: отметки в изменённых строках снимаются,
    /// отметки ниже сдвигаются на разницу в числе строк.
    mutating func applyOwnEdit(old: String, new: String) {
        guard !isEmpty else { return }
        let o = Self.split(old), n = Self.split(new)
        var p = 0
        while p < o.count, p < n.count, o[p] == n[p] { p += 1 }
        var s = 0
        while s < o.count - p, s < n.count - p, o[o.count - 1 - s] == n[n.count - 1 - s] { s += 1 }
        let oldEnd = o.count - s, delta = n.count - o.count
        func move(_ l: Int) -> Int? { l < p ? l : (l >= oldEnd ? l + delta : nil) }
        lines = Dictionary(uniqueKeysWithValues: lines.compactMap { l, k in move(l).map { ($0, k) } })
        // Удаление перед первой изменённой строкой остаётся на месте.
        deletedBefore = Set(deletedBefore.compactMap { $0 == p ? p : move($0) })
    }
}
