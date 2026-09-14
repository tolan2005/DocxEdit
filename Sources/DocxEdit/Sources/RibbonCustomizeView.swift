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

                // Правая колонка — «Избранное»: сверху добавленные (в порядке
                // пользователя, стрелки ↑↓ для reorder), снизу — доступные для добавления.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Группа «Избранное»")
                            .font(.subheadline).bold()
                        Text("Отмеченные команды появятся отдельной группой в конце вкладки «Главная». Стрелки ↑↓ меняют порядок.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !prefs.ribbonFavorites.isEmpty {
                            Text("В избранном").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                            ForEach(Array(prefs.ribbonFavorites.enumerated()), id: \.element) { idx, id in
                                if let cmd = RibbonCommandDef.find(id: id) {
                                    HStack(spacing: 6) {
                                        Label(cmd.title, systemImage: cmd.symbol)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Button {
                                            move(idx, by: -1)
                                        } label: { Image(systemName: "chevron.up") }
                                            .buttonStyle(.borderless)
                                            .disabled(idx == 0)
                                            .help("Переместить вверх")
                                        Button {
                                            move(idx, by: +1)
                                        } label: { Image(systemName: "chevron.down") }
                                            .buttonStyle(.borderless)
                                            .disabled(idx == prefs.ribbonFavorites.count - 1)
                                            .help("Переместить вниз")
                                        Button {
                                            prefs.ribbonFavorites.removeAll { $0 == id }
                                        } label: { Image(systemName: "xmark.circle") }
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(.secondary)
                                            .help("Убрать из избранного")
                                    }
                                }
                            }
                            Divider()
                        }
                        Text("Доступно").font(.caption2).foregroundStyle(.secondary)
                        ForEach(RibbonCommandDef.all.filter { !prefs.ribbonFavorites.contains($0.id) }) { cmd in
                            Button {
                                prefs.ribbonFavorites.append(cmd.id)
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                    Label(cmd.title, systemImage: cmd.symbol)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 300, idealWidth: 340)
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

    /// v1.8.2: переместить элемент избранного на ±1 позицию.
    private func move(_ idx: Int, by delta: Int) {
        var favs = prefs.ribbonFavorites
        let target = idx + delta
        guard idx >= 0, idx < favs.count, target >= 0, target < favs.count else { return }
        favs.swapAt(idx, target)
        prefs.ribbonFavorites = favs
    }
}
