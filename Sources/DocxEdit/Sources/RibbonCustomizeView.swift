//
//  RibbonCustomizeView.swift
//  DocxEdit (v1.2.0)
//
//  Диалог «Настроить панель инструментов»: скрытие/показ групп ribbon по
//  вкладкам + выбор команд для группы «Избранное» на «Главной».
//  Показывается как SwiftUI .sheet из RibbonView (не NSWindow — правило
//  ADR-039 касается только NSWindow(contentViewController:), sheets безопасны).
//

import SwiftUI

struct RibbonCustomizeView: View {
    @ObservedObject var prefs: AppPreferences
    @Environment(\.dismiss) private var dismiss

    private let tabs = ["Главная", "Вставка", "Разметка", "Таблица", "Обзор", "Вид"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Настройка панели инструментов")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            HSplitView {
                // Левая колонка — группы по вкладкам.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Группы кнопок")
                            .font(.subheadline).bold()
                        Text("Снимите галочку, чтобы скрыть группу с панели.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(tabs, id: \.self) { tab in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab)
                                    .font(.caption).bold()
                                    .foregroundStyle(.secondary)
                                ForEach(RibbonGroupDef.groups(forTab: tab)) { g in
                                    Toggle(g.title, isOn: groupBinding(g.id))
                                        .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 220, idealWidth: 240)

                // Правая колонка — «Избранное».
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Группа «Избранное»")
                            .font(.subheadline).bold()
                        Text("Отмеченные команды появятся отдельной группой в конце вкладки «Главная» — быстрый доступ без переключения вкладок.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(RibbonCommandDef.all) { cmd in
                            Toggle(isOn: favoriteBinding(cmd.id)) {
                                Label(cmd.title, systemImage: cmd.symbol)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 260, idealWidth: 300)
            }

            Divider()

            HStack {
                Button("Сбросить настройки") {
                    prefs.hiddenRibbonGroups = []
                    prefs.ribbonFavorites = []
                }
                Spacer()
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 480)
    }

    /// Binding «группа видима» (инвертирует hiddenRibbonGroups).
    private func groupBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !prefs.hiddenRibbonGroups.contains(id) },
            set: { visible in
                if visible { prefs.hiddenRibbonGroups.remove(id) }
                else       { prefs.hiddenRibbonGroups.insert(id) }
            }
        )
    }

    /// Binding «команда в избранном». Порядок хранится по каталогу.
    private func favoriteBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { prefs.ribbonFavorites.contains(id) },
            set: { on in
                if on {
                    if !prefs.ribbonFavorites.contains(id) {
                        // Вставляем, сохраняя порядок каталога.
                        let ordered = RibbonCommandDef.all.map(\.id)
                        var favs = Set(prefs.ribbonFavorites); favs.insert(id)
                        prefs.ribbonFavorites = ordered.filter { favs.contains($0) }
                    }
                } else {
                    prefs.ribbonFavorites.removeAll { $0 == id }
                }
            }
        )
    }
}
