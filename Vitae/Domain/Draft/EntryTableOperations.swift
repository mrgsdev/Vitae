import Foundation

/// Редактируемые колонки таблицы ввода (в порядке клавиатурной навигации).
enum EntryColumn: Int, CaseIterable, Hashable, Sendable {
    case name, value, unit, lower, upper, reference, price

    var title: String {
        switch self {
        case .name: "Название"
        case .value: "Результат"
        case .unit: "Единица"
        case .lower: "Нижняя граница"
        case .upper: "Верхняя граница"
        case .reference: "Референс (текст)"
        case .price: "Стоимость"
        }
    }

    /// Колонки, доступные для массового заполнения.
    static let bulkFillable: [EntryColumn] = [.value, .unit, .lower, .upper, .reference, .price]

    func isEditable(in row: EntryRow) -> Bool {
        switch self {
        case .name: row.isNameEditable
        case .value, .unit: row.kind.hasValue
        case .lower, .upper: row.kind.hasValue && !row.isQualitative
        case .reference: row.kind.hasValue && row.isQualitative
        case .price: row.kind.hasPrice
        }
    }

    func value(in row: EntryRow) -> String {
        switch self {
        case .name: row.name
        case .value: row.value
        case .unit: row.unit
        case .lower: row.lower
        case .upper: row.upper
        case .reference: row.referenceText
        case .price: row.price
        }
    }

    func set(_ value: String, in row: inout EntryRow) {
        switch self {
        case .name: row.name = value
        case .value: row.value = value
        case .unit: row.unit = value
        case .lower: row.lower = value
        case .upper: row.upper = value
        case .reference: row.referenceText = value
        case .price: row.price = value
        }
    }
}

struct EntryCell: Hashable, Sendable {
    let row: UUID
    let column: EntryColumn
}

/// Операции над таблицей ввода: вставка из буфера, массовое заполнение, навигация.
enum EntryTableOperations {
    /// Разбор текста из буфера обмена (Excel/Numbers): строки через перевод строки, ячейки через табуляцию.
    static func parseClipboard(_ text: String) -> [[String]] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while let last = lines.last, last.trimmed.isEmpty { lines.removeLast() }
        return lines.map { $0.components(separatedBy: "\t").map(\.trimmed) }
    }

    static func isMultiCell(_ text: String) -> Bool {
        let matrix = parseClipboard(text)
        return matrix.count > 1 || (matrix.first?.count ?? 0) > 1
    }

    /// Вставка матрицы значений, начиная с ячейки `start`. Заполнение идёт вниз по строкам,
    /// пропуская строки, где колонка недоступна (например, заголовки комплексов).
    /// Если в колонку «Нижняя граница» вставляется диапазон «3,5–5,5», заполняются обе границы.
    @discardableResult
    static func paste(_ text: String, at start: EntryCell, into rows: inout [EntryRow]) -> Int {
        let matrix = parseClipboard(text)
        guard !matrix.isEmpty, let startIndex = rows.firstIndex(where: { $0.id == start.row }) else { return 0 }
        let columnOrder = EntryColumn.allCases
        guard let startColumnIndex = columnOrder.firstIndex(of: start.column) else { return 0 }

        var filled = 0
        var rowIndex = startIndex
        for line in matrix {
            while rowIndex < rows.count && !start.column.isEditable(in: rows[rowIndex]) { rowIndex += 1 }
            guard rowIndex < rows.count else { break }
            var columnIndex = startColumnIndex
            for cellValue in line {
                while columnIndex < columnOrder.count && !columnOrder[columnIndex].isEditable(in: rows[rowIndex]) {
                    columnIndex += 1
                }
                guard columnIndex < columnOrder.count else { break }
                let column = columnOrder[columnIndex]
                if column == .lower, line.count == 1 {
                    let range = ReferenceRange.parse(cellValue)
                    if range.lower != nil || range.upper != nil {
                        rows[rowIndex].lower = Fmt.optionalNumber(range.lower)
                        rows[rowIndex].upper = Fmt.optionalNumber(range.upper)
                        filled += 1
                        columnIndex += 1
                        continue
                    }
                }
                column.set(cellValue, in: &rows[rowIndex])
                filled += 1
                columnIndex += 1
            }
            rowIndex += 1
        }
        return filled
    }

    enum FillScope: String, CaseIterable, Identifiable, Sendable {
        case marked, empty, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .marked: "Отмеченные строки"
            case .empty: "Только пустые ячейки"
            case .all: "Все строки"
            }
        }
    }

    /// Массовое заполнение колонки одним значением.
    @discardableResult
    static func bulkFill(_ value: String, column: EntryColumn, scope: FillScope, rows: inout [EntryRow]) -> Int {
        var count = 0
        for index in rows.indices where column.isEditable(in: rows[index]) {
            let current = column.value(in: rows[index])
            let applies: Bool
            switch scope {
            case .marked: applies = rows[index].isMarked
            case .empty: applies = current.trimmed.isEmpty
            case .all: applies = true
            }
            guard applies else { continue }
            column.set(value, in: &rows[index])
            count += 1
        }
        return count
    }

    /// Ячейка в соседней строке той же колонки (для стрелок и Return).
    static func neighbor(of cell: EntryCell, offset: Int, in rows: [EntryRow]) -> EntryCell? {
        guard let index = rows.firstIndex(where: { $0.id == cell.row }) else { return nil }
        var next = index + offset
        while next >= 0 && next < rows.count {
            if cell.column.isEditable(in: rows[next]) { return EntryCell(row: rows[next].id, column: cell.column) }
            next += offset
        }
        return nil
    }

    /// Удаление строк. Удаление заголовка комплекса удаляет и его компоненты.
    static func removeRows(ids: Set<UUID>, from rows: inout [EntryRow]) {
        let panelGroups = Set(rows.filter { ids.contains($0.id) && $0.kind == .panel }.map(\.groupID))
        rows.removeAll { ids.contains($0.id) || panelGroups.contains($0.groupID) }
        // Комплекс без компонентов превращается в услугу с той же стоимостью.
        let groupsWithComponents = Set(rows.filter { $0.kind == .component }.map(\.groupID))
        for index in rows.indices where rows[index].kind == .panel && !groupsWithComponents.contains(rows[index].groupID) {
            rows[index].kind = .service
        }
    }
}
