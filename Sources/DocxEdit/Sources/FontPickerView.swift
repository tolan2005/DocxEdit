//
//  FontPickerView.swift
//  DocxEdit
//
//  NSPopUpButton-обёртка для выбора шрифта с секциями:
//  Избранные → Недавние → Все системные.
//  v0.1.4: поддержка состояния «разные шрифты» (пустое поле).
//

import SwiftUI
import AppKit

struct FontPickerView: NSViewRepresentable {
    /// Текущее имя шрифта. Пустая строка = смешанное выделение.
    @Binding var selectedFont: String
    var favoriteFonts: [String]
    var recentFonts: [String]
    var allFonts: [String]
    var onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.fontSelected(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Низкое сопротивление сжатию: при нехватке места пикер усекает заголовок,
        // а не распирает соседние элементы тулбара (первопричина «наезжания»).
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        button.removeAllItems()
        guard let menu = button.menu else { return }

        let isMixed = selectedFont.isEmpty
        let isKnownFont = !isMixed && (
            favoriteFonts.contains(selectedFont) ||
            recentFonts.contains(selectedFont) ||
            allFonts.contains(selectedFont)
        )

        // Если текущее значение — плейсхолдер «Разные шрифты» либо шрифт, отсутствующий
        // во всех трёх списках, заводим для него отдельный служебный пункт первым в меню.
        // Причина: NSPopUpButton при show title, не совпадающего ни с одним реальным
        // пунктом (через setTitle), сам добавляет новый пункт в КОНЕЦ списка и открывает
        // popup там — список прокручивался в самый низ вместо избранных/недавних сверху.
        // Явно управляя этим пунктом (и его позицией), получаем предсказуемое поведение.
        if isMixed || !isKnownFont {
            let placeholder = NSMenuItem(
                title: isMixed ? "Разные шрифты" : selectedFont,
                action: nil, keyEquivalent: ""
            )
            menu.addItem(placeholder)
            menu.addItem(.separator())
        }

        // --- Избранные ---
        let hasFavorites = !favoriteFonts.isEmpty
        if hasFavorites {
            menu.addItem(sectionHeader("Избранные"))
            for name in favoriteFonts {
                menu.addItem(fontItem(name))
            }
            menu.addItem(.separator())
        }

        // --- Недавние ---
        let hasRecent = !recentFonts.isEmpty
        if hasRecent {
            menu.addItem(sectionHeader("Недавние"))
            for name in recentFonts {
                menu.addItem(fontItem(name))
            }
            menu.addItem(.separator())
        }

        // --- Все системные ---
        if hasFavorites || hasRecent {
            menu.addItem(sectionHeader("Все шрифты"))
        }
        for name in allFonts {
            menu.addItem(fontItem(name))
        }

        if isMixed || !isKnownFont {
            button.selectItem(at: 0)
        } else {
            button.selectItem(withTitle: selectedFont)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func fontItem(_ name: String) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.representedObject = name
        // Отображаем имя самим шрифтом (если он доступен)
        if let font = NSFont(name: name, size: 13) {
            item.attributedTitle = NSAttributedString(
                string: name,
                attributes: [.font: font]
            )
        }
        return item
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: FontPickerView
        var isUpdating = false

        init(parent: FontPickerView) { self.parent = parent }

        @objc func fontSelected(_ sender: NSPopUpButton) {
            guard !isUpdating,
                  let name = sender.selectedItem?.representedObject as? String else { return }
            parent.selectedFont = name
            parent.onSelect(name)
        }
    }
}
