//
//  BookmarksView.swift
//  DocxEdit
//
//  v0.2.4 (R04): диалог «Закладки» — список закладок документа + вставка/удаление/переход.
//  Закладки хранятся как custom NSAttributedString.Key .docxEditBookmark на диапазоне.
//  Известное ограничение: DOCX round-trip не реализован в этом релизе — закладки живут
//  только в текущем сеансе редактирования. Round-trip запланирован в отдельном фиксе.
//

import SwiftUI
import AppKit

struct BookmarksView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var newName: String = ""
    @State private var bookmarks: [BookmarkRow] = []
    @State private var selectedName: String? = nil

    struct BookmarkRow: Identifiable {
        var id: String { name }
        var name: String
        var previewText: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Закладки").font(.headline)

            HStack {
                TextField("Имя закладки", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Добавить") {
                    let trimmed = newName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    controller.insertBookmark(name: trimmed)
                    newName = ""
                    reload()
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            if bookmarks.isEmpty {
                Text("В документе нет закладок.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List(selection: $selectedName) {
                    ForEach(bookmarks) { b in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name).font(.body)
                            Text(b.previewText).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(b.name)
                    }
                }
                .frame(height: 200)
            }

            HStack {
                Button("Удалить") {
                    if let name = selectedName {
                        controller.deleteBookmark(name: name)
                        reload()
                    }
                }
                .disabled(selectedName == nil)

                Button("Перейти") {
                    if let name = selectedName {
                        controller.goToBookmark(name: name)
                    }
                }
                .disabled(selectedName == nil)

                Spacer()

                Button("Закрыть") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { reload() }
    }

    private func reload() {
        let raw = controller.listBookmarks()
        // Разные диапазоны с одним именем схлопываем в одну запись (первую).
        var seen = Set<String>()
        var out: [BookmarkRow] = []
        if let storage = controller.textView?.textStorage {
            for b in raw where !seen.contains(b.name) {
                seen.insert(b.name)
                let start = b.range.location
                let len = min(b.range.length, 40)
                let ns = storage.string as NSString
                let preview: String
                if start + len <= ns.length {
                    preview = ns.substring(with: NSRange(location: start, length: len))
                        .replacingOccurrences(of: "\n", with: " ")
                } else {
                    preview = ""
                }
                out.append(BookmarkRow(name: b.name, previewText: preview))
            }
        }
        bookmarks = out
    }
}
