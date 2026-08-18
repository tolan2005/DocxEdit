//
//  ImportReportView.swift
//  DocxEdit
//
//  «Отчёт об открытии» (v0.1.56) — что из OOXML не удалось полноценно восстановить.
//  Показывается по требованию (Обзор → «Отчёт об открытии») или автоматически,
//  когда открытый файл содержит непереваренные элементы.
//

import SwiftUI
import DocxCore

struct ImportReportView: View {
    @ObservedObject var session: DocumentSession
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отчёт об открытии")
                .font(.headline)

            performanceRow

            if session.lastImportReport.isEmpty {
                emptyState
            } else {
                Text("Мы открыли файл, но некоторые элементы не удалось восстановить полностью — они сохранены как обычный текст или пропущены. Это не всегда ошибка, а информация о том, что вы можете потерять при сохранении.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(session.lastImportReport.entries.enumerated()), id: \.offset) { _, entry in
                            entryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                if !session.lastImportReport.isEmpty {
                    Button("Скопировать в буфер") { copyToClipboard() }
                }
                Spacer()
                Button("Закрыть") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    /// v0.5.7 (R08): производительность open/save. Скрывается, если не было
    /// ни одного open/save в этой сессии.
    @ViewBuilder private var performanceRow: some View {
        let m = session.lastMetrics
        if m.lastOpenMs > 0 || m.lastSaveMs > 0 {
            HStack(spacing: 20) {
                if m.lastOpenMs > 0 {
                    metricCell(
                        icon: "arrow.down.doc",
                        title: "Открытие",
                        primary: formatMs(m.lastOpenMs),
                        secondary: "\(formatBytes(m.lastOpenBytes)) · \(formatMBps(m.openThroughputMBps))"
                    )
                }
                if m.lastSaveMs > 0 {
                    metricCell(
                        icon: "arrow.up.doc",
                        title: "Сохранение",
                        primary: formatMs(m.lastSaveMs),
                        secondary: "\(formatBytes(m.lastSaveBytes)) · \(formatMBps(m.saveThroughputMBps))"
                    )
                }
                Spacer()
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    private func metricCell(icon: String, title: String, primary: String, secondary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(primary).font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(secondary).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func formatMs(_ ms: Double) -> String {
        if ms < 10 { return String(format: "%.1f мс", ms) }
        if ms < 1000 { return "\(Int(ms.rounded())) мс" }
        return String(format: "%.2f c", ms / 1000)
    }
    private func formatBytes(_ b: Int) -> String {
        if b < 1024 { return "\(b) Б" }
        if b < 1024*1024 { return String(format: "%.1f КБ", Double(b) / 1024) }
        return String(format: "%.2f МБ", Double(b) / 1_048_576)
    }
    private func formatMBps(_ v: Double) -> String {
        v > 0 ? String(format: "%.1f МБ/с", v) : "—"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Всё импортировано без потерь.")
                    .font(.callout)
            }
            Text("В текущем документе не обнаружено OOXML-элементов, которые мы не смогли восстановить.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func entryRow(_ entry: ImportReport.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.category)
                        .font(.system(size: 13, weight: .semibold))
                    Text(entry.element)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("× \(entry.count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(entry.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func copyToClipboard() {
        var lines: [String] = ["Отчёт об открытии DocxEdit\n"]
        for e in session.lastImportReport.entries {
            lines.append("• \(e.category) (\(e.element)) × \(e.count)")
            lines.append("    \(e.explanation)")
        }
        let text = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
