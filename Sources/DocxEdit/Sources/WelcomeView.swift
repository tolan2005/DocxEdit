//
//  WelcomeView.swift
//  DocxEdit (v1.2.1)
//
//  Окно приветствия при запуске без документа: Создать / Открыть / Недавние.
//  Показывается, когда приложение запущено не через файл и восстановление
//  последней сессии выключено или восстанавливать нечего.
//  Окно — NSWindow(contentRect:) + NSHostingView(sizingOptions: []) (ADR-039 п.7).
//

import SwiftUI
import AppKit

struct WelcomeView: View {
    let recentURLs: [URL]
    let onNew: () -> Void
    let onOpen: () -> Void
    let onOpenRecent: (URL) -> Void
    let onClose: () -> Void

    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        HStack(spacing: 0) {
            // Левая часть — приложение + действия.
            VStack(spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 88, height: 88)
                }
                Text("DocxEdit")
                    .font(.system(size: 24, weight: .semibold))
                Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer().frame(height: 6)

                Button {
                    onNew()
                } label: {
                    Label("Новый документ", systemImage: "doc.badge.plus")
                        .frame(width: 190)
                }
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    onOpen()
                } label: {
                    Label("Открыть…", systemImage: "folder")
                        .frame(width: 190)
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                Spacer()

                Toggle("Открывать при старте приложения",
                       isOn: $prefs.showWelcomeOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(28)
            .frame(width: 280)

            Divider()

            // Правая часть — недавние файлы.
            VStack(alignment: .leading, spacing: 8) {
                Text("Недавние документы")
                    .font(.headline)
                    .padding(.bottom, 4)
                if recentURLs.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Недавних документов нет")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(recentURLs.prefix(8), id: \.absoluteString) { url in
                                Button {
                                    onOpenRecent(url)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: iconName(for: url))
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 13))
                                                .lineLimit(1)
                                            Text(url.deletingLastPathComponent().path)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        // v1.7.3: дата последнего изменения файла + размер, как в Finder.
                                        if let meta = fileMeta(for: url) {
                                            Text(meta)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                                .monospacedDigit()
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.primary.opacity(0.001)) // hover-friendly hit area
                                )
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 620, height: 360)
    }

    /// v1.7.3: иконка типа по расширению — .md/.docx/.txt/.rtf/.odt/.pdf.
    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "m.square"
        case "docx", "doc":    return "doc.richtext"
        case "rtf":            return "doc.plaintext"
        case "odt":            return "doc"
        case "pdf":            return "doc.viewfinder"
        default:               return "doc.text"
        }
    }

    /// v1.7.3: правая колонка — «дата · размер», как в Finder.
    /// Формат даты: сегодня «сегодня 14:32», иначе — короткий локализованный.
    private func fileMeta(for url: URL) -> String? {
        guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = vals.contentModificationDate else { return nil }
        let cal = Calendar.current
        let df = DateFormatter()
        if cal.isDateInToday(date) {
            df.dateFormat = "'сегодня' HH:mm"
        } else if cal.isDateInYesterday(date) {
            df.dateFormat = "'вчера' HH:mm"
        } else {
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "d MMM"
        }
        var text = df.string(from: date)
        if let size = vals.fileSize, size > 0 {
            text += " · \(sizeString(size))"
        }
        return text
    }
    private func sizeString(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}

/// Владелец окна приветствия (одно на приложение).
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show(appDelegate: AppDelegate) {
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); return }

        let view = WelcomeView(
            recentURLs: appDelegate.recentURLs,
            onNew:  { [weak self] in appDelegate.newDocument(); self?.close() },
            onOpen: { [weak self] in self?.close(); appDelegate.openDocument() },
            onOpenRecent: { [weak self] url in self?.close(); appDelegate.loadFromURL(url) },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
