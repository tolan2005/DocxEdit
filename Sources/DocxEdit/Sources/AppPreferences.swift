//
//  AppPreferences.swift
//  DocxEdit
//
//  Централизованные настройки приложения (UserDefaults-backed).
//  v0.1.4: избранные шрифты, шрифт/размер по умолчанию, недавние шрифты.
//

import Foundation
import Combine
import DocxCore

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    // MARK: - Избранные шрифты

    @Published var favoriteFonts: [String] {
        didSet { UserDefaults.standard.set(favoriteFonts, forKey: Keys.favoriteFonts) }
    }

    // MARK: - Недавние шрифты (последние 10 использованных)

    @Published private(set) var recentFonts: [String] = []

    func noteUsedFont(_ name: String) {
        var list = recentFonts.filter { $0 != name }
        list.insert(name, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentFonts = list
        UserDefaults.standard.set(list, forKey: Keys.recentFonts)
    }

    // MARK: - Шрифт и размер по умолчанию

    @Published var defaultFontName: String {
        didSet { UserDefaults.standard.set(defaultFontName, forKey: Keys.defaultFontName) }
    }

    @Published var defaultFontSize: Double {
        didSet { UserDefaults.standard.set(defaultFontSize, forKey: Keys.defaultFontSize) }
    }

    /// Шрифт для стандартных стилей заголовков (Заголовок 1–6).
    /// nil / пустая строка — использовать `defaultFontName`.
    @Published var headingFontName: String? {
        didSet {
            let v = (headingFontName?.isEmpty ?? true) ? nil : headingFontName
            UserDefaults.standard.set(v, forKey: Keys.headingFontName)
        }
    }

    // MARK: - Параметры страницы по умолчанию

    @Published var defaultPageSettings: PageSettings {
        didSet {
            if let data = try? JSONEncoder().encode(defaultPageSettings) {
                UserDefaults.standard.set(data, forKey: Keys.defaultPageSettings)
            }
            // v0.1.56: пробрасываем изменение в текущую сессию, чтобы открытый
            // документ сразу поменял ориентацию/поля/формат (иначе новые настройки
            // применяются только к новым документам — user это не ожидает).
            // Coordinator DocumentWindowView слушает и вызывает applyPageViewStyle.
            NotificationCenter.default.post(
                name: Notification.Name("docxEditPageSettingsChanged"),
                object: defaultPageSettings
            )
        }
    }

    // MARK: - Правописание (v0.3.1)

    /// Автопереключение языка проверки орфографии по содержимому абзаца.
    @Published var autoDetectSpellLanguage: Bool {
        didSet { UserDefaults.standard.set(autoDetectSpellLanguage, forKey: Keys.autoDetectSpellLanguage) }
    }

    /// v0.3.2: пользовательский словарь — слова, которые spell checker
    /// должен считать корректными. Применяется через `NSSpellChecker.learnWord`
    /// при старте контроллера и при каждом изменении списка.
    @Published var customDictionary: [String] {
        didSet { UserDefaults.standard.set(customDictionary, forKey: Keys.customDictionary) }
    }

    // MARK: - Автообновление (v1.1.0, REQUIREMENTS_AUTOUPDATE.md §4.2)

    /// Частота автоматической проверки обновлений.
    @Published var updateCheckFrequency: UpdateCheckFrequency {
        didSet { UserDefaults.standard.set(updateCheckFrequency.rawValue, forKey: Keys.updateCheckFrequency) }
    }

    /// Дата последней (успешной или неудачной) проверки — для соблюдения интервала.
    @Published var lastUpdateCheck: Date? {
        didSet { UserDefaults.standard.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck) }
    }

    /// Версия, которую пользователь явно попросил «пропустить» — не предлагать,
    /// пока не выйдет ещё более новая.
    @Published var skippedUpdateVersion: String? {
        didSet { UserDefaults.standard.set(skippedUpdateVersion, forKey: Keys.skippedUpdateVersion) }
    }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard
        favoriteFonts = ud.stringArray(forKey: Keys.favoriteFonts) ?? ["Roboto", "Montserrat"]
        recentFonts   = ud.stringArray(forKey: Keys.recentFonts)   ?? []
        defaultFontName = ud.string(forKey: Keys.defaultFontName)   ?? "Times New Roman"
        defaultFontSize = ud.object(forKey: Keys.defaultFontSize) as? Double ?? 12.0
        let hf = ud.string(forKey: Keys.headingFontName)
        headingFontName = (hf?.isEmpty ?? true) ? nil : hf
        if let data = ud.data(forKey: Keys.defaultPageSettings),
           let settings = try? JSONDecoder().decode(PageSettings.self, from: data) {
            defaultPageSettings = settings
        } else {
            defaultPageSettings = .a4Portrait
        }
        autoDetectSpellLanguage = (ud.object(forKey: Keys.autoDetectSpellLanguage) as? Bool) ?? true
        customDictionary = ud.stringArray(forKey: Keys.customDictionary) ?? []
        if let raw = ud.string(forKey: Keys.updateCheckFrequency),
           let f = UpdateCheckFrequency(rawValue: raw) {
            updateCheckFrequency = f
        } else {
            updateCheckFrequency = .onLaunch
        }
        lastUpdateCheck = ud.object(forKey: Keys.lastUpdateCheck) as? Date
        skippedUpdateVersion = ud.string(forKey: Keys.skippedUpdateVersion)
    }

    // MARK: - Keys

    private enum Keys {
        static let favoriteFonts      = "pref.favoriteFonts"
        static let recentFonts        = "pref.recentFonts"
        static let defaultFontName    = "pref.defaultFontName"
        static let defaultFontSize    = "pref.defaultFontSize"
        static let headingFontName    = "pref.headingFontName"
        static let defaultPageSettings = "pref.defaultPageSettings"
        static let autoDetectSpellLanguage = "pref.autoDetectSpellLanguage"
        static let customDictionary        = "pref.customDictionary"
        static let updateCheckFrequency    = "pref.updateCheckFrequency"
        static let lastUpdateCheck         = "pref.lastUpdateCheck"
        static let skippedUpdateVersion    = "pref.skippedUpdateVersion"
    }
}

// MARK: - Auto-Update Frequency (v1.1.0)

enum UpdateCheckFrequency: String, CaseIterable, Identifiable {
    case onLaunch = "onLaunch"
    case daily    = "daily"
    case weekly   = "weekly"
    case never    = "never"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onLaunch: return "При запуске"
        case .daily:    return "Раз в день"
        case .weekly:   return "Раз в неделю"
        case .never:    return "Никогда"
        }
    }

    /// Минимальный интервал между автоматическими проверками (nil = никогда авто).
    var interval: TimeInterval? {
        switch self {
        case .onLaunch: return 0
        case .daily:    return 24 * 60 * 60
        case .weekly:   return 7 * 24 * 60 * 60
        case .never:    return nil
        }
    }
}
