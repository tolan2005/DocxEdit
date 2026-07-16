//
//  DocumentPropertiesView.swift
//  DocxEdit
//
//  v0.2.1 (R04): диалог «Свойства документа» — title/author/subject/keywords/
//  language документа. Сохраняются в модель (DocumentMetadata), DOCX
//  round-trip через docProps/core.xml (уже был + расширен keywords/language).
//

import SwiftUI
import AppKit
import DocxCore

struct DocumentPropertiesView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var title: String = ""
    @State private var author: String = ""
    @State private var subject: String = ""
    @State private var keywords: String = ""
    @State private var language: String = "ru-RU"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Свойства документа").font(.headline)
            Form {
                HStack {
                    Text("Название:").frame(width: 110, alignment: .trailing)
                    TextField("", text: $title).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Автор:").frame(width: 110, alignment: .trailing)
                    TextField("", text: $author).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Тема:").frame(width: 110, alignment: .trailing)
                    TextField("", text: $subject).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Ключевые слова:").frame(width: 110, alignment: .trailing)
                    TextField("через запятую", text: $keywords).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Язык:").frame(width: 110, alignment: .trailing)
                    TextField("ru-RU, en-US, …", text: $language).textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Spacer()
                }
            }
            HStack {
                if let session = controller.session {
                    let createdAt = session.bridge.model.metadata.createdAt
                    let modifiedAt = session.bridge.model.metadata.modifiedAt
                    let df: DateFormatter = {
                        let f = DateFormatter()
                        f.dateStyle = .medium
                        f.timeStyle = .short
                        return f
                    }()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Создан: \(df.string(from: createdAt))")
                        Text("Изменён: \(df.string(from: modifiedAt))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear { load() }
    }

    private func load() {
        guard let m = controller.session?.bridge.model.metadata else { return }
        title = m.title
        author = m.author
        subject = m.subject
        keywords = m.keywords.joined(separator: ", ")
        language = m.language
    }

    private func apply() {
        let kw = keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        controller.updateMetadata(title: title, author: author, subject: subject,
                                  keywords: kw, language: language)
        onClose()
    }
}
