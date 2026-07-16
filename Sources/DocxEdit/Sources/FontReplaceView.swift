//
//  FontReplaceView.swift
//  DocxEdit
//
//  Диалог замены шрифтов: таблица использующихся в документе шрифтов,
//  отмечает отсутствующие в системе, позволяет выбрать замену для каждого.
//

import SwiftUI
import AppKit

struct FontReplaceRow: Identifiable {
    let id: String
    let fontName: String
    let isMissing: Bool
    var replacement: String = ""
}

struct FontReplaceView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void = {}

    @State private var rows: [FontReplaceRow] = []
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Шрифты, используемые в документе. Отмеченные красным отсутствуют в системе.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                HStack {
                    Text("Шрифт документа").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Заменить на").font(.caption).foregroundStyle(.secondary)
                        .frame(width: 200, alignment: .leading)
                }
                ForEach($rows) { $row in
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: row.isMissing ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(row.isMissing ? .orange : .green)
                            Text(row.fontName)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("", selection: $row.replacement) {
                            Text("— без замены —").tag("")
                            if !prefs.favoriteFonts.isEmpty {
                                Section("Избранные") {
                                    ForEach(prefs.favoriteFonts, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            if !prefs.recentFonts.isEmpty {
                                Section("Недавние") {
                                    ForEach(prefs.recentFonts, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            Section(prefs.favoriteFonts.isEmpty && prefs.recentFonts.isEmpty ? "" : "Все шрифты") {
                                ForEach(controller.availableFonts, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                Button("Заменить шрифты") {
                    for row in rows where !row.replacement.isEmpty {
                        controller.replaceFont(from: row.fontName, to: row.replacement)
                    }
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rows.contains { !$0.replacement.isEmpty })
            }
        }
        .padding()
        .frame(width: 520, height: 380)
        .onAppear {
            rows = controller.fontsUsedInDocument().map {
                FontReplaceRow(id: $0.id, fontName: $0.id, isMissing: $0.isMissing)
            }
        }
    }
}
