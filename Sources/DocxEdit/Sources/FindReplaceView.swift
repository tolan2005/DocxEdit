//
//  FindReplaceView.swift
//  DocxEdit
//
//  v0.1.96: расширенный поиск и замена — с regex, учётом регистра и целыми словами.
//  Отдельный дилог (не подменяет системный NSTextFinder на ⌘F): открывается меню
//  Правка → Расширенный поиск… (⇧⌘F). Использует DocumentController.findNext /
//  replaceCurrent / replaceAll. Окно по паттерну v0.1.91 (см. ADR-039 п.7).
//

import SwiftUI
import AppKit

struct FindReplaceView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var searchText: String = ""
    @State private var replaceText: String = ""
    @State private var useRegex: Bool = false
    @State private var caseSensitive: Bool = false
    @State private var wholeWord: Bool = false
    @State private var statusMessage: String = ""
    @State private var matchCount: Int = 0
    /// v1.5.18: подсветка всех вхождений в документе (рисует DocxLayoutManager).
    @State private var highlightAll: Bool = true

    private var options: DocumentController.SearchOptions {
        DocumentController.SearchOptions(useRegex: useRegex, caseSensitive: caseSensitive, wholeWord: wholeWord)
    }

    private func refreshCount() {
        guard !searchText.isEmpty else {
            matchCount = 0
            controller.clearFindHighlights()
            return
        }
        matchCount = controller.countMatches(pattern: searchText, options: options)
        if highlightAll {
            controller.showFindHighlights(pattern: searchText, options: options)
        } else {
            controller.clearFindHighlights()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Найти и заменить").font(.headline)
            HStack {
                Text("Найти:").frame(width: 80, alignment: .trailing)
                TextField(useRegex ? "регулярное выражение…" : "текст…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Заменить:").frame(width: 80, alignment: .trailing)
                TextField(useRegex ? "$1 для групп…" : "текст…", text: $replaceText)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 16) {
                Toggle("Регулярное выражение", isOn: $useRegex)
                Toggle("Учитывать регистр", isOn: $caseSensitive)
                Toggle("Слово целиком", isOn: $wholeWord)
                Toggle("Подсветить все", isOn: $highlightAll)
            }
            .toggleStyle(.checkbox)
            HStack {
                // v1.5.18: «3 из 17» — текущее совпадение среди всех.
                let idxText = controller.findCurrentIndex.map { "\($0) из \(matchCount)" }
                Text(searchText.isEmpty ? " " : "Совпадений: \(matchCount)" + (idxText.map { " — \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(matchCount == 0 && !searchText.isEmpty ? .red : .secondary)
                Spacer()
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Закрыть") {
                    controller.clearFindHighlights()
                    onClose()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Заменить все") {
                    let n = controller.replaceAll(pattern: searchText, replacement: replaceText, options: options)
                    statusMessage = n == 0 ? "Не найдено." : "Заменено: \(n)"
                    refreshCount()
                }
                .disabled(searchText.isEmpty)
                Button("Заменить") {
                    if controller.replaceCurrent(pattern: searchText, replacement: replaceText, options: options) {
                        statusMessage = ""
                    } else {
                        statusMessage = "Не найдено."
                    }
                }
                .disabled(searchText.isEmpty)
                Button("Найти далее") {
                    if controller.findNext(pattern: searchText, options: options) {
                        statusMessage = ""
                    } else {
                        statusMessage = "Не найдено."
                    }
                }
                .disabled(searchText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: searchText)   { _ in refreshCount() }
        .onChange(of: useRegex)     { _ in refreshCount() }
        .onChange(of: caseSensitive){ _ in refreshCount() }
        .onChange(of: wholeWord)    { _ in refreshCount() }
        .onChange(of: highlightAll) { _ in refreshCount() }
        .onDisappear { controller.clearFindHighlights() }
    }
}
