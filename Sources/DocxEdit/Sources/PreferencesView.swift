//
//  PreferencesView.swift
//  DocxEdit
//
//  Окно настроек (Cmd+,). v0.1.4.
//

import SwiftUI
import AppKit
import DocxCore

struct PreferencesView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    @State private var newFavFont = ""
    @State private var selectedFavIndex: Int? = nil

    private let allFonts = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Основные", systemImage: "gearshape") }
            fontsTab
                .tabItem { Label("Шрифты", systemImage: "textformat") }
            pageTab
                .tabItem { Label("Страница", systemImage: "doc.text") }
            DefaultAppsSettingsView()
                .tabItem { Label("По умолчанию", systemImage: "star") }
        }
        .padding()
        .frame(width: 520, height: 420)
    }

    // MARK: - Основные

    private var generalTab: some View {
        Form {
            Section("Документ по умолчанию") {
                HStack {
                    Text("Размер шрифта")
                    Spacer()
                    Stepper(value: $prefs.defaultFontSize, in: 6...144, step: 1) {
                        Text("\(Int(prefs.defaultFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text("Семейство шрифта задаётся на вкладке «Шрифты» (отдельно для «Обычный» и «Заголовки»).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Правописание") {
                Toggle("Автоопределение языка проверки орфографии",
                       isOn: $prefs.autoDetectSpellLanguage)
                Text("Определяет язык текущего абзаца (RU/EN) и переключает словарь проверки орфографии автоматически.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Обновления") {
                Picker("Проверять обновления", selection: $prefs.updateCheckFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                Text("Автоматически ищет новые релизы на GitHub (\(UpdateConfig.owner)/\(UpdateConfig.repo)). При «Никогда» сетевых запросов не делает; ручная проверка — в меню DocxEdit → «Проверить обновления…».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let last = prefs.lastUpdateCheck {
                    Text("Последняя проверка: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Шрифты (избранные)

    private var fontsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Избранные шрифты отображаются первыми в списке выбора шрифта.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(selection: $selectedFavIndex) {
                ForEach(Array(prefs.favoriteFonts.enumerated()), id: \.offset) { idx, name in
                    Text(name)
                        .font(NSFont(name: name, size: 14).map { Font(($0 as CTFont)) } ?? .body)
                        .tag(idx)
                }
                .onDelete { prefs.favoriteFonts.remove(atOffsets: $0) }
                .onMove  { prefs.favoriteFonts.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            .frame(minHeight: 140)

            HStack {
                Picker("", selection: $newFavFont) {
                    Text("Выберите шрифт…").tag("")
                    ForEach(allFonts.filter { !prefs.favoriteFonts.contains($0) }, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                Button("Добавить") {
                    guard !newFavFont.isEmpty,
                          !prefs.favoriteFonts.contains(newFavFont) else { return }
                    prefs.favoriteFonts.append(newFavFont)
                    newFavFont = ""
                }
                .disabled(newFavFont.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    if let i = selectedFavIndex {
                        prefs.favoriteFonts.remove(at: i)
                        selectedFavIndex = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedFavIndex == nil)
            }

            Divider()

            Text("Шрифты для стилей")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Шрифт «Обычный»:")
                    .frame(width: 140, alignment: .leading)
                Picker("", selection: $prefs.defaultFontName) {
                    // Показываем «Избранные», затем «Все» — как в основном пикере тулбара.
                    Section("Избранные") {
                        ForEach(prefs.favoriteFonts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Section("Все шрифты") {
                        ForEach(allFonts, id: \.self) { Text($0).tag($0) }
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }

            HStack {
                Text("Шрифт заголовков:")
                    .frame(width: 140, alignment: .leading)
                Picker("", selection: Binding<String>(
                    get: { prefs.headingFontName ?? "" },
                    set: { prefs.headingFontName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("(как у «Обычный»)").tag("")
                    ForEach(prefs.favoriteFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            Text("«Обычный» — семейство шрифта для основного текста и стиля «Обычный». «Заголовки» — для стилей Заголовок 1–6; если не выбран, используется шрифт «Обычного».")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Страница

    private let pointsPerCm: CGFloat = 28.3465

    private var marginPreset: String {
        let m = prefs.defaultPageSettings.margins
        if m == .standard { return "standard" }
        if m == .narrow   { return "narrow" }
        if m == .wide     { return "wide" }
        return "custom"
    }

    private var pageTab: some View {
        Form {
            Section("Бумага") {
                HStack {
                    Text("Формат")
                    Spacer()
                    Picker("", selection: $prefs.defaultPageSettings.paperSize) {
                        ForEach(PaperSize.allCases.filter { $0 != .custom }, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .frame(width: 120)
                    .labelsHidden()
                }
                HStack {
                    Text("Ориентация")
                    Spacer()
                    Picker("", selection: $prefs.defaultPageSettings.orientation) {
                        Text("Книжная").tag(PageOrientation.portrait)
                        Text("Альбомная").tag(PageOrientation.landscape)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .labelsHidden()
                }
            }
            Section("Поля") {
                HStack {
                    Text("Пресет")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { marginPreset },
                        set: { preset in
                            switch preset {
                            case "standard": prefs.defaultPageSettings.margins = .standard
                            case "narrow":   prefs.defaultPageSettings.margins = .narrow
                            case "wide":     prefs.defaultPageSettings.margins = .wide
                            default: break
                            }
                        }
                    )) {
                        Text("Стандартные (2/3 см)").tag("standard")
                        Text("Узкие (1.27 см)").tag("narrow")
                        Text("Широкие (2.54/5 см)").tag("wide")
                        Text("Пользовательские").tag("custom")
                    }
                    .frame(width: 200)
                    .labelsHidden()
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Верхнее (см)")
                        marginField($prefs.defaultPageSettings.margins.top)
                        Text("Нижнее (см)")
                        marginField($prefs.defaultPageSettings.margins.bottom)
                    }
                    GridRow {
                        Text("Левое (см)")
                        marginField($prefs.defaultPageSettings.margins.left)
                        Text("Правое (см)")
                        marginField($prefs.defaultPageSettings.margins.right)
                    }
                    Toggle("Зеркальные поля (для брошюр)",
                           isOn: $prefs.defaultPageSettings.mirrorMargins)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func marginField(_ binding: Binding<CGFloat>) -> some View {
        let cmBinding = Binding<Double>(
            get: { Double(binding.wrappedValue / pointsPerCm) },
            set: { binding.wrappedValue = CGFloat($0) * pointsPerCm }
        )
        return TextField("", value: cmBinding, format: .number.precision(.fractionLength(2)))
            .multilineTextAlignment(.trailing)
            .frame(width: 60)
            .textFieldStyle(.squareBorder)
    }
}
