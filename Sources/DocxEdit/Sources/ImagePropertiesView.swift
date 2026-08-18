//
//  ImagePropertiesView.swift
//  DocxEdit
//
//  Диалог «Свойства изображения» (v0.1.60, R03): ширина в сантиметрах, alt-text
//  (замещающий текст для accessibility, пишется в `<wp:docPr descr="…">`).
//  Высота автоматически пересчитывается по пропорциям при смене ширины.
//

import SwiftUI
import DocxCore

struct ImagePropertiesView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var widthCm: Double = 8.0
    @State private var altText: String = ""
    @State private var alignment: NSTextAlignment = .left
    @State private var wrap: InlineImageWrap = .inline
    @State private var originalWidthPt: CGFloat = 0
    @State private var originalHeightPt: CGFloat = 0
    @State private var didLoad = false

    private let ptPerCm: Double = 28.3465  // 72 pt/inch ÷ 2.54 cm/inch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Свойства изображения")
                .font(.headline)

            // v1.2.5: заменили Form → VStack. Form на macOS расширяет свою ширину
            // под собственный grid, VStack растёт под неё, и .frame(width: 480)
            // на родителе центрирует overflow, из-за чего заголовок «Свойства
            // изображения» уезжал влево за пределы окна. Фиксированные ширины
            // строк дают детерминированную раскладку в пределах 448pt (480 - 2×16 padding).
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Ширина:")
                        .frame(width: 130, alignment: .trailing)
                    TextField("", value: $widthCm, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Stepper("", value: $widthCm, in: 0.5...30.0, step: 0.5)
                        .labelsHidden()
                    Text("см")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("Выравнивание:")
                        .frame(width: 130, alignment: .trailing)
                    Picker("", selection: $alignment) {
                        Image(systemName: "text.alignleft").tag(NSTextAlignment.left)
                        Image(systemName: "text.aligncenter").tag(NSTextAlignment.center)
                        Image(systemName: "text.alignright").tag(NSTextAlignment.right)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("Обтекание:")
                        .frame(width: 130, alignment: .trailing)
                    Picker("", selection: $wrap) {
                        Text("В тексте").tag(InlineImageWrap.inline)
                        Text("Прямоугольник").tag(InlineImageWrap.square)
                        Text("По контуру").tag(InlineImageWrap.tight)
                        Text("Сверху и снизу").tag(InlineImageWrap.topAndBottom)
                        Text("За текстом").tag(InlineImageWrap.behindText)
                        Text("Перед текстом").tag(InlineImageWrap.inFrontOfText)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("Замещающий текст:")
                        .frame(width: 130, alignment: .trailing)
                    TextEditor(text: $altText)
                        .font(.body)
                        .frame(width: 300, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // v0.1.98: поворот и зеркало — bake в bitmap (никакого angle-поля в модели).
            HStack(spacing: 8) {
                Text("Поворот:").frame(width: 130, alignment: .trailing)
                rotateButton(icon: "rotate.left", tip: "Против часовой (90° CCW)") {
                    controller.rotateImageAtCaret(degreesCW: -90)
                    reloadDimensions()
                }
                rotateButton(icon: "rotate.right", tip: "По часовой (90° CW)") {
                    controller.rotateImageAtCaret(degreesCW: 90)
                    reloadDimensions()
                }
                rotateButton(icon: "arrow.triangle.2.circlepath", tip: "180°") {
                    controller.rotateImageAtCaret(degreesCW: 180)
                    reloadDimensions()
                }
                rotateButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                             tip: "Отразить по горизонтали") {
                    controller.flipImageAtCaretHorizontal()
                }
                Spacer()
            }

            Text("Замещающий текст используется программами чтения с экрана и сохраняется в DOCX как `<wp:docPr descr>`. Пропорции сохраняются при изменении ширины. Поворот и отражение сразу применяются к содержимому изображения (bake в bitmap) — сохраняются в DOCX как обычный PNG.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Удалить изображение", role: .destructive) {
                    controller.deleteImageAtCaret()
                    onClose()
                }
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480, height: 500, alignment: .topLeading)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let props = controller.imagePropertiesAtCaret() {
                originalWidthPt = props.widthPt
                originalHeightPt = props.heightPt
                widthCm = Double(props.widthPt) / ptPerCm
                altText = props.altText
                alignment = props.alignment
                wrap = controller.imageWrapAtCaret()
            }
        }
    }

    private func apply() {
        let widthPt = CGFloat(widthCm * ptPerCm)
        controller.updateImageAtCaret(newWidthPt: widthPt, newHeightPt: 0, newAltText: altText)
        controller.setImageWrapAtCaret(wrap)
        controller.applyAlignment(alignment)
        onClose()
    }

    /// После поворота 90° ширина/высота меняются местами — обновляем поле «Ширина»
    /// и запомненные пропорции, чтобы дальше пропорции пересчитывались корректно.
    private func reloadDimensions() {
        if let props = controller.imagePropertiesAtCaret() {
            originalWidthPt = props.widthPt
            originalHeightPt = props.heightPt
            widthCm = Double(props.widthPt) / ptPerCm
        }
    }

    @ViewBuilder
    private func rotateButton(icon: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}
