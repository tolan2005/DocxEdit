//
//  DocumentController+Tables.swift
//  Распил монолита DocumentController.swift (v1.6.5, PROJECT_ANALYSIS.md §3.1).
//  Таблицы: операции строк/столбцов, стиль, высота — v0.1.50+
//  Код перенесён без изменений (extension того же класса). Stored properties
//  перенесены в основной класс (в extension запрещены).
//

import AppKit
import DocxCore

extension DocumentController {
    // MARK: - Операции строк/столбцов таблицы (v0.1.50)

    /// Операции над таблицей, применяемые к таблице в позиции курсора.
    enum TableEdit {
        case addRowAbove, addRowBelow
        case addColumnLeft, addColumnRight
        case deleteRow, deleteColumn, deleteTable
        /// Объединить выделенные ячейки одной строки в одну (colSpan = сумма).
        /// Горизонтальный merge из линейного выделения NSTextView.
        case mergeCells
        /// Объединить прямоугольник ячеек по явным grid-координатам (из диалога-сетки,
        /// v0.1.65). Не зависит от линейного выделения NSTextView — единственный
        /// надёжный способ вертикального/прямоугольного merge.
        case mergeRect(minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)
        /// Разделить текущую ячейку (colSpan>1 → 1x1 + вставка пустых справа).
        case splitCell
        /// v0.1.85: пометить текущую строку как строку-заголовок таблицы (toggle).
        /// В DOCX — `<w:tblHeader/>`; повторяется на каждой странице при печати.
        case toggleHeaderRow
        /// v0.1.86: задать минимальную высоту текущей строки (pt). `nil` — сброс к авто.
        case setRowHeight(CGFloat?)
    }

    /// v0.1.89: фактическая визуальная высота текущей строки таблицы (pt), считывается
    /// из NSLayoutManager. Обходит все абзацы текущей строки (по совпадению startingRow
    /// у cellBlock) и берёт union bounding rect — включает высоту, добавленную ручным
    /// увеличением содержимого. Nil, если курсор не в таблице.
    func currentRowVisualHeight() -> CGFloat? {
        guard let tv = textView, let storage = tv.textStorage,
              let lm = tv.layoutManager, let tc = tv.textContainer,
              storage.length > 0 else { return nil }
        guard let span = tableSpanAtCaret() else { return nil }
        let full = NSRange(location: 0, length: storage.length)
        let ns = storage.string as NSString
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        var loc = span.range.location
        let end = min(NSMaxRange(span.range), storage.length)
        while loc < end {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let probe = min(pr.location, storage.length - 1)
            if let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
               let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
               cb.table === span.nsTable, cb.startingRow == span.caretRow {
                let gr = lm.glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
                if gr.length > 0 {
                    let rect = lm.boundingRect(forGlyphRange: gr, in: tc)
                    minY = min(minY, rect.minY)
                    maxY = max(maxY, rect.maxY)
                }
            }
            loc = pr.length > 0 ? NSMaxRange(pr) : loc + 1
            _ = full
        }
        return (maxY > minY) ? (maxY - minY) : nil
    }

    /// Диапазон таблицы в storage вокруг позиции курсора + текущие координаты ячейки.
    /// Возвращает nil, если курсор не в таблице.
    struct TableSpan {
        let range: NSRange
        let nsTable: NSTextTable
        let caretRow: Int
        let caretCol: Int
    }

    func tableSpanAtCaret() -> TableSpan? {
        guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return nil }
        let raw = tv.selectedRange().location
        let probe = min(max(0, raw), storage.length - 1)
        guard let ps = storage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle,
              let caretBlock = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first else {
            return nil
        }
        let table = caretBlock.table
        let ns = storage.string as NSString

        // Идём назад по абзацам, пока встречаем ту же NSTextTable.
        var startLoc = ns.paragraphRange(for: NSRange(location: probe, length: 0)).location
        while startLoc > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: startLoc - 1, length: 0))
            guard let pps = storage.attribute(.paragraphStyle, at: prev.location, effectiveRange: nil) as? NSParagraphStyle,
                  let pcb = pps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                  pcb.table === table else { break }
            startLoc = prev.location
        }
        // Вперёд.
        var endLoc = NSMaxRange(ns.paragraphRange(for: NSRange(location: probe, length: 0)))
        while endLoc < storage.length {
            let next = ns.paragraphRange(for: NSRange(location: endLoc, length: 0))
            guard next.length > 0,
                  let nps = storage.attribute(.paragraphStyle, at: next.location, effectiveRange: nil) as? NSParagraphStyle,
                  let ncb = nps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                  ncb.table === table else { break }
            endLoc = NSMaxRange(next)
        }
        return TableSpan(range: NSRange(location: startLoc, length: endLoc - startLoc),
                         nsTable: table,
                         caretRow: caretBlock.startingRow,
                         caretCol: caretBlock.startingColumn)
    }

    /// Применяет операцию к таблице в позиции курсора (add/delete row/col/table).
    /// Извлекает модель таблицы через `DocumentModel.from(attributed:)` на subAttr
    /// текущего span, мутирует, перерендеривает через `appendTable` и заменяет
    /// весь span одним атомарным `replaceCharacters` под `shouldChangeText` —
    /// один шаг undo (паттерн ADR-027).
    func applyTableEdit(_ edit: TableEdit) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard let span = tableSpanAtCaret() else { return }

        // deleteTable — упрощённый путь без извлечения/перерендера.
        if case .deleteTable = edit {
            let attrs = tv.typingAttributes
            let empty = NSAttributedString(string: "", attributes: attrs)
            guard tv.shouldChangeText(in: span.range, replacementString: "") else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: span.range, with: empty)
            storage.endEditing()
            tv.didChangeText()
            let caretLoc = min(span.range.location, storage.length)
            tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
            notifyModelChange()
            refreshSelectionState()
            return
        }

        // Извлекаем модель таблицы из subAttr — reverse-bridge даёт TableBlock.
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var table: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { table = t; break }
        }
        guard var newTable = table else { return }

        let r = span.caretRow
        let c = span.caretCol

        func emptyCell() -> TableCell {
            TableCell(blocks: [.paragraph(Paragraph(
                runs: [Run(text: "", attributes: CharacterAttributes())],
                attributes: ParagraphAttributes()))])
        }

        // (targetRow, targetCol) — куда перевести курсор после перерендера.
        // Add-ops сохраняют позицию исходной ячейки (со сдвигом, если новая
        // строка/столбец добавлены до неё). Delete-ops оставляют курсор в той
        // же строке/столбце (clamp к последнему индексу, если удалили последний).
        var targetRow = r
        var targetCol = c

        switch edit {
        case .addRowAbove:
            let cols = newTable.rows.first?.cells.count ?? 1
            let row = DocxCore.TableRow(cells: (0..<cols).map { _ in emptyCell() })
            newTable.rows.insert(row, at: max(0, min(r, newTable.rows.count)))
            targetRow = r + 1
        case .addRowBelow:
            let cols = newTable.rows.first?.cells.count ?? 1
            let row = DocxCore.TableRow(cells: (0..<cols).map { _ in emptyCell() })
            newTable.rows.insert(row, at: max(0, min(r + 1, newTable.rows.count)))
            targetRow = r
        case .addColumnLeft:
            for i in newTable.rows.indices {
                let idx = max(0, min(c, newTable.rows[i].cells.count))
                newTable.rows[i].cells.insert(emptyCell(), at: idx)
            }
            targetCol = c + 1
        case .addColumnRight:
            for i in newTable.rows.indices {
                let idx = max(0, min(c + 1, newTable.rows[i].cells.count))
                newTable.rows[i].cells.insert(emptyCell(), at: idx)
            }
            targetCol = c
        case .deleteRow:
            guard newTable.rows.count > 1 else {
                applyTableEdit(.deleteTable); return
            }
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows.remove(at: r)
            targetRow = min(r, newTable.rows.count - 1)
        case .deleteColumn:
            guard (newTable.rows.first?.cells.count ?? 0) > 1 else {
                applyTableEdit(.deleteTable); return
            }
            for i in newTable.rows.indices {
                if c >= 0, c < newTable.rows[i].cells.count {
                    newTable.rows[i].cells.remove(at: c)
                }
            }
            targetCol = min(c, (newTable.rows.first?.cells.count ?? 1) - 1)
        case .toggleHeaderRow:
            // v0.1.85: пометить текущую строку как заголовок таблицы (или снять).
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows[r].isHeader.toggle()
            targetRow = r
        case .setRowHeight(let value):
            // v0.1.86: минимальная высота текущей строки. Nil = сброс.
            guard r >= 0, r < newTable.rows.count else { return }
            newTable.rows[r].height = (value.map { max(0, $0) }).flatMap { $0 > 0 ? $0 : nil }
            targetRow = r
        case .deleteTable:
            return // покрыто выше
        case .mergeCells:
            // Горизонтальный merge из линейного выделения NSTextView. Берём границы
            // от ПЕРВОЙ и ПОСЛЕДНЕЙ ячейки выделения. Вертикальный/прямоугольный
            // merge через выделение невозможен (NSTextView не умеет прямоугольное
            // выделение) — для него есть диалог-сетка → .mergeRect (v0.1.65).
            let sel = tv.selectedRange()
            let ns = storage.string as NSString
            var firstCoord: (row: Int, col: Int, span: Int)? = nil
            var lastCoord: (row: Int, col: Int, span: Int)? = nil
            var loc = sel.location
            let end = NSMaxRange(sel)
            while loc <= end {
                let pr = ns.paragraphRange(for: NSRange(location: min(loc, storage.length - 1), length: 0))
                if let ps = storage.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle,
                   let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first,
                   cb.table === span.nsTable {
                    let coord = (cb.startingRow, cb.startingColumn, cb.columnSpan)
                    if firstCoord == nil { firstCoord = coord }
                    lastCoord = coord
                }
                if pr.length == 0 { break }
                loc = NSMaxRange(pr)
                if loc == end && pr.location + pr.length == end { break }
            }
            guard let a = firstCoord, let b = lastCoord else { NSSound.beep(); return }
            let minRow = min(a.row, b.row)
            let maxRow = max(a.row, b.row)
            let minCol = min(a.col, b.col)
            let maxCol = max(a.col + a.span - 1, b.col + b.span - 1)
            guard mergeRectInto(&newTable, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol) else {
                NSSound.beep(); return
            }
            targetRow = minRow
            targetCol = minCol
        case let .mergeRect(minRow, maxRow, minCol, maxCol):
            guard mergeRectInto(&newTable, minRow: minRow, maxRow: maxRow, minCol: minCol, maxCol: maxCol) else {
                NSSound.beep(); return
            }
            targetRow = minRow
            targetCol = minCol
        case .splitCell:
            // Возвращаем текущую ячейку в 1x1 + восстанавливаем удалённые ячейки в rows ниже
            // (для rowSpan>1) и справа (для colSpan>1).
            guard r < newTable.rows.count else { return }
            var idxByCol: [Int: Int] = [:]
            var cur = 0
            for (i, cell) in newTable.rows[r].cells.enumerated() {
                for gc in cur..<(cur + max(1, cell.colSpan)) { idxByCol[gc] = i }
                cur += max(1, cell.colSpan)
            }
            guard let cellIdx = idxByCol[c] else { return }
            let currentColSpan = max(1, newTable.rows[r].cells[cellIdx].colSpan)
            let currentRowSpan = max(1, newTable.rows[r].cells[cellIdx].rowSpan)
            guard currentColSpan > 1 || currentRowSpan > 1 else { NSSound.beep(); return }

            let cellStartCol = c
            let cellEndCol = c + currentColSpan - 1
            // Горизонтальный split: у самой ячейки colSpan=1, вставляем справа.
            newTable.rows[r].cells[cellIdx].colSpan = 1
            newTable.rows[r].cells[cellIdx].rowSpan = 1
            for _ in 0..<(currentColSpan - 1) {
                newTable.rows[r].cells.insert(emptyCell(), at: cellIdx + 1)
            }
            // Вертикальный split: в каждой row в диапазоне (r+1 .. r+currentRowSpan-1)
            // вставляем currentColSpan пустых ячеек в позицию с grid-col = cellStartCol.
            if currentRowSpan > 1 {
                for row in (r + 1)...(r + currentRowSpan - 1) where row < newTable.rows.count {
                    // Ищем индекс в row.cells, куда вставлять — первая ячейка с grid-col >= cellStartCol.
                    var insertIdx = newTable.rows[row].cells.count
                    var gridCol = 0
                    for (i, cell) in newTable.rows[row].cells.enumerated() {
                        if gridCol >= cellStartCol { insertIdx = i; break }
                        gridCol += max(1, cell.colSpan)
                    }
                    for _ in cellStartCol...cellEndCol {
                        newTable.rows[row].cells.insert(emptyCell(), at: insertIdx)
                    }
                }
            }
            targetRow = r
            targetCol = c
        }

        // Перерендер — appendTable даёт эквивалентный shape (без хвостового абзаца).
        let payload = NSMutableAttributedString()
        let typingAttrs = tv.typingAttributes
        let defaultFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        appendTable(newTable, to: payload, defaultFont: defaultFont,
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: pageUsableWidth)

        guard tv.shouldChangeText(in: span.range, replacementString: payload.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: span.range, with: payload)
        storage.endEditing()
        tv.didChangeText()
        // Курсор — в целевую ячейку (targetRow, targetCol), а не в top-left.
        let caretLoc = locationOfCell(row: targetRow, col: targetCol,
                                       tableStart: span.range.location,
                                       storage: storage) ?? span.range.location
        tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Объединяет прямоугольник ячеек [minRow…maxRow]×[minCol…maxCol] (в grid-
    /// координатах) внутри `table`. Возвращает false, если прямоугольник вырожден
    /// (одна ячейка) или выходит за границы — тогда вызывающий делает beep.
    /// Общий код для `.mergeCells` (выделение) и `.mergeRect` (диалог-сетка).
    private func mergeRectInto(_ table: inout TableBlock,
                               minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) -> Bool {
        guard minRow >= 0, minCol >= 0, maxRow >= minRow, maxCol >= minCol else { return false }
        guard maxRow > minRow || maxCol > minCol else { return false }
        guard maxRow < table.rows.count else { return false }

        func emptyCell() -> TableCell {
            TableCell(blocks: [.paragraph(Paragraph(
                runs: [Run(text: "", attributes: CharacterAttributes())],
                attributes: ParagraphAttributes()))])
        }

        // Собираем непустое содержимое всех ячеек прямоугольника + удаляем покрытые.
        var mergedBlocks: [Block] = []
        for row in minRow...maxRow {
            var idxByCol: [Int: Int] = [:]
            var cur = 0
            for (i, cell) in table.rows[row].cells.enumerated() {
                for gc in cur..<(cur + max(1, cell.colSpan)) { idxByCol[gc] = i }
                cur += max(1, cell.colSpan)
            }
            var cellIndices = Set<Int>()
            for gc in minCol...maxCol {
                if let idx = idxByCol[gc] { cellIndices.insert(idx) }
            }
            for idx in cellIndices.sorted() {
                for block in table.rows[row].cells[idx].blocks {
                    if case .paragraph(let p) = block,
                       !(p.runs.isEmpty || p.runs.allSatisfy { $0.text.isEmpty }) {
                        mergedBlocks.append(block)
                    }
                }
            }
            let toRemove: [Int]
            if row == minRow, let keepIdx = idxByCol[minCol] {
                toRemove = cellIndices.subtracting([keepIdx]).sorted()
            } else {
                toRemove = cellIndices.sorted()
            }
            for i in toRemove.reversed() {
                table.rows[row].cells.remove(at: i)
            }
        }
        // Находим target (grid-col == minCol) в первой строке после удалений.
        var targetIdx: Int? = nil
        var cur = 0
        for (i, cell) in table.rows[minRow].cells.enumerated() {
            if cur == minCol { targetIdx = i; break }
            cur += max(1, cell.colSpan)
        }
        guard let ti = targetIdx else { return false }
        table.rows[minRow].cells[ti].colSpan = maxCol - minCol + 1
        table.rows[minRow].cells[ti].rowSpan = maxRow - minRow + 1
        if !mergedBlocks.isEmpty {
            table.rows[minRow].cells[ti].blocks = mergedBlocks
        }
        return true
    }

    /// Размер сетки таблицы под курсором + позиция ячейки-курсора (в grid-координатах).
    /// Для диалога объединения ячеек (v0.1.65). Nil, если курсор не в таблице.
    func tableGridInfo() -> (rows: Int, cols: Int, caretRow: Int, caretCol: Int)? {
        guard let span = tableSpanAtCaret(), let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var table: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { table = t; break }
        }
        guard let t = table, !t.rows.isEmpty else { return nil }
        let rows = t.rows.count
        let cols = t.rows.map { row in row.cells.reduce(0) { $0 + max(1, $1.colSpan) } }.max() ?? 1
        let cr = min(max(0, span.caretRow), rows - 1)
        let cc = min(max(0, span.caretCol), cols - 1)
        return (rows, cols, cr, cc)
    }

    /// Полезная ширина страницы (ширина - левое+правое поле) в points.
    /// Используется для позиционирования таблиц (v0.1.73).
    var pageUsableWidth: CGFloat {
        session?.bridge.model.pageSettings.usableWidthInPoints ?? PageSettings.a4Portrait.usableWidthInPoints
    }

    // MARK: - Стиль таблицы (v0.1.51)

    /// Возвращает текущий стиль таблицы под курсором + позицию ячейки (row, col).
    /// Nil, если курсор не в таблице.
    func currentTableInfo() -> (style: DocxCore.TableStyle, cellBackground: CodableColor?, columnWidth: CGFloat?, row: Int, col: Int)? {
        guard let span = tableSpanAtCaret(),
              let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block {
                let r = min(max(0, span.caretRow), t.rows.count - 1)
                let c = min(max(0, span.caretCol), (t.rows.first?.cells.count ?? 1) - 1)
                let cell = t.rows[r].cells[c]
                return (t.style, cell.backgroundColor, cell.width, r, c)
            }
        }
        return nil
    }

    /// Универсальная мутация таблицы под курсором — извлекает модель, вызывает
    /// `transform(inout TableBlock, row, col)`, перерендеривает через `appendTable`,
    /// заменяет span одним атомарным `replaceCharacters` (один шаг undo). Курсор
    /// возвращается в ту же ячейку (row, col).
    func mutateCurrentTable(_ transform: (inout TableBlock, Int, Int) -> Void) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard let span = tableSpanAtCaret() else { return }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        var newTable: TableBlock?
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { newTable = t; break }
        }
        guard var t = newTable else { return }
        transform(&t, span.caretRow, span.caretCol)

        let payload = NSMutableAttributedString()
        let typingAttrs = tv.typingAttributes
        let defaultFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        appendTable(t, to: payload, defaultFont: defaultFont,
                    fallbackFontName: AppPreferences.shared.favoriteFonts.first,
                    usableWidth: pageUsableWidth)

        guard tv.shouldChangeText(in: span.range, replacementString: payload.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: span.range, with: payload)
        storage.endEditing()
        tv.didChangeText()
        let caretLoc = locationOfCell(row: span.caretRow, col: span.caretCol,
                                       tableStart: span.range.location, storage: storage) ?? span.range.location
        tv.setSelectedRange(NSRange(location: caretLoc, length: 0))
        notifyModelChange()
        refreshSelectionState()
    }

    /// Меняет границы всей таблицы: показывать/цвет/толщина.
    func setTableBorders(hasBorders: Bool, color: NSColor?, width: CGFloat) {
        mutateCurrentTable { t, _, _ in
            t.style.hasBorders = hasBorders
            if let c = color {
                let cc = c.usingColorSpace(.sRGB) ?? c
                t.style.borderColor = CodableColor(red: cc.redComponent, green: cc.greenComponent,
                                                    blue: cc.blueComponent, alpha: cc.alphaComponent)
            } else {
                t.style.borderColor = nil
            }
            t.style.borderWidth = max(0, width)
        }
    }

    /// Заливка текущей ячейки (nil — убрать).
    func setCellBackground(_ color: NSColor?) {
        mutateCurrentTable { t, r, c in
            guard r < t.rows.count, c < t.rows[r].cells.count else { return }
            if let color {
                let cc = color.usingColorSpace(.sRGB) ?? color
                t.rows[r].cells[c].backgroundColor = CodableColor(
                    red: cc.redComponent, green: cc.greenComponent,
                    blue: cc.blueComponent, alpha: cc.alphaComponent)
            } else {
                t.rows[r].cells[c].backgroundColor = nil
            }
        }
    }

    /// Горизонтальное выравнивание таблицы на странице (v0.1.70).
    /// В DOCX — `<w:jc>` в `<w:tblPr>`. С v0.1.92 и визуально в редакторе:
    /// appendTable задаёт contentWidth + левый margin NSTextTable, когда
    /// суммарная ширина колонок известна и меньше usable-ширины страницы.
    func setTableAlignment(_ alignment: DocxCore.TableAlignment) {
        mutateCurrentTable { t, _, _ in
            t.alignment = alignment
        }
    }

    /// Текущее выравнивание таблицы под курсором (для prefill диалога).
    func currentTableAlignment() -> DocxCore.TableAlignment? {
        guard let span = tableSpanAtCaret(),
              let storage = textView?.textStorage else { return nil }
        let sub = storage.attributedSubstring(from: span.range)
        let mini = DocumentModel.from(attributed: sub)
        for block in (mini.sections.first?.blocks ?? []) {
            if case .table(let t) = block { return t.alignment }
        }
        return nil
    }

    /// Ширина текущей колонки в points (устанавливается на КАЖДУЮ ячейку колонки).
    /// nil — авто-ширина.
    func setColumnWidth(_ width: CGFloat?) {
        mutateCurrentTable { t, _, c in
            for i in t.rows.indices {
                guard c < t.rows[i].cells.count else { continue }
                t.rows[i].cells[c].width = width
            }
        }
    }

    /// Ищет первый абзац с `NSTextTableBlock.startingRow == row` и `startingColumn == col`
    /// начиная с `tableStart`. Возвращает storage-позицию начала этого абзаца или nil,
    /// если не нашёл (например, targetRow/Col выходят за границы новой таблицы).
    private func locationOfCell(row: Int, col: Int, tableStart: Int, storage: NSTextStorage) -> Int? {
        let ns = storage.string as NSString
        var loc = tableStart
        while loc < storage.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            guard let ps = storage.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle,
                  let cb = ps.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first else { return nil }
            if cb.startingRow == row && cb.startingColumn == col { return para.location }
            loc = NSMaxRange(para)
        }
        return nil
    }

}
