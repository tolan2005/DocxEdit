//
//  HeaderFooterView.swift
//  DocxEdit
//
//  Диалог «Колонтитулы» — текст верхнего/нижнего колонтитула + выравнивание.
//  Плейсхолдеры {page} / {pages} / {date} подставляются при отрисовке листов.
//  v0.2.3: разные колонтитулы для первой страницы и для чётных/нечётных.
//

import SwiftUI
import AppKit
import DocxCore

struct HeaderFooterView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var headerText: String = ""
    @State private var footerText: String = ""
    @State private var headerAlign: DocxCore.TextAlignment = .center
    @State private var footerAlign: DocxCore.TextAlignment = .center

    @State private var differentFirstPage: Bool = false
    @State private var firstHeaderText: String = ""
    @State private var firstFooterText: String = ""
    @State private var firstHeaderAlign: DocxCore.TextAlignment = .center
    @State private var firstFooterAlign: DocxCore.TextAlignment = .center

    @State private var differentOddEven: Bool = false
    @State private var evenHeaderText: String = ""
    @State private var evenFooterText: String = ""
    @State private var evenHeaderAlign: DocxCore.TextAlignment = .center
    @State private var evenFooterAlign: DocxCore.TextAlignment = .center

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Колонтитулы").font(.headline)

                GroupBox("Основной (нечётные страницы)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Верхний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $headerText)
                        alignmentPicker($headerAlign)
                        Divider()
                        Text("Нижний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $footerText)
                        alignmentPicker($footerAlign)
                    }.padding(6)
                }

                Toggle("Первая страница отличается", isOn: $differentFirstPage)
                    .toggleStyle(.checkbox)
                GroupBox("Первая страница") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Верхний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $firstHeaderText)
                        alignmentPicker($firstHeaderAlign)
                        Divider()
                        Text("Нижний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $firstFooterText)
                        alignmentPicker($firstFooterAlign)
                    }.padding(6)
                }
                .disabled(!differentFirstPage)
                .opacity(differentFirstPage ? 1 : 0.4)

                Toggle("Разные для чётных и нечётных страниц", isOn: $differentOddEven)
                    .toggleStyle(.checkbox)
                GroupBox("Чётные страницы") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Верхний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $evenHeaderText)
                        alignmentPicker($evenHeaderAlign)
                        Divider()
                        Text("Нижний").font(.caption).foregroundStyle(.secondary)
                        TextField("Текст", text: $evenFooterText)
                        alignmentPicker($evenFooterAlign)
                    }.padding(6)
                }
                .disabled(!differentOddEven)
                .opacity(differentOddEven ? 1 : 0.4)

                Text("Плейсхолдеры: {page} — номер страницы, {pages} — всего страниц, {date} — дата.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button("Готово") { apply(); onClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 500, height: 620)
        .onAppear {
            let hf = controller.currentHeaderFooter()
            headerText = hf.headerText
            footerText = hf.footerText
            headerAlign = hf.headerAlignment
            footerAlign = hf.footerAlignment
            differentFirstPage = hf.differentFirstPage
            firstHeaderText = hf.firstHeaderText
            firstFooterText = hf.firstFooterText
            firstHeaderAlign = hf.firstHeaderAlignment
            firstFooterAlign = hf.firstFooterAlignment
            differentOddEven = hf.differentOddEven
            evenHeaderText = hf.evenHeaderText
            evenFooterText = hf.evenFooterText
            evenHeaderAlign = hf.evenHeaderAlignment
            evenFooterAlign = hf.evenFooterAlignment
        }
    }

    private func alignmentPicker(_ binding: Binding<DocxCore.TextAlignment>) -> some View {
        Picker("", selection: binding) {
            Text("По левому краю").tag(DocxCore.TextAlignment.left)
            Text("По центру").tag(DocxCore.TextAlignment.center)
            Text("По правому краю").tag(DocxCore.TextAlignment.right)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func apply() {
        controller.setHeaderFooter(HeaderFooter(
            headerText: headerText, footerText: footerText,
            headerAlignment: headerAlign, footerAlignment: footerAlign,
            differentFirstPage: differentFirstPage,
            firstHeaderText: firstHeaderText, firstFooterText: firstFooterText,
            firstHeaderAlignment: firstHeaderAlign, firstFooterAlignment: firstFooterAlign,
            differentOddEven: differentOddEven,
            evenHeaderText: evenHeaderText, evenFooterText: evenFooterText,
            evenHeaderAlignment: evenHeaderAlign, evenFooterAlignment: evenFooterAlign))
    }
}
