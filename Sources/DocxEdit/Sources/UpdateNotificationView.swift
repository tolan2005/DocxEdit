//
//  UpdateNotificationView.swift
//  DocxEdit (v1.1.0, v1.2.2 — markdown + progress + auto-install)
//
//  Banner-диалог «Доступно обновление». Окно — NSWindow(contentRect:) +
//  NSHostingView(sizingOptions: []) (ADR-039 п.7).
//

import SwiftUI
import AppKit

struct UpdateNotificationView: View {
    let release: GitHubRelease
    let onInstall: () -> Void
    let onLater: () -> Void
    let onSkip: () -> Void

    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var statusText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Доступно обновление")
                        .font(.headline)
                    Text("DocxEdit \(release.tagName)" + (release.prerelease ? " (пре-релиз)" : ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            ScrollView {
                MarkdownReleaseNotesView(
                    markdown: release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "Описание отсутствует."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 140, maxHeight: 200)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            if isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress, total: 1.0)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Пропустить эту версию") { onSkip() }
                    .disabled(isDownloading)
                Spacer()
                Button("Позже") { onLater() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isDownloading)
                Button(isDownloading ? "Установка…" : "Установить сейчас") {
                    install()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDownloading)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }

    private func install() {
        isDownloading = true
        errorMessage = nil
        progress = 0
        statusText = "Скачивание…"

        Task { @MainActor in
            do {
                try await UpdaterEngine.shared.downloadAndInstall(release) { phase in
                    switch phase {
                    case .downloading(let p):
                        self.progress = p
                        let pct = Int(p * 100)
                        self.statusText = "Скачивание… \(pct)%"
                    case .verifying:
                        self.progress = 1.0
                        self.statusText = "Проверка целостности…"
                    case .installing:
                        self.statusText = "Установка и перезапуск…"
                    }
                }
                // downloadAndInstall завершит текущий процесс — сюда обычно уже не доходит.
                onInstall()
            } catch {
                self.errorMessage = error.localizedDescription
                self.isDownloading = false
            }
        }
    }
}

// MARK: - Markdown-рендер release notes

/// Минимальный markdown → SwiftUI. Поддерживает: `###`/`##`/`#` заголовки,
/// `- `/`* ` буллиты, inline `**bold**`/`*italic*`/`` `code` `` (через AttributedString).
private struct MarkdownReleaseNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                render(line)
            }
        }
    }

    private var lines: [String] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    @ViewBuilder
    private func render(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 4)
        } else if line.hasPrefix("### ") {
            heading(String(line.dropFirst(4)), size: 13, weight: .bold, top: 6)
        } else if line.hasPrefix("## ") {
            heading(String(line.dropFirst(3)), size: 14, weight: .bold, top: 8)
        } else if line.hasPrefix("# ") {
            heading(String(line.dropFirst(2)), size: 15, weight: .bold, top: 8)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 12))
                inlineText(String(line.dropFirst(2)))
            }
        } else {
            inlineText(line)
        }
    }

    private func heading(_ text: String, size: CGFloat, weight: Font.Weight, top: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .padding(.top, top)
    }

    private func inlineText(_ text: String) -> some View {
        // AttributedString(markdown:) поддерживает **/*/`code` inline.
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr).font(.system(size: 12)).textSelection(.enabled)
        }
        return Text(text).font(.system(size: 12)).textSelection(.enabled)
    }
}
