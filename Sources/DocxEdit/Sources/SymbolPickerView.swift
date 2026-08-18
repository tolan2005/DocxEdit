//
//  SymbolPickerView.swift
//  DocxEdit
//
//  Диалог «Символ» (v0.1.58) — сетка Юникод-символов по категориям,
//  клик вставляет символ в текущую позицию курсора через
//  DocumentController.insertTextAtCaret. Аналог диалога Word «Символ».
//

import SwiftUI

struct SymbolCategory: Identifiable {
    let id: String
    let title: String
    let symbols: [String]
}

enum SymbolLibrary {
    static let categories: [SymbolCategory] = [
        SymbolCategory(id: "punct", title: "Пунктуация", symbols: [
            "—", "–", "…", "«", "»", "„", "“", "”", "‘", "’", "‚",
            "•", "·", "‧", "¶", "§", "†", "‡", "№", "°", "‰", "¿", "¡"
        ]),
        SymbolCategory(id: "spaces", title: "Пробелы", symbols: [
            "\u{00A0}", "\u{2009}", "\u{200A}", "\u{202F}", "\u{2007}"
        ]),
        SymbolCategory(id: "currency", title: "Валюта", symbols: [
            "$", "€", "£", "¥", "₽", "¢", "₹", "₩", "₴", "₺", "₪", "฿", "₦", "₱", "₡", "₨", "₫", "₭", "₮", "₼", "₾", "¤"
        ]),
        SymbolCategory(id: "math", title: "Математика", symbols: [
            "±", "×", "÷", "≈", "≠", "≤", "≥", "∞", "√", "∑", "∏", "∫", "∂", "∆", "∇",
            "π", "µ", "Ω", "α", "β", "γ", "θ", "λ", "σ", "φ", "ψ", "ω",
            "°", "′", "″", "¹", "²", "³", "½", "¼", "¾", "‰"
        ]),
        SymbolCategory(id: "arrows", title: "Стрелки", symbols: [
            "←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙",
            "⇐", "⇒", "⇑", "⇓", "⇔", "⇕",
            "↰", "↱", "↲", "↳", "⤴", "⤵", "↩", "↪"
        ]),
        SymbolCategory(id: "greek", title: "Греческие", symbols: [
            "Α", "Β", "Γ", "Δ", "Ε", "Ζ", "Η", "Θ", "Ι", "Κ", "Λ", "Μ",
            "Ν", "Ξ", "Ο", "Π", "Ρ", "Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω",
            "α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "µ",
            "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ", "φ", "χ", "ψ", "ω"
        ]),
        SymbolCategory(id: "legal", title: "Знаки", symbols: [
            "©", "®", "™", "℠", "℗", "℀", "℁", "℅", "℆", "℮"
        ]),
        SymbolCategory(id: "shapes", title: "Фигуры", symbols: [
            "■", "□", "▪", "▫", "●", "○", "◉", "◎", "◆", "◇", "★", "☆",
            "▲", "△", "▼", "▽", "◀", "▶",
            "♠", "♥", "♦", "♣", "♪", "♫", "☀", "☁", "☂", "☎", "✓", "✔", "✗", "✘"
        ])
    ]
}

struct SymbolPickerView: View {
    @ObservedObject var controller: DocumentController
    let onClose: () -> Void

    @State private var selectedCategoryId: String = SymbolLibrary.categories.first!.id

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            categoriesList
            Divider()
            symbolsGrid
        }
        .frame(width: 560, height: 380)
    }

    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedCategoryId) {
                ForEach(SymbolLibrary.categories) { cat in
                    Text(cat.title)
                        .tag(cat.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 160)
        }
    }

    private var symbolsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentCategory.title)
                    .font(.headline)
                Spacer()
                Button("Закрыть") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                let cols = [GridItem](repeating: GridItem(.fixed(44), spacing: 2), count: 8)
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(Array(currentCategory.symbols.enumerated()), id: \.offset) { _, sym in
                        symbolCell(sym)
                    }
                }
            }
            Text("Клик по символу вставляет его в позицию курсора. Диалог остаётся открыт — можно вставить несколько.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var currentCategory: SymbolCategory {
        SymbolLibrary.categories.first { $0.id == selectedCategoryId } ?? SymbolLibrary.categories[0]
    }

    private func symbolCell(_ sym: String) -> some View {
        Button {
            controller.insertTextAtCaret(sym)
        } label: {
            Text(displayString(sym))
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(codepointLabel(sym))
    }

    /// Пробельные символы отдельно показываем читаемым плейсхолдером,
    /// иначе клетки будут выглядеть пустыми.
    private func displayString(_ sym: String) -> String {
        guard let scalar = sym.unicodeScalars.first else { return sym }
        switch scalar.value {
        case 0x00A0: return "␣"
        case 0x2009: return "␣ᵗ"
        case 0x200A: return "␣ʰ"
        case 0x202F: return "␣ⁿ"
        case 0x2007: return "␣ᶠ"
        default: return sym
        }
    }

    private func codepointLabel(_ sym: String) -> String {
        let scalars = sym.unicodeScalars.map { String(format: "U+%04X", $0.value) }
        return "\(sym) — \(scalars.joined(separator: " "))"
    }
}
