//
//  NavigatorSidebarView.swift
//  DocxEdit
//
//  v1.5.11: панель навигации по заголовкам (слева, паттерн Word Navigation Pane
//  / Google Docs outline). Список заголовков H1–H6 с отступом по уровню;
//  клик — прыжок к абзацу (курсор + прокрутка). Источник — живой textStorage
//  (`navigatorHeadings()`), пересчёт по `controller.textRevision`.
//

import SwiftUI
import AppKit

struct NavigatorSidebarView: View {
    @ObservedObject var controller: DocumentController
    @Binding var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Навигация").font(.headline)
                Spacer()
                Button { controller.toggleNavigatorSidebar() } label: {
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

            Divider()

            // textRevision в observed controller гарантирует пересчёт на правках.
            let headings = controller.navigatorHeadings()
            if headings.isEmpty {
                Text("Нет заголовков.\nПримените стиль «Заголовок 1–6» (⌘⌥1…6).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(headings.enumerated()), id: \.offset) { _, h in
                            headingRow(h)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: width)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func headingRow(_ h: DocumentController.NavigatorHeading) -> some View {
        Button {
            controller.goToHeading(location: h.location)
        } label: {
            Text(h.text)
                .font(.system(size: 12, weight: h.level == 1 ? .semibold : .regular))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10 + CGFloat(h.level - 1) * 14)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
