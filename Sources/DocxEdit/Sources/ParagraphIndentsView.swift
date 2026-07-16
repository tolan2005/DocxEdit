//
//  ParagraphIndentsView.swift
//  DocxEdit
//
//  v0.1.94: диалог «Абзац» — отступы левого/правого края и режим первой строки
//  (нет / первая строка / выступ). Все значения — в см; конвертируются в pt
//  для DocumentController.applyParagraphIndents(left:right:special:).
//  Паттерн окна: NSWindow(contentRect:) + NSHostingView(sizingOptions: []) —
//  правило после v0.1.91 (см. ADR-039 п.7), фиксированный размер контента.
//

import SwiftUI
import AppKit

struct ParagraphIndentsView: View {
    @ObservedObject var controller: DocumentController
    var onClose: () -> Void

    enum SpecialMode: Hashable {
        case none, firstLine, hanging
    }

    @State private var leftCm: Double = 0
    @State private var rightCm: Double = 0
    @State private var specialMode: SpecialMode = .none
    @State private var specialCm: Double = 1.25

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Отступы абзаца").font(.headline)

            GroupBox("Отступ") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Слева:").frame(width: 90, alignment: .trailing)
                        TextField("", value: $leftCm, format: .number.precision(.fractionLength(2)))
                            .frame(width: 70)
                        Text("см")
                        Stepper("", value: $leftCm, in: 0...20, step: 0.25).labelsHidden()
                    }
                    HStack {
                        Text("Справа:").frame(width: 90, alignment: .trailing)
                        TextField("", value: $rightCm, format: .number.precision(.fractionLength(2)))
                            .frame(width: 70)
                        Text("см")
                        Stepper("", value: $rightCm, in: 0...20, step: 0.25).labelsHidden()
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Первая строка") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Специальный:").frame(width: 110, alignment: .trailing)
                        Picker("", selection: $specialMode) {
                            Text("(нет)").tag(SpecialMode.none)
                            Text("Отступ первой строки").tag(SpecialMode.firstLine)
                            Text("Выступ").tag(SpecialMode.hanging)
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    HStack {
                        Text("На:").frame(width: 110, alignment: .trailing)
                        TextField("", value: $specialCm, format: .number.precision(.fractionLength(2)))
                            .frame(width: 70)
                        Text("см")
                        Stepper("", value: $specialCm, in: 0...20, step: 0.25).labelsHidden()
                    }
                    .disabled(specialMode == .none)
                    .opacity(specialMode == .none ? 0.4 : 1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") {
                    let cmToPt: (Double) -> CGFloat = { CGFloat($0 * 28.3465) }
                    let special: CGFloat
                    switch specialMode {
                    case .none:      special = 0
                    case .firstLine: special =  cmToPt(specialCm)
                    case .hanging:   special = -cmToPt(specialCm)
                    }
                    controller.applyParagraphIndents(
                        left: cmToPt(leftCm),
                        right: cmToPt(rightCm),
                        special: special
                    )
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            let ptToCm: (CGFloat) -> Double = { pt in (Double(pt) / 28.3465 * 100).rounded() / 100 }
            let (l, r, s) = controller.currentParagraphIndents()
            leftCm = ptToCm(l)
            rightCm = ptToCm(r)
            if s > 0 { specialMode = .firstLine; specialCm = ptToCm(s) }
            else if s < 0 { specialMode = .hanging; specialCm = ptToCm(-s) }
            else { specialMode = .none; specialCm = 1.25 }
        }
    }
}
