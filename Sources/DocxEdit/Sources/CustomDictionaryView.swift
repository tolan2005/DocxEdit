//
//  CustomDictionaryView.swift
//  DocxEdit
//
//  v0.3.2 (R05): диалог управления пользовательским словарём — список слов,
//  которые spell checker считает корректными (learnWord).
//

import SwiftUI
import AppKit

struct CustomDictionaryView: View {
    @ObservedObject var controller: DocumentController
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var newWord: String = ""
    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пользовательский словарь")
                .font(.headline)
            Text("Слова из этого списка не подчёркиваются как орфографические ошибки.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(prefs.customDictionary, id: \.self) { word in
                    Text(word).tag(word as String?)
                }
            }
            .frame(minHeight: 220)
            .border(Color(NSColor.separatorColor))

            HStack {
                TextField("Новое слово", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Добавить") { add() }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Удалить") {
                    if let w = selection { controller.removeFromCustomDictionary(w); selection = nil }
                }
                .disabled(selection == nil)
            }

            HStack {
                Spacer()
                Button("Готово") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 380)
    }

    private func add() {
        controller.addToCustomDictionary(newWord)
        newWord = ""
    }
}
