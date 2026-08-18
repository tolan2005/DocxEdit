//
//  DefaultAppsView.swift
//  DocxEdit
//
//  Настройки «Сделать приложение по умолчанию»: таблица типов файлов,
//  которые умеет открывать DocxEdit, с текущим приложением по умолчанию
//  для каждого и возможностью назначить/сменить его.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreServices

struct FileTypeAssociation: Identifiable {
    let id: String
    /// UTType для API `NSWorkspace.urlForApplication(toOpen:)`.
    let utType: UTType
    let displayName: String
    let extensions: [String]

    /// Резолвит UTType по расширению файла (LaunchServices сама подставит
    /// актуальный UTI из зарегистрированных приложений или из декларации в
    /// нашем Info.plist). Фолбэк — строковый UTI, затем `.data`.
    private static func resolve(ext: String, uti: String) -> UTType {
        UTType(filenameExtension: ext) ?? UTType(uti) ?? .data
    }

    static let all: [FileTypeAssociation] = [
        .init(id: "docx",
              utType: resolve(ext: "docx", uti: "org.openxmlformats.wordprocessingml.document"),
              displayName: "Office Open XML (DOCX)", extensions: ["docx"]),
        .init(id: "doc",
              utType: resolve(ext: "doc", uti: "com.microsoft.word.doc"),
              displayName: "Legacy Word-Processor (DOC)", extensions: ["doc"]),
        .init(id: "rtf",
              utType: resolve(ext: "rtf", uti: "public.rtf"),
              displayName: "Rich Text Format", extensions: ["rtf"]),
        .init(id: "md",
              utType: resolve(ext: "md", uti: "net.daringfireball.markdown"),
              displayName: "Markdown", extensions: ["md", "markdown"]),
        .init(id: "txt",
              utType: resolve(ext: "txt", uti: "public.plain-text"),
              displayName: "Обычный текст", extensions: ["txt"]),
    ]
}

/// Владелец состояния таблицы дефолтов. Class + ObservableObject, потому что
/// SwiftUI TabView периодически пересоздаёт вьюху → `@State` теряется
/// (проверено: refresh отрабатывал, а последующие ренды показывали пустой словарь);
/// `@StateObject` переживает пересоздание вьюхи.
@MainActor
final class DefaultAppsModel: ObservableObject {
    @Published var currentDefaults: [String: URL] = [:]
    @Published var errorMessage: String?

    func refresh() {
        var next: [String: URL] = [:]
        for assoc in FileTypeAssociation.all {
            if let url = defaultApp(for: assoc) { next[assoc.id] = url }
        }
        currentDefaults = next
    }

    func setDefault(_ appURL: URL, for assoc: FileTypeAssociation) {
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: assoc.utType) { [weak self] err in
            Task { @MainActor in
                guard let self else { return }
                if let err {
                    self.errorMessage = "Не удалось установить приложение по умолчанию для \(assoc.displayName): \(err.localizedDescription)"
                } else {
                    self.errorMessage = nil
                }
                // NSWorkspace обновляет кэш LaunchServices не сразу.
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.refresh()
            }
        }
    }

    /// LaunchServices: (1) `LSCopyDefaultRoleHandlerForContentType` резолвит bundle
    /// id для UTI (устойчиво даже когда UTType не полностью зарегистрирован);
    /// (2) фолбэк — временный файл на диске (LS смотрит расширение);
    /// (3) фолбэк — UTType-based API.
    private func defaultApp(for assoc: FileTypeAssociation) -> URL? {
        let uti = assoc.utType.identifier
        if let bundleId = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?.takeRetainedValue() as String?,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        if let ext = assoc.extensions.first {
            let probe = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("docxedit-lsprobe-\(UUID().uuidString).\(ext)")
            let created = FileManager.default.createFile(atPath: probe.path, contents: nil)
            defer { if created { try? FileManager.default.removeItem(at: probe) } }
            if created, let url = NSWorkspace.shared.urlForApplication(toOpen: probe) {
                return url
            }
        }
        return NSWorkspace.shared.urlForApplication(toOpen: assoc.utType)
    }
}

struct DefaultAppsSettingsView: View {
    @StateObject private var model = DefaultAppsModel()

    private var ourBundleURL: URL { Bundle.main.bundleURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сделать приложение по умолчанию")
                .font(.headline)
            Text("Для каждого формата видно текущее приложение по умолчанию в системе. DocxEdit оптимизирован для DOCX; для остальных форматов — это дополнительная возможность.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(FileTypeAssociation.all) { assoc in
                row(for: assoc)
            }
            .listStyle(.bordered)
            .frame(minHeight: 220)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .onAppear { model.refresh() }
    }

    private func row(for assoc: FileTypeAssociation) -> some View {
        let currentURL = model.currentDefaults[assoc.id]
        let isUs = currentURL.map { sameApp($0, ourBundleURL) } ?? false

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(assoc.displayName)
                Text("." + assoc.extensions.joined(separator: ", ."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isUs {
                Label("DocxEdit — по умолчанию", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text(currentURL?.deletingPathExtension().lastPathComponent ?? "не определено")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !isUs {
                Button("Сделать DocxEdit приложением по умолчанию") {
                    model.setDefault(ourBundleURL, for: assoc)
                }
            }
            Button("Изменить на другое приложение…") {
                chooseOtherApp(for: assoc)
            }
        }
        .padding(.vertical, 2)
    }

    private func sameApp(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL == b.standardizedFileURL
    }

    private func chooseOtherApp(for assoc: FileTypeAssociation) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.setDefault(url, for: assoc)
        }
    }
}
