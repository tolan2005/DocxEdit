//
//  UpdaterEngine.swift
//  DocxEdit (v1.1.0, v1.2.2 — progress + auto-install)
//
//  Встроенный автообновление: проверка GitHub Releases, semver-сравнение,
//  скачивание .dmg с SHA256-верификацией, авто-установка и перезапуск через
//  detached bash-скрипт (§4.5 REQUIREMENTS_AUTOUPDATE).
//
//  Приватность (ADR-008): никаких User-Agent-хвостов с ID, при `.never` — 0 запросов.
//

import Foundation
import AppKit
import SwiftUI

// MARK: - Config

enum UpdateConfig {
    static let owner = "tolan2005"
    static let repo  = "DocxEdit"

    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    }

    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "DocxEdit/\(v) (macOS)"
    }

    static let cacheTTL: TimeInterval = 60 * 60
}

// MARK: - Semver

enum Semver {
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = parts(lhs), b = parts(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    private static func parts(_ s: String) -> [Int] {
        var str = s
        if str.hasPrefix("v") { str.removeFirst() }
        if let dash = str.firstIndex(of: "-") { str = String(str[..<dash]) }
        return str.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func normalize(_ s: String) -> String {
        var str = s
        if str.hasPrefix("v") { str.removeFirst() }
        return str
    }
}

// MARK: - GitHub Release model

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let assets: [Asset]
    let prerelease: Bool
    let htmlURL: URL

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets, prerelease
        case htmlURL = "html_url"
    }
}

// MARK: - SHA256

enum SHA256Verifier {
    static func expectedHash(for filename: String, sumsFileContents: String) -> String? {
        for line in sumsFileContents.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let hash = String(parts[0])
            let name = String(parts.dropFirst().joined(separator: " ")).trimmingCharacters(in: .whitespaces)
            if name == filename { return hash.lowercased() }
        }
        return nil
    }

    static func fileHash(at url: URL) throws -> String {
        let p = Process()
        p.launchPath = "/usr/bin/shasum"
        p.arguments = ["-a", "256", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        return String(s.split(separator: " ").first ?? "").lowercased()
    }
}

// MARK: - Install phase (для UI прогресса)

enum InstallPhase {
    case downloading(Double)
    case verifying
    case installing
}

// MARK: - Download delegate (для стриминга прогресса)

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var savedLocation: URL?

    func setContinuation(_ c: CheckedContinuation<URL, Error>) {
        self.continuation = c
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let cb = onProgress
        DispatchQueue.main.async { cb?(p) }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Файл в location удалится, как только этот делегат вернёт управление —
        // копируем в стабильное место немедленно (синхронно, до завершения делегата).
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxEdit-update-" + UUID().uuidString + "-" +
                                    (downloadTask.originalRequest?.url?.lastPathComponent ?? "download"))
        do {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.moveItem(at: location, to: dst)
            savedLocation = dst
        } catch {
            savedLocation = nil
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let e = error {
            continuation?.resume(throwing: e)
        } else if let loc = savedLocation {
            continuation?.resume(returning: loc)
        } else {
            continuation?.resume(throwing: NSError(
                domain: "UpdaterEngine", code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Загрузка завершена без файла"]
            ))
        }
        continuation = nil
    }
}

// MARK: - Engine

@MainActor
final class UpdaterEngine: ObservableObject {
    static let shared = UpdaterEngine()

    @Published var availableUpdate: GitHubRelease?
    @Published var isChecking: Bool = false
    @Published var lastError: String?

    private let session = URLSession(configuration: .ephemeral)
    private let prefs = AppPreferences.shared

    private init() {}

    // MARK: Public API

    func checkOnLaunchIfNeeded() {
        guard let interval = prefs.updateCheckFrequency.interval else { return }
        if let last = prefs.lastUpdateCheck, Date().timeIntervalSince(last) < interval {
            return
        }
        Task { await self.performCheck(manual: false) }
    }

    func checkNow() {
        Task { await self.performCheck(manual: true) }
    }

    // MARK: Core

    private func performCheck(manual: Bool) async {
        isChecking = true
        lastError = nil
        defer { isChecking = false; prefs.lastUpdateCheck = Date() }

        do {
            let release = try await fetchLatestRelease()
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let remoteVersion = Semver.normalize(release.tagName)

            let cmp = Semver.compare(remoteVersion, currentVersion)
            if cmp > 0 {
                if !manual, prefs.skippedUpdateVersion == remoteVersion { return }
                self.availableUpdate = release
            } else if manual {
                self.lastError = "У вас уже установлена последняя версия (\(currentVersion))."
            }
        } catch {
            if manual { self.lastError = "Не удалось проверить обновления: \(error.localizedDescription)" }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var req = URLRequest(url: UpdateConfig.latestReleaseURL)
        req.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "UpdaterEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    // MARK: Download & Install

    /// Скачивает .dmg (fallback: .app.zip), верифицирует SHA256, запускает detached
    /// installer-скрипт и завершает текущий процесс. installer ждёт выхода родителя,
    /// копирует .app на место, снимает quarantine и перезапускает обновлённое приложение.
    func downloadAndInstall(_ release: GitHubRelease,
                            progress: @escaping (InstallPhase) -> Void) async throws {
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        let zipAsset = release.assets.first { $0.name.hasSuffix(".app.zip") }
        let sumsAsset = release.assets.first { $0.name == "SHA256SUMS" }

        guard let asset = dmgAsset ?? zipAsset else {
            throw NSError(domain: "UpdaterEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "В релизе нет подходящего файла для установки. Скачайте вручную: \(release.htmlURL.absoluteString)"])
        }

        // 1. Скачиваем с потоковым прогрессом.
        let downloaded = try await downloadFileWithProgress(from: asset.browserDownloadURL) { p in
            progress(.downloading(p))
        }

        // 2. Верификация SHA256 (обязательно, если SHA256SUMS есть).
        progress(.verifying)
        if let sums = sumsAsset {
            let sumsData = try await downloadData(from: sums.browserDownloadURL)
            let sumsText = String(data: sumsData, encoding: .utf8) ?? ""
            if let expected = SHA256Verifier.expectedHash(for: asset.name, sumsFileContents: sumsText) {
                let actual = try SHA256Verifier.fileHash(at: downloaded)
                if actual != expected {
                    try? FileManager.default.removeItem(at: downloaded)
                    throw NSError(domain: "UpdaterEngine", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "Не удалось проверить целостность файла — обновление отменено."])
                }
            }
        }

        // 3. Запускаем detached installer + завершаем себя.
        progress(.installing)
        try launchInstallerAndQuit(downloadedPath: downloaded)
    }

    private func downloadFileWithProgress(from url: URL,
                                          progress: @escaping (Double) -> Void) async throws -> URL {
        let delegate = DownloadProgressDelegate()
        delegate.onProgress = progress
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        var req = URLRequest(url: url)
        req.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 300

        return try await withCheckedThrowingContinuation { cont in
            delegate.setContinuation(cont)
            let task = session.downloadTask(with: req)
            task.resume()
        }
    }

    private func downloadData(from url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 60
        let (data, _) = try await session.data(for: req)
        return data
    }

    // MARK: Installer script

    /// Пишет bash-скрипт в /tmp, запускает его detached с PID/пути и завершает текущее приложение.
    private func launchInstallerAndQuit(downloadedPath: URL) throws {
        let appBundle = Bundle.main.bundleURL
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocxEdit-install-\(UUID().uuidString).sh")

        try Self.installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        // chmod +x
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let pid = ProcessInfo.processInfo.processIdentifier

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [
            scriptURL.path,
            "\(pid)",
            downloadedPath.path,
            appBundle.path
        ]
        // Отключаем I/O — скрипт должен пережить родителя.
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()

        // Даём скрипту стартовать, потом гасим себя корректно.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    /// Установочный bash-скрипт. Ждёт выхода родителя (до 30 с), монтирует .dmg
    /// (или распаковывает .zip), копирует .app на место, снимает com.apple.quarantine,
    /// перезапускает обновлённое приложение и удаляет за собой временные файлы.
    private static let installerScript: String = #"""
#!/bin/bash
set -u

PARENT_PID="$1"
DOWNLOAD_PATH="$2"
APP_PATH="$3"

log() { : ; } # тихо; для отладки заменить на: echo "$@" >> /tmp/docxedit-install.log

log "installer start pid=$PARENT_PID dl=$DOWNLOAD_PATH app=$APP_PATH"

# 1. Ждём выхода родителя (максимум 30с).
for i in $(seq 1 300); do
    if ! kill -0 "$PARENT_PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
# Даём OS освободить bundle.
sleep 0.5

APP_NAME=$(basename "$APP_PATH")
MOUNT_POINT=""

install_from_dmg() {
    local ATTACH
    ATTACH=$(hdiutil attach -nobrowse -readonly -noautoopen "$DOWNLOAD_PATH" 2>/dev/null)
    MOUNT_POINT=$(echo "$ATTACH" | grep -o '/Volumes/[^ ].*' | tail -n1)
    if [ -z "$MOUNT_POINT" ]; then
        log "mount failed"
        return 1
    fi
    local SRC_APP
    SRC_APP=$(find "$MOUNT_POINT" -maxdepth 2 -name "$APP_NAME" -type d 2>/dev/null | head -n1)
    if [ -z "$SRC_APP" ]; then
        SRC_APP=$(find "$MOUNT_POINT" -maxdepth 2 -name "*.app" -type d 2>/dev/null | head -n1)
    fi
    if [ -z "$SRC_APP" ]; then
        log "no .app inside dmg"
        return 1
    fi
    # Копируем в staging, потом атомарно меняем.
    local STAGING
    STAGING=$(dirname "$APP_PATH")/.$APP_NAME.new.$$
    rm -rf "$STAGING" 2>/dev/null
    cp -R "$SRC_APP" "$STAGING" || return 1
    rm -rf "$APP_PATH" 2>/dev/null
    mv "$STAGING" "$APP_PATH" || return 1
    return 0
}

install_from_zip() {
    local WORK
    WORK=$(mktemp -d)
    /usr/bin/unzip -q "$DOWNLOAD_PATH" -d "$WORK" || { rm -rf "$WORK"; return 1; }
    local SRC_APP
    SRC_APP=$(find "$WORK" -maxdepth 3 -name "$APP_NAME" -type d 2>/dev/null | head -n1)
    if [ -z "$SRC_APP" ]; then
        SRC_APP=$(find "$WORK" -maxdepth 3 -name "*.app" -type d 2>/dev/null | head -n1)
    fi
    if [ -z "$SRC_APP" ]; then
        rm -rf "$WORK"; return 1
    fi
    local STAGING
    STAGING=$(dirname "$APP_PATH")/.$APP_NAME.new.$$
    rm -rf "$STAGING" 2>/dev/null
    cp -R "$SRC_APP" "$STAGING" || { rm -rf "$WORK"; return 1; }
    rm -rf "$APP_PATH" 2>/dev/null
    mv "$STAGING" "$APP_PATH" || { rm -rf "$WORK"; return 1; }
    rm -rf "$WORK"
    return 0
}

INSTALL_OK=1
case "$DOWNLOAD_PATH" in
    *.dmg) install_from_dmg && INSTALL_OK=0 ;;
    *.zip) install_from_zip && INSTALL_OK=0 ;;
    *)     log "unknown ext: $DOWNLOAD_PATH" ;;
esac

# Всегда стараемся размонтировать, если было.
if [ -n "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet -force >/dev/null 2>&1 || true
fi

if [ "$INSTALL_OK" -eq 0 ]; then
    # Снимаем quarantine, чтобы Gatekeeper не показывал предупреждение.
    xattr -d -r com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    # Перезапуск.
    /usr/bin/open "$APP_PATH"
else
    # Откат неполучился — показываем оригинальный .dmg/.zip в Finder, чтобы пользователь мог поставить вручную.
    /usr/bin/open -R "$DOWNLOAD_PATH"
fi

# Уборка.
rm -f "$DOWNLOAD_PATH" 2>/dev/null || true
# self-delete (скрипт удаляется после завершения).
rm -f "$0" 2>/dev/null || true
exit 0
"""#

    // MARK: UI actions

    func skipCurrentAvailable() {
        if let r = availableUpdate {
            prefs.skippedUpdateVersion = Semver.normalize(r.tagName)
        }
        availableUpdate = nil
    }

    func dismissCurrentAvailable() {
        availableUpdate = nil
    }
}
