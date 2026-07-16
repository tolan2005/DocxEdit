// TablePropertiesView.swift — диалог свойств таблицы (v0.1.51, R03).
//
// Открывается из меню Вставка → «Свойства таблицы…» или кнопки на ribbon.
// Управляет: границы (вкл/выкл + цвет + толщина), заливка ТЕКУЩЕЙ ячейки,
// ширина ТЕКУЩЕЙ колонки. Правки применяются мгновенно через
// `DocumentController.setTableBorders`/`setCellBackground`/`setColumnWidth` —
// каждый вызов = один атомарный replaceCharacters (один шаг undo).

import SwiftUI
import AppKit
import DocxCore

struct TablePropertiesView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var hasBorders: Bool = true
    @State private var borderColor: Color = .gray
    @State private var borderWidth: Double = 0.5

    @State private var tableAlignment: DocxCore.TableAlignment = .left
    @State private var initialTableAlignment: DocxCore.TableAlignment = .left

    @State private var cellFill: Color = .clear
    @State private var cellHasFill: Bool = false

    @State private var columnWidthCm: Double = 3.5
    @State private var columnAutoWidth: Bool = true

    @State private var initialized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: Границы
            GroupBox("Границы таблицы") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Показывать границы", isOn: $hasBorders)
                        .onChange(of: hasBorders) { _ in applyBorders() }
                    // v0.1.91: секции всегда видимы (dimmed вместо if) — окно диалога
                    // теперь фиксированного размера (фикс краша NSHostingController),
                    // условное раскрытие меняло бы высоту контента и клипалось.
                    HStack(spacing: 8) {
                        Text("Цвет")
                        Spacer()
                        ColorPicker("", selection: $borderColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44)
                            .onChange(of: borderColor) { _ in applyBorders() }
                    }
                    .disabled(!hasBorders)
                    .opacity(hasBorders ? 1 : 0.4)
                    HStack(spacing: 8) {
                        Text("Толщина линии")
                        Spacer()
                        Stepper(value: $borderWidth, in: 0.25...5.0, step: 0.25) {
                            Text(String(format: "%.2f pt", borderWidth))
                                .monospacedDigit()
                                .frame(width: 68, alignment: .trailing)
                        }
                        .onChange(of: borderWidth) { _ in applyBorders() }
                    }
                    .disabled(!hasBorders)
                    .opacity(hasBorders ? 1 : 0.4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // MARK: Выравнивание таблицы на странице (v0.1.70; v0.1.76 — plain buttons вместо Picker segmented)
            GroupBox("Выравнивание на странице") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        alignButton(.left,   icon: "text.alignleft")
                        alignButton(.center, icon: "text.aligncenter")
                        alignButton(.right,  icon: "text.alignright")
                        Spacer()
                    }
                    Text("Применяется при закрытии диалога. Работает, когда таблица уже суммарной шириной колонок не на всю страницу.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // MARK: Заливка ячейки
            GroupBox("Ячейка (текущая)") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Заливка ячейки", isOn: $cellHasFill)
                        .onChange(of: cellHasFill) { _ in applyCellFill() }
                    HStack(spacing: 8) {
                        Text("Цвет заливки")
                        Spacer()
                        ColorPicker("", selection: $cellFill, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 44)
                            .onChange(of: cellFill) { _ in applyCellFill() }
                    }
                    .disabled(!cellHasFill)
                    .opacity(cellHasFill ? 1 : 0.4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // MARK: Ширина колонки
            GroupBox("Колонка (текущая)") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Автоматическая ширина", isOn: $columnAutoWidth)
                        .onChange(of: columnAutoWidth) { _ in applyColumnWidth() }
                    HStack(spacing: 8) {
                        Text("Ширина")
                        Spacer()
                        Stepper(value: $columnWidthCm, in: 0.5...20.0, step: 0.25) {
                            Text(String(format: "%.2f см", columnWidthCm))
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .onChange(of: columnWidthCm) { _ in applyColumnWidth() }
                    }
                    .disabled(columnAutoWidth)
                    .opacity(columnAutoWidth ? 0.4 : 1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Закрыть", action: closeAndApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { loadFromCurrent() }
    }

    private func loadFromCurrent() {
        guard let info = controller.currentTableInfo() else {
            onClose()
            return
        }
        hasBorders = info.style.hasBorders
        if let bc = info.style.borderColor {
            borderColor = Color(NSColor(srgbRed: bc.red, green: bc.green, blue: bc.blue, alpha: bc.alpha))
        } else {
            borderColor = Color(NSColor(white: 0.6, alpha: 1))
        }
        borderWidth = Double(max(0.25, info.style.borderWidth))
        let curAlign = controller.currentTableAlignment() ?? .left
        tableAlignment = curAlign
        initialTableAlignment = curAlign
        if let bg = info.cellBackground {
            cellFill = Color(NSColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: bg.alpha))
            cellHasFill = true
        } else {
            cellFill = .yellow
            cellHasFill = false
        }
        if let w = info.columnWidth, w > 0 {
            columnAutoWidth = false
            columnWidthCm = Double(w / 28.3465) // pt → cm
        } else {
            columnAutoWidth = true
            columnWidthCm = 3.5
        }
        initialized = true
    }

    /// Кнопка выравнивания таблицы — стиль ADR-013 (plain button + явный frame + background).
    /// НЕ вызывает mutateCurrentTable сразу — только обновляет @State. Applied on close.
    @ViewBuilder
    private func alignButton(_ value: DocxCore.TableAlignment, icon: String) -> some View {
        let isOn = tableAlignment == value
        Button {
            tableAlignment = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor.opacity(0.25) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyTableAlignment() {
        guard initialized else { return }
        controller.setTableAlignment(tableAlignment)
    }

    /// Закрывает диалог; если alignment таблицы изменился — применяет ПОСЛЕ
    /// того как окно закрыто и layout-цикл SwiftUI завершён. Live-onChange
    /// приводил к «attempting to update layout during layout» краху из-за того,
    /// что `nsTable.setContentWidth`/`setWidth(_:for:.margin:)` в appendTable
    /// меняли геометрию главного окна во время layout-цикла окна диалога.
    private func closeAndApply() {
        let willChange = tableAlignment != initialTableAlignment && initialized
        onClose()
        if willChange {
            DispatchQueue.main.async {
                controller.setTableAlignment(tableAlignment)
            }
        }
    }

    private func applyBorders() {
        guard initialized else { return }
        let ns = NSColor(borderColor).usingColorSpace(.sRGB) ?? NSColor.gray
        controller.setTableBorders(hasBorders: hasBorders, color: ns, width: CGFloat(borderWidth))
    }

    private func applyCellFill() {
        guard initialized else { return }
        if cellHasFill {
            let ns = NSColor(cellFill).usingColorSpace(.sRGB) ?? NSColor.yellow
            controller.setCellBackground(ns)
        } else {
            controller.setCellBackground(nil)
        }
    }

    private func applyColumnWidth() {
        guard initialized else { return }
        if columnAutoWidth {
            controller.setColumnWidth(nil)
        } else {
            let pt = CGFloat(columnWidthCm * 28.3465)
            controller.setColumnWidth(pt)
        }
    }
}
