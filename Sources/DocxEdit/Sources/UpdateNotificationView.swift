//
//  UpdateNotificationView.swift
//  DocxEdit (v1.1.0)
//
//  Banner-диалог «Доступно обновление». Показывается в отдельном NSWindow
//  по паттерну ADR-039 п.7 (NSWindow(contentRect:) + NSHostingView(sizingOptions:[])) —
//  единственный разрешённый паттерн диалогов после краха «Свойств таблицы» v0.1.70.
//

import SwiftUI

struct UpdateNotificationView: View {
    let release: GitHubRelease
    let onInstall: () -> Void
    let onLater: () -> Void
    let onSkip: () -> Void

    @State private var isDownloading = false
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
                Text(release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Описание отсутствует.")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 180)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(6)

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
                Button(isDownloading ? "Загрузка…" : "Установить сейчас") {
                    install()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isDownloading)
            }
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }

    private func install() {
        isDownloading = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await UpdaterEngine.shared.downloadAndInstall(release) { _ in }
                onInstall()
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
