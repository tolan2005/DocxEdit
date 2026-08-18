//
//  ImageCropView.swift
//  DocxEdit
//
//  v1.2.4: визуальная обрезка изображения. Показывает исходное изображение
//  с полупрозрачным затемнением обрезаемой области и 4 драг-углами (drag corners).
//  Внутренне работает с нормализованным `crop: CGRect` (0..1) в системе координат
//  изображения (top-left origin). При Применить транслируется в `top/right/bottom/left`
//  фракции и передаётся в `DocumentController.cropImageAtCaret` (bake в bitmap,
//  один шаг undo, DOCX сохраняет уже обрезанный PNG).
//

import SwiftUI
import AppKit

struct ImageCropView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var image: NSImage?
    /// Нормализованный crop-прямоугольник в пространстве изображения (top-left origin, 0..1).
    @State private var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var didLoad = false

    /// Максимум по большей стороне для превью (px в экранных единицах).
    private let maxDisplay: CGFloat = 380
    /// Минимальный размер crop-прямоугольника (нормализованно).
    private let minCrop: CGFloat = 0.05
    private let handleSize: CGFloat = 14

    var body: some View {
        VStack(spacing: 12) {
            Text("Обрезка изображения").font(.headline)
            Text("Перетаскивайте углы прямоугольника, чтобы выбрать видимую область изображения.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                Color(NSColor.controlBackgroundColor)
                if let image {
                    cropCanvas(for: image)
                } else {
                    Text("Курсор не на изображении.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 420, height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            HStack {
                Button("Сбросить") {
                    crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
                .disabled(image == nil)
                Spacer()
                Button("Отмена") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Применить") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(image == nil
                              || crop.width < minCrop
                              || crop.height < minCrop
                              || (crop.width >= 0.999 && crop.height >= 0.999))
            }
        }
        .padding(16)
        .frame(width: 460, height: 540)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            image = controller.imageAtCaret()
        }
    }

    // MARK: - Canvas

    private func cropCanvas(for image: NSImage) -> some View {
        let imgSize = image.size
        let aspect = max(0.01, imgSize.width) / max(0.01, imgSize.height)
        let box: CGSize = {
            // Вписываем в квадрат 380x380, сохраняя пропорции.
            if aspect >= 1 { return CGSize(width: maxDisplay, height: maxDisplay / aspect) }
            return CGSize(width: maxDisplay * aspect, height: maxDisplay)
        }()

        return ZStack(alignment: .topLeading) {
            // Полный шахматный фон под прозрачные PNG.
            CheckerboardView()
                .frame(width: box.width, height: box.height)

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: box.width, height: box.height)

            // Затемнение обрезаемой области — 4 прямоугольника по краям crop.
            dimOverlay(box: box)

            // Рамка crop.
            let x = box.width * crop.minX
            let y = box.height * crop.minY
            let w = box.width * crop.width
            let h = box.height * crop.height

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: w, height: h)
                .offset(x: x, y: y)
                .shadow(color: .black.opacity(0.5), radius: 0.5)
                .allowsHitTesting(false)

            // Драг тела прямоугольника (перемещение всего окна кадрирования).
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, w), height: max(0, h))
                .offset(x: x, y: y)
                .gesture(bodyDragGesture(box: box))

            // 4 угла.
            cornerHandle(at: CGPoint(x: x,     y: y),     corner: .topLeft,     box: box)
            cornerHandle(at: CGPoint(x: x + w, y: y),     corner: .topRight,    box: box)
            cornerHandle(at: CGPoint(x: x,     y: y + h), corner: .bottomLeft,  box: box)
            cornerHandle(at: CGPoint(x: x + w, y: y + h), corner: .bottomRight, box: box)
        }
        .frame(width: box.width, height: box.height)
    }

    // MARK: - Dim overlay

    private func dimOverlay(box: CGSize) -> some View {
        let dim = Color.black.opacity(0.5)
        let x = box.width * crop.minX
        let y = box.height * crop.minY
        let w = box.width * crop.width
        let h = box.height * crop.height
        return ZStack(alignment: .topLeading) {
            // Верх
            dim.frame(width: box.width, height: max(0, y))
            // Низ
            dim.frame(width: box.width, height: max(0, box.height - (y + h)))
                .offset(x: 0, y: y + h)
            // Лево (только полоса рядом с crop)
            dim.frame(width: max(0, x), height: max(0, h))
                .offset(x: 0, y: y)
            // Право
            dim.frame(width: max(0, box.width - (x + w)), height: max(0, h))
                .offset(x: x + w, y: y)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Handles

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func cornerHandle(at pos: CGPoint, corner: Corner, box: CGSize) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: handleSize, height: handleSize)
            .offset(x: pos.x - handleSize / 2, y: pos.y - handleSize / 2)
            .gesture(handleGesture(corner: corner, box: box))
    }

    private func handleGesture(corner: Corner, box: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let nx = clamp(g.location.x / box.width, 0, 1)
                let ny = clamp(g.location.y / box.height, 0, 1)
                var c = crop
                switch corner {
                case .topLeft:
                    let maxX = c.maxX - minCrop
                    let maxY = c.maxY - minCrop
                    let newX = min(nx, maxX)
                    let newY = min(ny, maxY)
                    c = CGRect(x: newX, y: newY,
                               width: c.maxX - newX, height: c.maxY - newY)
                case .topRight:
                    let minX = c.minX + minCrop
                    let maxY = c.maxY - minCrop
                    let newRight = max(nx, minX)
                    let newY = min(ny, maxY)
                    c = CGRect(x: c.minX, y: newY,
                               width: newRight - c.minX, height: c.maxY - newY)
                case .bottomLeft:
                    let maxX = c.maxX - minCrop
                    let minY = c.minY + minCrop
                    let newX = min(nx, maxX)
                    let newBottom = max(ny, minY)
                    c = CGRect(x: newX, y: c.minY,
                               width: c.maxX - newX, height: newBottom - c.minY)
                case .bottomRight:
                    let minX = c.minX + minCrop
                    let minY = c.minY + minCrop
                    let newRight = max(nx, minX)
                    let newBottom = max(ny, minY)
                    c = CGRect(x: c.minX, y: c.minY,
                               width: newRight - c.minX, height: newBottom - c.minY)
                }
                crop = c
            }
    }

    /// Перетаскивание всего crop-прямоугольника (без изменения размера).
    private func bodyDragGesture(box: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { g in
                // g.translation — сдвиг от начала жеста. Пересчёт: сохраняем стартовый origin,
                // но SwiftUI без явного @State startCrop это неудобно. Проще — двигать
                // по мгновенному location, центрируя прямоугольник под курсор.
                let nx = clamp(g.location.x / box.width - crop.width / 2, 0, 1 - crop.width)
                let ny = clamp(g.location.y / box.height - crop.height / 2, 0, 1 - crop.height)
                crop = CGRect(x: nx, y: ny, width: crop.width, height: crop.height)
            }
    }

    // MARK: - Helpers

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private func apply() {
        controller.cropImageAtCaret(
            topFrac: crop.minY,
            rightFrac: 1 - crop.maxX,
            bottomFrac: 1 - crop.maxY,
            leftFrac: crop.minX
        )
        onClose()
    }
}

// MARK: - Checkerboard

/// Шахматный фон для превью изображений с прозрачностью.
private struct CheckerboardView: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            let cols = Int(ceil(size.width / s))
            let rows = Int(ceil(size.height / s))
            for r in 0..<rows {
                for c in 0..<cols {
                    let dark = (r + c).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)
                    ctx.fill(Path(rect),
                             with: .color(dark ? Color(white: 0.82) : Color(white: 0.95)))
                }
            }
        }
    }
}
