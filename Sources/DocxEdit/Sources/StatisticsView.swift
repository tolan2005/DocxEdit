//
//  StatisticsView.swift
//  DocxEdit
//
//  Диалог «Статистика документа» — счётчики слов/знаков/абзацев/строк/страниц.
//

import SwiftUI
import AppKit
import DocxCore

/// Полная статистика: базовая (из DocumentStatisticsCalculator) + строки и страницы
/// из живого layout NSTextView.
struct FullStatistics {
    let stats: DocumentStatistics
    let lines: Int
    let pages: Int
}

struct StatisticsView: View {
    let stats: FullStatistics
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Статистика документа")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                row("Страниц",                  value: stats.pages)
                row("Слов",                     value: stats.stats.words)
                row("Знаков (с пробелами)",     value: stats.stats.characters)
                row("Знаков (без пробелов)",    value: stats.stats.charactersNoSpaces)
                row("Абзацев",                  value: stats.stats.paragraphs)
                row("Строк",                    value: stats.lines)
            }
            .padding(.vertical, 4)

            HStack {
                Button("Обновить") { onRefresh() }
                Spacer()
                Button("Закрыть") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func row(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .monospacedDigit()
        }
    }
}
