//
//  RowHeightView.swift
//  DocxEdit
//
//  v0.1.86: минимальная высота строки таблицы. Отдельный простой диалог,
//  чтобы не трогать TablePropertiesView (крашится, ADR-открытая проблема).
//  v0.1.87: инициализация текущим значением из controller.currentRowHeight.
//

import SwiftUI
import AppKit

struct RowHeightView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    @State private var heightCm: Double = 0.5
    @State private var autoHeight: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Высота строки таблицы").font(.headline)
            Toggle("Автоматическая высота", isOn: $autoHeight)
            if !autoHeight {
                HStack(spacing: 8) {
                    Text("Минимум:")
                    TextField("", value: $heightCm, format: .number.precision(.fractionLength(2)))
                        .frame(width: 80)
                    Text("см")
                    Stepper("", value: $heightCm, in: 0.1...30, step: 0.1)
                        .labelsHidden()
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") {
                    if autoHeight {
                        controller.applyTableEdit(.setRowHeight(nil))
                    } else {
                        // см → pt (1 см = 28.3465 pt)
                        let pt = CGFloat(heightCm * 28.3465)
                        controller.applyTableEdit(.setRowHeight(pt))
                    }
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            // v0.1.89: если явная высота задана — снимаем автогалку и показываем её.
            // Если нет — оставляем автогалку, но prefill'им поле ФАКТИЧЕСКОЙ визуальной
            // высотой (из layout manager). Пользователь увидит текущее значение сразу
            // при снятии галки, независимо от того, задавал он высоту раньше или строка
            // выросла от содержимого.
            let ptToCm: (CGFloat) -> Double = { pt in (Double(pt) / 28.3465 * 100).rounded() / 100 }
            if let pt = controller.currentRowHeight, pt > 0 {
                autoHeight = false
                heightCm = ptToCm(pt)
            } else if let visualPt = controller.currentRowVisualHeight(), visualPt > 0 {
                autoHeight = true
                heightCm = ptToCm(visualPt)
            } else {
                autoHeight = true
                heightCm = 0.5
            }
        }
    }
}
