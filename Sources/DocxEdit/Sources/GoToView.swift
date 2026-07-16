//
//  GoToView.swift
//  DocxEdit
//
//  Диалог «Перейти к…» — переход к номеру страницы/строки/абзаца.
//

import SwiftUI
import AppKit

enum GoToTarget: String, CaseIterable, Identifiable {
    case page      = "Странице"
    case line      = "Строке"
    case paragraph = "Абзацу"
    var id: String { rawValue }
}

struct GoToView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var target: GoToTarget = .page
    @State private var numberText: String = "1"
    @State private var error: String?
    @FocusState private var numberFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Перейти к")
                .font(.headline)

            Picker("К объекту:", selection: $target) {
                ForEach(GoToTarget.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()

            HStack {
                Text("Номер:")
                TextField("", text: $numberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($numberFocused)
                    .onSubmit { perform() }
            }

            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Перейти") { perform() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { numberFocused = true }
    }

    private func perform() {
        guard let n = Int(numberText.trimmingCharacters(in: .whitespaces)), n > 0 else {
            error = "Введите положительный номер"
            return
        }
        let ok = controller.goTo(target: target, number: n)
        if ok {
            onClose()
        } else {
            error = "\(target.rawValue) с номером \(n) не найден\(target == .page ? "а" : "")"
        }
    }
}
