//
//  CommandPaletteView.swift
//  DocxEdit (v1.8.0)
//
//  Быстрая палитра всех команд приложения (⌘⇧P). Fuzzy-поиск по названию,
//  Enter — исполнить, ↑↓ — навигация, Esc — закрыть. Каталог команд —
//  RibbonCommandDef.all (v1.2.0, расширен в v1.8.0 файловыми/форматными
//  операциями). Панель — NSPanel (floating), центрируется над key window,
//  закрывается на потерю фокуса.
//

import SwiftUI
import AppKit

// MARK: - Fuzzy-scorer

/// Простая реализация subsequence-scoring: буквы query должны идти в порядке
/// в target (регистронезависимо). Score = чем больше подряд + чем ближе к
/// началу совпадений, тем выше.
enum FuzzyMatcher {
    static func score(query: String, in target: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        var ti = 0, qi = 0
        var score = 0
        var streak = 0
        var firstMatch: Int? = nil
        while ti < t.count, qi < q.count {
            if t[ti] == q[qi] {
                if firstMatch == nil { firstMatch = ti }
                streak += 1
                score += 4 + streak
                qi += 1
            } else {
                streak = 0
            }
            ti += 1
        }
        guard qi == q.count else { return nil }
        // Бонус за раннее совпадение (title начинается с query — выше).
        if let f = firstMatch { score -= f / 2 }
        // Точное совпадение подстроки — сильно выше (для «Сохранить»).
        if target.lowercased().contains(query.lowercased()) { score += 100 }
        return score
    }
}

// MARK: - View

struct CommandPaletteView: View {
    @ObservedObject var controller: DocumentController
    let appDelegate: AppDelegate
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    private var results: [(RibbonCommandDef, Int)] {
        let all = RibbonCommandDef.all
        if query.isEmpty {
            return all.map { ($0, 0) }
        }
        return all
            .compactMap { cmd -> (RibbonCommandDef, Int)? in
                guard let s = FuzzyMatcher.score(query: query, in: cmd.title) else { return nil }
                return (cmd, s)
            }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Что вы хотите сделать?", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .onChange(of: query) { _ in selectedIndex = 0 }
                    .onSubmit { runSelected() }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if results.isEmpty {
                Text("Ничего не найдено")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.prefix(30).enumerated()), id: \.offset) { idx, pair in
                                CommandRow(cmd: pair.0, selected: idx == selectedIndex)
                                    .id(idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIndex = idx
                                        runSelected()
                                    }
                                    .onHover { hovering in
                                        if hovering { selectedIndex = idx }
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { new in
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                keyHint("↑↓", "выбор")
                keyHint("↵", "выполнить")
                keyHint("esc", "закрыть")
                Spacer()
                Text("\(results.count) команд")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 560, height: 420)
        .background(KeyEventHandler(onArrowDown: moveDown, onArrowUp: moveUp, onEscape: onClose))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func moveDown() { selectedIndex = min(selectedIndex + 1, max(0, min(29, results.count - 1))) }
    private func moveUp()   { selectedIndex = max(selectedIndex - 1, 0) }
    private func runSelected() {
        let list = results.prefix(30)
        guard selectedIndex < list.count else { return }
        let cmd = list[list.index(list.startIndex, offsetBy: selectedIndex)].0
        onClose()
        // Небольшая задержка чтобы палитра успела закрыться и key window вернулся.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            cmd.run(controller, appDelegate)
        }
    }

    private func keyHint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.4)))
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CommandRow: View {
    let cmd: RibbonCommandDef
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.symbol)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
            Text(cmd.title)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(selected ? Color.accentColor : Color.clear)
    }
}

// MARK: - Клавиатурная обработка (↑ ↓ Esc)

/// NSViewRepresentable-хук на keyDown. Меньше кода, чем через
/// `.onKeyPress` (macOS 14+), и работает надёжно для NSPanel.
private struct KeyEventHandler: NSViewRepresentable {
    let onArrowDown: () -> Void
    let onArrowUp: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onArrowDown = onArrowDown
        view.onArrowUp = onArrowUp
        view.onEscape = onEscape
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyView)?.onArrowDown = onArrowDown
        (nsView as? KeyView)?.onArrowUp = onArrowUp
        (nsView as? KeyView)?.onEscape = onEscape
    }
    final class KeyView: NSView {
        var onArrowDown: (() -> Void)?
        var onArrowUp: (() -> Void)?
        var onEscape: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor.map { NSEvent.removeMonitor($0) }
            monitor = nil
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard e.window === window, let self else { return e }
                switch e.keyCode {
                case 125: self.onArrowDown?(); return nil   // ↓
                case 126: self.onArrowUp?();   return nil   // ↑
                case 53:  self.onEscape?();    return nil   // Esc
                default:  return e
                }
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

// MARK: - Панель-обёртка

/// Владелец плавающей панели палитры. Один экземпляр на приложение
/// (singleton) — открытие в другом окне переиспользует ту же панель,
/// но пересоздаёт content с текущим controller/appDelegate.
@MainActor
final class CommandPaletteWindow {
    static let shared = CommandPaletteWindow()
    private var panel: NSPanel?

    func toggle(controller: DocumentController, appDelegate: AppDelegate) {
        if let p = panel, p.isVisible { close(); return }
        show(controller: controller, appDelegate: appDelegate)
    }

    func show(controller: DocumentController, appDelegate: AppDelegate) {
        let content = CommandPaletteView(controller: controller, appDelegate: appDelegate) {
            [weak self] in self?.close()
        }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 420)

        let p = panel ?? NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.hidesOnDeactivate = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = false
        p.level = .floating
        p.contentView = hosting

        // Центрируем над key window.
        if let key = NSApp.keyWindow ?? NSApp.mainWindow {
            let kf = key.frame
            let px = kf.midX - 280
            let py = kf.midY + 60      // чуть выше центра
            p.setFrameOrigin(NSPoint(x: px, y: py))
        } else {
            p.center()
        }
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
    }
}
