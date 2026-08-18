//
//  StylesSidebarView.swift
//  DocxEdit
//
//  v0.2.7 (R04): боковая панель со списком стилей документа. Показывает стили
//  абзаца (Обычный + Заголовки 1..6) и символьные стили (Strong/Emphasis/CodeChar)
//  с превью — клик по стилю применяет его к выделению. Стандартные + пользовательские
//  стили из `document.styles` (`effectiveParagraphStyle`).
//

import SwiftUI
import AppKit
import DocxCore

struct StylesSidebarView: View {
    @ObservedObject var controller: DocumentController
    @Binding var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Стили").font(.headline)
                Spacer()
                Button { controller.toggleStylesSidebar() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Закрыть панель")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("Стили абзаца").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    ForEach(StandardParagraphStyle.all) { s in
                        styleRow(name: s.def.name, id: s.id,
                                 preview: makePreview(for: s.id),
                                 isActive: controller.currentStyleId == s.id) {
                            controller.applyParagraphStyle(id: s.id)
                        }
                    }

                    Divider().padding(.horizontal, 12).padding(.vertical, 6)

                    Text("Стили знака").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    ForEach(StandardCharacterStyle.all) { s in
                        styleRow(name: s.def.name, id: s.id,
                                 preview: makePreview(charStyleId: s.id),
                                 isActive: controller.currentCharStyleId == s.id) {
                            controller.applyCharacterStyle(id: s.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: width)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func styleRow(name: String, id: String, preview: AttributedString,
                          isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(preview)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Строит превью абзацного стиля через AttributedString (шрифт/размер/цвет).
    private func makePreview(for id: String) -> AttributedString {
        let def = controller.effectiveParagraphStyle(id: id)
        var s = AttributedString(def.name)
        let base = NSFont.systemFont(ofSize: 12)
        if let sz = def.fontSize {
            // Ограничиваем превью — крупные заголовки в списке смотрелись бы плохо.
            let clamped = min(CGFloat(sz), 18)
            s.font = NSFont.systemFont(ofSize: clamped)
        } else {
            s.font = base
        }
        if def.bold == true {
            s.font = (s.font.map { $0.bold() }) ?? base.bold()
        }
        if def.italic == true {
            s.font = (s.font.map { $0.italic() }) ?? base.italic()
        }
        if let c = def.textColor {
            s.foregroundColor = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        }
        return s
    }

    /// Строит превью символьного стиля.
    private func makePreview(charStyleId id: String) -> AttributedString {
        let def = controller.effectiveCharacterStyle(id: id)
        var s = AttributedString(def.name)
        let base = NSFont.systemFont(ofSize: 12)
        s.font = base
        if def.bold == true   { s.font = base.bold() }
        if def.italic == true { s.font = (s.font.map { $0.italic() }) ?? base.italic() }
        return s
    }
}

private extension NSFont {
    func bold() -> NSFont {
        let d = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.bold))
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
    func italic() -> NSFont {
        let d = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
