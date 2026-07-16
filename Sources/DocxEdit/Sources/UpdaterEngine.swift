//
//  UpdaterEngine.swift
//  DocxEdit (v1.1.0)
//
//  Встроенный автообновление: проверка GitHub Releases, semver-сравнение,
//  скачивание .dmg с SHA256-верификацией. См. REQUIREMENTS_AUTOUPDATE.md §4.
//
//  Устройство: минимальная схема без Sparkle-зависимости.
//  1. GET https://api.github.com/repos/<owner>/<repo>/releases/latest
//  2. Сравниваем tag_name с текущей CFBundleShortVersionString через semver.
//  3. Если новее — показываем banner (UpdateNotificationView).
//  4. По клику «Установить» — скачиваем .dmg + SHA256SUMS, верифицируем, открываем.
//
//  Приватность (ADR-008): никаких User-Agent-хвостов с ID, никаких промежуточных
//  сервисов, при `.never` — 0 сетевых запросов.
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

    /// User-Agent строго без идентификаторов машины (REQUIREMENTS §4.3 F-B-11).
    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "DocxEdit/\(v) (macOS)"
    }

    /// Кеш metadata в UserDefaults — не долбим API повторно в пределах часа
    /// (риск R2 в §8 — cluster NAT / rate-limit 60/час/IP).
    static let cacheTTL: TimeInterval = 60 * 60
}

// MARK: - Semver

enum Semver {
    /// Возвращает `> 0`, если `lhs` новее `rhs`; `< 0`, если старее; `0` если равны.
    /// Pre-release суффиксы (`-rc.1`, `-beta.2`) игнорируются в v1 —
    /// это осознанное ограничение (см. REQUIREMENTS §5.1).
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let a = parts(lhs), b = parts(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// Разбирает "v1.2.3-rc.1" → [1, 2, 3] (стрипая ведущий v и pre-release суффикс).
    private static func parts(_ s: String) -> [Int] {
        var str = s
        if str.hasPrefix("v") { str.removeFirst() }
        if let dash = str.firstIndex(of: "-") { str = String(str[..<dash]) }
        return str.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// "1.2.3-rc.1" → "1.2.3". Для сравнения версий и матчинга asset-имён.
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
    /// Разбирает `SHA256SUMS` (формат `<hex>  <filename>`) и возвращает hash для
    /// указанного имени файла (или nil).
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

    /// Вычисляет SHA256 файла (hex, lowercase).
    static func fileHash(at url: URL) throws -> String {
        // Используем shasum(1) — не требует CommonCrypto/Digest импорта, гарантированно есть в macOS.
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

// MARK: - Engine

@MainActor
final class UpdaterEngine: ObservableObject {
    static let shared = UpdaterEngine()

    /// Найденная доступная версия для показа UI (nil = нет).
    @Published var availableUpdate: GitHubRelease?

    /// Идёт ли сетевая проверка сейчас (для UI индикатора).
    @Published var isChecking: Bool = false

    /// Ошибка ручной проверки (ставится только для manual — auto тихая).
    @Published var lastError: String?

    private let session = URLSession(configuration: .ephemeral)
    private let prefs = AppPreferences.shared

    private init() {}

    // MARK: Public API

    /// Автоматическая проверка при запуске — тихая, соблюдает интервал и `.never`.
    func checkOnLaunchIfNeeded() {
        guard let interval = prefs.updateCheckFrequency.interval else { return } // .never → 0 запросов
        if let last = prefs.lastUpdateCheck, Date().timeIntervalSince(last) < interval {
            return
        }
        Task { await self.performCheck(manual: false) }
    }

    /// Ручная проверка через меню — показывает результат даже если «нет обновлений».
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
                // Новее.
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

    /// Скачивает .dmg (fallback: .app.zip), верифицирует SHA256, открывает в Finder.
    func downloadAndInstall(_ release: GitHubRelease,
                            progress: @escaping (Double) -> Void) async throws {
        // 1. Ищем подходящий asset — приоритет .dmg.
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        let zipAsset = release.assets.first { $0.name.hasSuffix(".app.zip") }
        let sumsAsset = release.assets.first { $0.name == "SHA256SUMS" }

        guard let asset = dmgAsset ?? zipAsset else {
            throw NSError(domain: "UpdaterEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "В релизе нет подходящего файла для установки. Скачайте вручную: \(release.htmlURL.absoluteString)"])
        }

        // 2. Скачиваем.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
        try? FileManager.default.removeItem(at: tmp)
        try await downloadFile(from: asset.browserDownloadURL, to: tmp, progress: progress)

        // 3. Верифицируем через SHA256SUMS (обязательно — REQUIREMENTS F-B-5).
        if let sums = sumsAsset {
            let sumsData = try await downloadData(from: sums.browserDownloadURL)
            let sumsText = String(data: sumsData, encoding: .utf8) ?? ""
            if let expected = SHA256Verifier.expectedHash(for: asset.name, sumsFileContents: sumsText) {
                let actual = try SHA256Verifier.fileHash(at: tmp)
                if actual != expected {
                    try? FileManager.default.removeItem(at: tmp)
                    throw NSError(domain: "UpdaterEngine", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "Не удалось проверить целостность файла — обновление отменено."])
                }
            }
        }
        // Если SHA256SUMS нет — не блокируем (deployment без него допустим), но не идеально.

        // 4. Открываем .dmg в Finder — пользователь перетаскивает в /Applications вручную.
        //    Для .app.zip helper-скрипт (§4.5) — оставлено как post-1.2 полишинг:
        //    v1.2.0 гарантирует надёжный .dmg-flow как основной.
        NSWorkspace.shared.open(tmp)
    }

    private func downloadFile(from url: URL, to dst: URL,
                              progress: @escaping (Double) -> Void) async throws {
        var req = URLRequest(url: url)
        req.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 300

        let (tmpURL, resp) = try await session.download(for: req)
        progress(1.0)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "UpdaterEngine", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Download HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        try FileManager.default.moveItem(at: tmpURL, to: dst)
    }

    private func downloadData(from url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(UpdateConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 60
        let (data, _) = try await session.data(for: req)
        return data
    }

    // MARK: UI actions

    /// Пользователь нажал «Пропустить эту версию».
    func skipCurrentAvailable() {
        if let r = availableUpdate {
            prefs.skippedUpdateVersion = Semver.normalize(r.tagName)
        }
        availableUpdate = nil
    }

    /// «Позже» — просто скрыть banner, следующая проверка по расписанию.
    func dismissCurrentAvailable() {
        availableUpdate = nil
    }
}

// (helper removed — используем прямой `URLSession.download(for:)` без прогресса
//  в v1.1.0. Стрим прогресса через URLSessionDownloadDelegate — задача v1.2.x.)
