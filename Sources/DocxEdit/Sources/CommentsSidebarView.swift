//
//  CommentsSidebarView.swift
//  DocxEdit
//
//  v0.4.4 (R06): боковая панель комментариев справа от редактора. Показывает
//  все треды документа с author/date/text + ответами; поддерживает переход
//  к тексту треда, добавление ответа, resolve/unresolve, удаление.
//
//  Паттерн — StylesSidebarView (v0.2.7): панель фиксированной ширины,
//  ObservedObject на CommentsEngine (перерисовка через `version`).
//

import SwiftUI
import AppKit
import DocxCore

struct CommentsSidebarView: View {
    @ObservedObject var engine: CommentsEngine
    @Binding var width: CGFloat
    /// v1.5.9: закрытие панели крестиком в заголовке.
    var onClose: (() -> Void)? = nil
    @State private var newCommentText: String = ""
    @State private var replyDrafts: [String: String] = [:]  // threadId → draft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Комментарии").font(.headline)
                Spacer()
                Button {
                    guard !newCommentText.isEmpty else { return }
                    engine.addComment(text: newCommentText)
                    newCommentText = ""
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .buttonStyle(.plain)
                .help("Добавить комментарий к выделению")
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Закрыть панель")
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)

            HStack {
                TextField("Новый комментарий…", text: $newCommentText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            let items = engine.listComments()
            if items.isEmpty {
                Text("Пока нет комментариев.\nВыделите текст и нажмите +.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.thread.id) { item in
                            threadCard(item.thread, orphan: item.anchor == nil)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: width)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func threadCard(_ thread: CommentThread, orphan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(thread.author).font(.caption).bold()
                Text(dateString(thread.date)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if thread.resolved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Решён")
                }
                if orphan {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Привязка к тексту потеряна")
                }
            }
            Text(thread.text).font(.body)
            ForEach(thread.replies) { reply in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reply.author).font(.caption2).bold()
                        Text(dateString(reply.date)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(reply.text).font(.callout)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            }
            // Ответ
            HStack {
                TextField("Ответить…", text: Binding(
                    get: { replyDrafts[thread.id] ?? "" },
                    set: { replyDrafts[thread.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Button("↵") {
                    let d = replyDrafts[thread.id]?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !d.isEmpty else { return }
                    engine.addReply(threadId: thread.id, text: d)
                    replyDrafts[thread.id] = ""
                }
                .disabled((replyDrafts[thread.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                Button {
                    engine.goToComment(threadId: thread.id)
                } label: {
                    Image(systemName: "location")
                }
                .buttonStyle(.plain).help("Перейти к тексту")
                .disabled(orphan)
                Button {
                    engine.setResolved(threadId: thread.id, resolved: !thread.resolved)
                } label: {
                    Image(systemName: thread.resolved ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(.plain).help(thread.resolved ? "Открыть заново" : "Пометить решённым")
                Spacer()
                Button {
                    engine.removeComment(threadId: thread.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain).help("Удалить тред")
            }
        }
        .padding(10)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5))
        .cornerRadius(6)
        .opacity(thread.resolved ? 0.6 : 1.0)
    }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}
