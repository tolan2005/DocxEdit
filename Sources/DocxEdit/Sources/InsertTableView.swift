//
//  InsertTableView.swift
//  DocxEdit
//
//  Grid-picker для вставки таблицы (R03, v0.1.49) — как в мейнстрим-редакторов.
//  8×8 сетка «мигающих» ячеек; hover подсвечивает N×M выделение, клик — вставляет.
//

import SwiftUI

struct InsertTableView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    private let maxRows = 8
    private let maxCols = 8

    @State private var hoverRows = 0
    @State private var hoverCols = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Вставить таблицу").font(.headline)
            Text(hoverRows > 0 && hoverCols > 0
                 ? "\(hoverCols) × \(hoverRows) таблица"
                 : "Наведите на сетку, чтобы выбрать размер")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                ForEach(0..<maxRows, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<maxCols, id: \.self) { c in
                            let selected = r < hoverRows && c < hoverCols
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside {
                                        hoverRows = r + 1
                                        hoverCols = c + 1
                                    }
                                }
                                .onTapGesture { insert(rows: r + 1, cols: c + 1) }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Вставить \(max(1, hoverCols)) × \(max(1, hoverRows))") {
                    insert(rows: max(1, hoverRows), cols: max(1, hoverCols))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hoverRows == 0 || hoverCols == 0)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func insert(rows: Int, cols: Int) {
        controller.insertTable(rows: rows, cols: cols)
        onClose()
    }
}
