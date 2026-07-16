//
//  StylesView.swift
//  DocxEdit
//
//  Диалог «Стили» — редактирование стандартных стилей абзаца (Обычный, Заголовки)
//  и символьных стилей (Strong/Emphasis/Code) на уровне текущего документа.
//  Изменения сохраняются в `DocumentModel.styles` (сериализуются в DOCX styles.xml).
//

import SwiftUI
import AppKit
import DocxCore

struct StylesView: View {
    @ObservedObject var controller: DocumentController
    @ObservedObject var session: DocumentSession
    let onClose: () -> Void

    @State private var selectedId: String = "Normal"

    /// Стили абзаца: стандартные + пользовательские из документа (внешние .docx).
    private var paragraphStyleList: [(id: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for s in StandardParagraphStyle.all { seen.insert(s.id); out.append((s.id, s.def.name)) }
        for (id, def) in session.bridge.model.styles.paragraphStyles.sorted(by: { $0.key < $1.key })
        where !seen.contains(id) {
            out.append((id, def.name))
        }
        return out
    }

    private var characterStyleList: [(id: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for s in StandardCharacterStyle.all { seen.insert(s.id); out.append((s.id, s.def.name)) }
        for (id, def) in session.bridge.model.styles.characterStyles.sorted(by: { $0.key < $1.key })
        where !seen.contains(id) {
            out.append((id, def.name))
        }
        return out
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 220)
            detail
                .frame(minWidth: 380)
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    // MARK: List

    private var list: some View {
        List(selection: $selectedId) {
            Section("Стили абзаца") {
                ForEach(paragraphStyleList, id: \.id) { style in
                    Text(style.name).tag(style.id)
                }
            }
            Section("Стили знака") {
                ForEach(characterStyleList, id: \.id) { style in
                    Text(style.name).tag(style.id)
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if characterStyleList.contains(where: { $0.id == selectedId }) {
            characterEditor
        } else if paragraphStyleList.contains(where: { $0.id == selectedId }) {
            paragraphEditor
        } else {
            Text("Выберите стиль").foregroundStyle(.secondary)
        }
    }

    // MARK: Paragraph editor

    private var paragraphEditor: some View {
        let effective = controller.effectiveParagraphStyle(id: selectedId)
        return Form {
            Section {
                LabeledContent("Название", value: effective.name)
                if let base = effective.basedOn {
                    LabeledContent("Основан на", value: base)
                }
            }
            Section("Шрифт") {
                Picker("Семейство:", selection: paragraphFontBinding(effective)) {
                    Text("(по умолчанию из настроек)").tag(String?.none)
                    Divider()
                    ForEach(AppPreferences.shared.favoriteFonts, id: \.self) { name in
                        Text(name).tag(String?(name))
                    }
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { name in
                        Text(name).tag(String?(name))
                    }
                }
                .pickerStyle(.menu)

                Stepper(value: paragraphIntBinding(get: { Int(effective.fontSize ?? 12) }, set: { $0.fontSize = CGFloat($1) }),
                        in: 6...96) {
                    Text("Размер: \(Int(effective.fontSize ?? 12)) pt")
                }
                Toggle("Полужирный", isOn: paragraphBoolBinding(
                    get: { effective.bold ?? false },
                    set: { $0.bold = $1 }))
                Toggle("Курсив", isOn: paragraphBoolBinding(
                    get: { effective.italic ?? false },
                    set: { $0.italic = $1 }))
            }
            Section("Цвета") {
                colorRow("Цвет текста",
                         color: colorBinding(get: { effective.textColor }, set: { $0.textColor = $1 }))
                colorRow("Цвет заливки",
                         color: colorBinding(get: { effective.backgroundColor }, set: { $0.backgroundColor = $1 }))
            }
            Section("Абзац") {
                Picker("Выравнивание:", selection: paragraphAlignmentBinding(effective)) {
                    Text("(по умолчанию)").tag(DocxCore.TextAlignment?.none)
                    Divider()
                    Text("По левому краю").tag(DocxCore.TextAlignment?(.left))
                    Text("По центру").tag(DocxCore.TextAlignment?(.center))
                    Text("По правому краю").tag(DocxCore.TextAlignment?(.right))
                    Text("По ширине").tag(DocxCore.TextAlignment?(.justify))
                }
                .pickerStyle(.menu)
            }
            Section("Интервалы (pt)") {
                HStack {
                    Text("До абзаца:")
                    TextField("", value: paragraphDoubleBinding(get: { Double(effective.spaceBefore ?? 0) }, set: { $0.spaceBefore = CGFloat($1) }),
                              format: .number)
                        .frame(width: 60)
                }
                HStack {
                    Text("После абзаца:")
                    TextField("", value: paragraphDoubleBinding(get: { Double(effective.spaceAfter ?? 0) }, set: { $0.spaceAfter = CGFloat($1) }),
                              format: .number)
                        .frame(width: 60)
                }
            }
            Section {
                HStack {
                    Button("Сбросить к стандарту") {
                        controller.resetParagraphStyle(id: selectedId)
                    }
                    Spacer()
                    Button("Закрыть") { onClose() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Character editor

    private var characterEditor: some View {
        let effective = controller.effectiveCharacterStyle(id: selectedId)
        return Form {
            LabeledContent("Название", value: effective.name)
            Section("Шрифт") {
                Picker("Семейство:", selection: characterFontBinding(effective)) {
                    Text("(унаследовать)").tag(String?.none)
                    Divider()
                    ForEach(AppPreferences.shared.favoriteFonts, id: \.self) { name in
                        Text(name).tag(String?(name))
                    }
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { name in
                        Text(name).tag(String?(name))
                    }
                }
                .pickerStyle(.menu)

                Toggle("Полужирный", isOn: characterBoolBinding(
                    get: { effective.bold }, set: { $0.bold = $1 }))
                Toggle("Курсив", isOn: characterBoolBinding(
                    get: { effective.italic }, set: { $0.italic = $1 }))
                Stepper(value: characterIntBinding(
                    get: { Int(effective.fontSize ?? 12) },
                    set: { $0.fontSize = CGFloat($1) }
                ), in: 6...96) {
                    Text("Размер: \(Int(effective.fontSize ?? 12)) pt")
                }
            }
            Section {
                HStack {
                    Button("Сбросить к стандарту") {
                        controller.resetCharacterStyle(id: selectedId)
                    }
                    Spacer()
                    Button("Закрыть") { onClose() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Bindings helpers — paragraph

    private func paragraphIntBinding(get: @escaping () -> Int,
                                     set: @escaping (inout ParagraphStyleDef, Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: { new in mutateParagraph { set(&$0, new) } })
    }

    private func paragraphDoubleBinding(get: @escaping () -> Double,
                                        set: @escaping (inout ParagraphStyleDef, Double) -> Void) -> Binding<Double> {
        Binding(get: get, set: { new in mutateParagraph { set(&$0, new) } })
    }

    private func paragraphBoolBinding(get: @escaping () -> Bool,
                                      set: @escaping (inout ParagraphStyleDef, Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { new in mutateParagraph { set(&$0, new) } })
    }

    private func paragraphFontBinding(_ effective: ParagraphStyleDef) -> Binding<String?> {
        Binding(
            get: { effective.fontName },
            set: { new in mutateParagraph { $0.fontName = new } })
    }

    private func paragraphAlignmentBinding(_ effective: ParagraphStyleDef) -> Binding<DocxCore.TextAlignment?> {
        Binding(
            get: { effective.alignment },
            set: { new in mutateParagraph { $0.alignment = new } })
    }

    private func mutateParagraph(_ mutate: (inout ParagraphStyleDef) -> Void) {
        var current = controller.effectiveParagraphStyle(id: selectedId)
        mutate(&current)
        controller.overrideParagraphStyle(id: selectedId, def: current)
    }

    // MARK: Bindings helpers — character

    private func characterIntBinding(get: @escaping () -> Int,
                                     set: @escaping (inout CharacterStyleDef, Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: { new in mutateCharacter { set(&$0, new) } })
    }

    private func characterBoolBinding(get: @escaping () -> Bool,
                                      set: @escaping (inout CharacterStyleDef, Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { new in mutateCharacter { set(&$0, new) } })
    }

    private func characterFontBinding(_ effective: CharacterStyleDef) -> Binding<String?> {
        Binding(
            get: { effective.fontName },
            set: { new in mutateCharacter { $0.fontName = new } })
    }

    private func mutateCharacter(_ mutate: (inout CharacterStyleDef) -> Void) {
        var current = controller.effectiveCharacterStyle(id: selectedId)
        mutate(&current)
        controller.overrideCharacterStyle(id: selectedId, def: current)
    }

    // MARK: Color helpers

    private func colorRow(_ label: String, color: Binding<CodableColor?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            ColorWellButton(color: color)
            if color.wrappedValue != nil {
                Button {
                    color.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Убрать цвет")
            }
        }
    }

    private func colorBinding(get: @escaping () -> CodableColor?,
                              set: @escaping (inout ParagraphStyleDef, CodableColor?) -> Void) -> Binding<CodableColor?> {
        Binding(get: get, set: { new in mutateParagraph { set(&$0, new) } })
    }
}

/// Обёртка NSColorWell для SwiftUI, работающая с `CodableColor?`.
private struct ColorWellButton: NSViewRepresentable {
    @Binding var color: CodableColor?

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = color.map { NSColor(calibratedRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) } ?? .clear
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        let target = color.map { NSColor(calibratedRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) } ?? .clear
        if nsView.color != target { nsView.color = target }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let owner: ColorWellButton
        init(_ owner: ColorWellButton) { self.owner = owner }
        @objc func colorChanged(_ well: NSColorWell) {
            let c = well.color.usingColorSpace(.sRGB) ?? well.color
            owner.color = CodableColor(red: c.redComponent, green: c.greenComponent,
                                       blue: c.blueComponent, alpha: c.alphaComponent)
        }
    }
}
