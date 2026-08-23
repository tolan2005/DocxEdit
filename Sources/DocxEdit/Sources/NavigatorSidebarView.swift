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
    /// v1.6.5: индекс строки-цели при drag-reorder разделов.
    @State private var dropTarget: Int? = nil
    /// v1.6.5: индекс перетаскиваемой строки.
    @State private var draggingIndex: Int? = nil

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
                        ForEach(Array(headings.enumerated()), id: \.offset) { idx, h in
                            headingRow(idx, h)
                                .onDrag {
                                    draggingIndex = idx
                                    return NSItemProvider(object: String(idx) as NSString)
                                }
                                .onDrop(of: [.text], delegate: NavigatorDropDelegate(
                                    targetIndex: idx,
                                    isTarget: dropTarget == idx && draggingIndex != idx,
                                    onEnter: { dropTarget = idx },
                                    onExit: { if dropTarget == idx { dropTarget = nil } },
                                    onPerform: { _, index in
                                        let from = draggingIndex ?? index
                                        dropTarget = nil
                                        draggingIndex = nil
                                        guard from != idx else { return }
                                        controller.moveSection(from: from, to: idx)
                                    }))
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
    private func headingRow(_ idx: Int, _ h: DocumentController.NavigatorHeading) -> some View {
        let isCurrent = controller.currentHeadingLocation == h.location
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
                .background(
                    // v1.6.5: подсветка текущего раздела + цель дропа.
                    Group {
                        if dropTarget == idx, draggingIndex != nil {
                            Rectangle().fill(Color.accentColor.opacity(0.35)).frame(height: 2)
                                .frame(maxHeight: .infinity, alignment: .top)
                        } else if isCurrent {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.12))
                        } else {
                            Color.clear
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            // v1.6.4/1.6.5: навигация, уровень и перемещение раздела.
            Button("Перейти к разделу") {
                controller.goToHeading(location: h.location)
            }
            Divider()
            Button("Понизить уровень (\(min(6, h.level + 1)))") {
                controller.demoteHeading(location: h.location, currentLevel: h.level)
            }
            .disabled(h.level >= 6)
            Button("Повысить уровень (\(max(1, h.level - 1)))") {
                controller.promoteHeading(location: h.location, currentLevel: h.level)
            }
            .disabled(h.level <= 1)
            Divider()
            Button("Переместить раздел вверх") {
                controller.moveSection(from: idx, to: idx - 1)
            }
            .disabled(idx == 0)
            Button("Переместить раздел вниз") {
                controller.moveSection(from: idx, to: idx + 1)
            }
            .disabled(idx >= controller.navigatorHeadings().count - 1)
        }
    }
}

/// v1.6.5: DropDelegate для drag-reorder разделов в навигаторе.
/// Источник берётся из `draggingIndex` (ставится в onDrag строки).
private struct NavigatorDropDelegate: DropDelegate {
    let targetIndex: Int
    let isTarget: Bool
    let onEnter: () -> Void
    let onExit: () -> Void
    let onPerform: (NSItemProvider?, Int) -> Void

    func dropEntered(info: DropInfo) {
        onEnter()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onPerform(info.itemProviders(for: [.text]).first, targetIndex)
        return true
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
}
