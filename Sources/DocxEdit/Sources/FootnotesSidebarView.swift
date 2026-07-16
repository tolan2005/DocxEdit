//
//  FootnotesSidebarView.swift
//  v0.5.4 (R07): панель списка/редактирования сносок.
//  Паттерн симметричен CommentsSidebarView. Правило проекта — окно/панель
//  через NSHostingView (см. table_properties_crash.md), но здесь панель — часть
//  DocumentWindowView как inline-элемент справа, не отдельное окно.
//

import SwiftUI
import DocxCore

struct FootnotesSidebarView: View {
    @ObservedObject var controller: DocumentController
    @Environment(\.dismiss) private var dismiss

    // Локальный state для редактирования — синхронизируется с моделью on commit.
    @State private var drafts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Сноски")
                    .font(.headline)
                Spacer()
                Text("\(controller.listFootnotes().count)")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(8)
            Divider()

            if controller.listFootnotes().isEmpty {
                Spacer()
                Text("Нет сносок")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(controller.listFootnotes(), id: \.id) { f in
                            footnoteRow(f)
                            Divider()
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func footnoteRow(_ f: Footnote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(f.id + ".")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .frame(width: 26, alignment: .leading)
                TextEditor(text: Binding(
                    get: { drafts[f.id] ?? f.text },
                    set: { newValue in
                        drafts[f.id] = newValue
                        controller.updateFootnoteText(id: f.id, text: newValue)
                    }
                ))
                .font(.system(size: 12))
                .frame(minHeight: 40, maxHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }
            HStack {
                Spacer()
                Button {
                    controller.removeFootnote(id: f.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Удалить сноску")
            }
        }
        .padding(.vertical, 2)
    }
}
