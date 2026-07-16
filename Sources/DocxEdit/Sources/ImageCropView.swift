//
//  ImageCropView.swift
//  DocxEdit
//
//  v0.1.101: диалог обрезки изображения. 4 поля в процентах от исходных сторон
//  (сверху / справа / снизу / слева). Bake в bitmap через
//  DocumentController.cropImageAtCaret — один шаг undo, DOCX сохраняет уже
//  обрезанный PNG.
//

import SwiftUI
import AppKit

struct ImageCropView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var topPct: Double = 0
    @State private var rightPct: Double = 0
    @State private var bottomPct: Double = 0
    @State private var leftPct: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Обрезка изображения").font(.headline)
            Text("Значения — проценты от исходных сторон, обрезаемые с соответствующего края.")
                .font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Сверху:")
                    field($topPct)
                    Text("%").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Справа:")
                    field($rightPct)
                    Text("%").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Снизу:")
                    field($bottomPct)
                    Text("%").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Слева:")
                    field($leftPct)
                    Text("%").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Сбросить") {
                    topPct = 0; rightPct = 0; bottomPct = 0; leftPct = 0
                }
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") {
                    controller.cropImageAtCaret(
                        topFrac: topPct / 100,
                        rightFrac: rightPct / 100,
                        bottomFrac: bottomPct / 100,
                        leftFrac: leftPct / 100)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(topPct + bottomPct >= 100 || leftPct + rightPct >= 100)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func field(_ v: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: v, format: .number.precision(.fractionLength(0)))
                .frame(width: 60)
            Stepper("", value: v, in: 0...95, step: 1).labelsHidden()
        }
    }
}
