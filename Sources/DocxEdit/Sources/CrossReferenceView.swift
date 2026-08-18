//
//  CrossReferenceView.swift
//  v0.5.6 (R07): диалог вставки перекрёстной ссылки на закладку.
//

import SwiftUI

struct CrossReferenceView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var selectedBookmark: String = ""
    @State private var displayText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Перекрёстная ссылка")
                .font(.headline)

            let names = controller.listBookmarkNames()
            if names.isEmpty {
                Text("В документе нет закладок. Создайте закладку через Вставка → Закладка.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Целевая закладка:")
                Picker("", selection: $selectedBookmark) {
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .onAppear {
                    if selectedBookmark.isEmpty { selectedBookmark = names.first ?? "" }
                }

                Text("Текст ссылки (оставьте пустым — будет «→ имя»):")
                TextField("", text: $displayText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Вставить") {
                    guard !selectedBookmark.isEmpty else { onClose(); return }
                    controller.insertCrossReference(
                        bookmarkName: selectedBookmark,
                        displayText: displayText
                    )
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(names.isEmpty || selectedBookmark.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400)
    }
}
