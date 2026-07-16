//
//  MergeCellsView.swift
//  DocxEdit
//
//  Диалог объединения ячеек через сетку (v0.1.65). NSTextView не умеет
//  прямоугольное выделение, поэтому вертикальный/прямоугольный merge невозможно
//  задать выделением текста. Здесь ячейка-курсор — якорь; наведение/клик по
//  второму углу задаёт прямоугольник, «Объединить» — сливает его.
//

import SwiftUI

struct MergeCellsView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var rows = 0
    @State private var cols = 0
    @State private var anchorRow = 0
    @State private var anchorCol = 0
    @State private var hoverRow = -1
    @State private var hoverCol = -1
    @State private var didLoad = false

    // Прямоугольник от якоря до наведённой (или, если нет hover, до якоря).
    private var rect: (minR: Int, maxR: Int, minC: Int, maxC: Int) {
        let tr = hoverRow >= 0 ? hoverRow : anchorRow
        let tc = hoverCol >= 0 ? hoverCol : anchorCol
        return (min(anchorRow, tr), max(anchorRow, tr), min(anchorCol, tc), max(anchorCol, tc))
    }

    private var selectionIsValid: Bool {
        let r = rect
        return (r.maxR > r.minR) || (r.maxC > r.minC)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Объединить ячейки").font(.headline)
            Text("Ячейка с курсором — начальная (синяя рамка). Наведите на противоположный угол и нажмите «Объединить».")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows > 0 && cols > 0 {
                grid
                Text(sizeLabel)
                    .font(.subheadline)
                    .foregroundStyle(selectionIsValid ? .primary : .secondary)
            } else {
                Text("Курсор не в таблице.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Объединить") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!selectionIsValid)
            }
        }
        .padding(16)
        .frame(minWidth: 320)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let info = controller.tableGridInfo() {
                rows = info.rows
                cols = info.cols
                anchorRow = info.caretRow
                anchorCol = info.caretCol
            }
        }
    }

    private var sizeLabel: String {
        let r = rect
        let h = r.maxR - r.minR + 1
        let w = r.maxC - r.minC + 1
        if !selectionIsValid { return "Выберите второй угол прямоугольника" }
        return "Объединить \(w) × \(h) (столбцов × строк)"
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<cols, id: \.self) { c in
                        cellView(r: r, c: c)
                    }
                }
            }
        }
    }

    private func cellView(r: Int, c: Int) -> some View {
        let rc = rect
        let inRect = r >= rc.minR && r <= rc.maxR && c >= rc.minC && c <= rc.maxC
        let isAnchor = r == anchorRow && c == anchorCol
        return RoundedRectangle(cornerRadius: 2)
            .fill(inRect ? Color.accentColor.opacity(isAnchor ? 0.55 : 0.35)
                         : Color(nsColor: .controlBackgroundColor))
            .frame(width: 26, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isAnchor ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isAnchor ? 2 : 0.5)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hoverRow = r; hoverCol = c }
            }
            .onTapGesture {
                hoverRow = r; hoverCol = c
                if selectionIsValid { apply() }
            }
    }

    private func apply() {
        let r = rect
        guard selectionIsValid else { return }
        controller.applyTableEdit(.mergeRect(minRow: r.minR, maxRow: r.maxR, minCol: r.minC, maxCol: r.maxC))
        onClose()
    }
}
