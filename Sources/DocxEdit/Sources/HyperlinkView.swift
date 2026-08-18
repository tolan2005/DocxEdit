//
//  HyperlinkView.swift
//  DocxEdit
//
//  Диалог вставки/редактирования гиперссылки (v0.1.54, R03).
//  Открывается по ⌘K или через меню Вставка → «Гиперссылка…».
//

import SwiftUI
import AppKit

struct HyperlinkView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var displayText: String = ""
    @State private var url: String = ""
    @State private var isEditing: Bool = false  // true = в позиции курсора уже есть ссылка
    @FocusState private var focusedField: Field?

    private enum Field { case text, url }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing ? "Изменить гиперссылку" : "Вставить гиперссылку")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Текст:")
                    TextField("Отображаемый текст", text: $displayText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .text)
                }
                GridRow {
                    Text("Адрес:")
                    TextField("https://example.com", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .url)
                        .onSubmit { apply() }
                }
            }

            HStack {
                if isEditing {
                    Button("Удалить ссылку") {
                        controller.removeHyperlink()
                        onClose()
                    }
                }
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Сохранить" : "Вставить") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear {
            // Prefill: если в позиции курсора уже есть ссылка — редактируем её;
            // иначе — новый ввод. Если выделен текст — берём его в поле «Текст».
            if let existing = controller.hyperlinkAtCaret() {
                url = existing
                isEditing = true
            }
            let sel = controller.selectedText()
            if !sel.isEmpty {
                displayText = sel
                focusedField = .url
            } else {
                focusedField = .text
            }
        }
    }

    private func apply() {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        // Автопрефикс схемы, если пользователь ввёл голый домен.
        let normalized: String = {
            if clean.contains("://") || clean.hasPrefix("mailto:") || clean.hasPrefix("tel:") {
                return clean
            }
            if clean.contains("@") { return "mailto:\(clean)" }
            return "https://\(clean)"
        }()
        controller.insertHyperlink(text: displayText, url: normalized)
        onClose()
    }
}
