import AppKit
import SwiftUI

/// Табличный ввод результатов в стиле Numbers: фиксированные колонки, фокус по ячейкам,
/// навигация Tab/↑/↓/Return, многострочная вставка из Excel по ⌘V.
struct ResultEntryGrid: View {
    @Binding var rows: [EntryRow]
    var issues: [EntryIssue]

    @FocusState private var focusedCell: EntryCell?
    @State private var pendingRemoval: EntryRow?

    static let checkboxWidth: CGFloat = 28
    static let nameMinWidth: CGFloat = 190
    static let statusWidth: CGFloat = 128
    static let deleteWidth: CGFloat = 28
    static let widths: [EntryColumn: CGFloat] = [.value: 92, .unit: 86, .lower: 74, .upper: 74, .reference: 149, .price: 100]

    /// Минимальная ширина таблицы; если панель уже, таблица прокручивается по горизонтали.
    static var minimumWidth: CGFloat {
        let columns: [EntryColumn] = [.value, .unit, .lower, .upper, .price]
        var total: CGFloat = checkboxWidth + nameMinWidth + statusWidth + deleteWidth + 8
        for column in columns { total += widths[column] ?? 0 }
        return total
    }

    var body: some View {
        let issuesByRow = Dictionary(grouping: issues, by: \.rowID)
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                ForEach($rows) { $row in
                                    EntryGridRow(row: $row, issues: issuesByRow[row.id] ?? [], focusedCell: $focusedCell) {
                                        if row.hasEnteredData { pendingRemoval = row } else { remove(row) }
                                    }
                                    .id(row.id)
                                    Divider().opacity(0.6)
                                }
                            }
                        }
                        .onChange(of: focusedCell) { _, cell in
                            guard let cell else { return }
                            proxy.scrollTo(cell.row)
                        }
                    }
                }
                .frame(width: max(geometry.size.width, Self.minimumWidth), height: geometry.size.height)
            }
            .scrollIndicators(geometry.size.width >= Self.minimumWidth ? .hidden : .automatic)
        }
        .background(Theme.cardBackground)
        .background(KeyEventMonitor(handler: handleKey))
        .confirmationDialog("Удалить строку?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { row in
            Button("Удалить", role: .destructive) { remove(row) }
        } message: { row in
            Text(row.kind == .panel
                 ? "Будет удалён комплекс «\(row.name)» вместе со всеми введёнными значениями компонентов."
                 : "В строке «\(row.name)» есть введённые данные.")
        }
        .accessibilityIdentifier("editor.grid")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { !rows.isEmpty && rows.allSatisfy(\.isMarked) },
                set: { value in for index in rows.indices { rows[index].isMarked = value } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: Self.checkboxWidth)
            headerCell("Показатель", width: nil, alignment: .leading)
                .frame(minWidth: Self.nameMinWidth)
            headerCell("Результат", width: Self.widths[.value], alignment: .trailing)
            headerCell("Единица", width: Self.widths[.unit], alignment: .leading)
            headerCell("Нижняя гр.", width: Self.widths[.lower], alignment: .trailing)
            headerCell("Верхняя гр.", width: Self.widths[.upper], alignment: .trailing)
            headerCell("Стоимость", width: Self.widths[.price], alignment: .trailing)
            headerCell("Статус", width: Self.statusWidth, alignment: .leading)
            Color.clear.frame(width: Self.deleteWidth)
        }
        .frame(height: 28)
        .background(Theme.gridHeader)
    }

    private func headerCell(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: width == nil ? .infinity : width, alignment: alignment)
                .frame(width: width)
            Divider()
        }
    }

    private func remove(_ row: EntryRow) {
        EntryTableOperations.removeRows(ids: [row.id], from: &rows)
        pendingRemoval = nil
    }

    /// Клавиатурная навигация и вставка столбца. Возвращает true, если событие обработано.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let cell = focusedCell else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 125: // ↓
            guard flags.isDisjoint(with: [.command, .option, .shift]) else { return false }
            if let next = EntryTableOperations.neighbor(of: cell, offset: 1, in: rows) { focusedCell = next }
            return true
        case 126: // ↑
            guard flags.isDisjoint(with: [.command, .option, .shift]) else { return false }
            if let previous = EntryTableOperations.neighbor(of: cell, offset: -1, in: rows) { focusedCell = previous }
            return true
        case 36, 76: // Return / Enter
            guard !flags.contains(.command) else { return false }
            let offset = flags.contains(.shift) ? -1 : 1
            if let next = EntryTableOperations.neighbor(of: cell, offset: offset, in: rows) { focusedCell = next }
            return true
        default:
            if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v",
               let text = NSPasteboard.general.string(forType: .string), EntryTableOperations.isMultiCell(text) {
                EntryTableOperations.paste(text, at: cell, into: &rows)
                return true
            }
            return false
        }
    }
}

struct EntryGridRow: View {
    @Binding var row: EntryRow
    let issues: [EntryIssue]
    var focusedCell: FocusState<EntryCell?>.Binding
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Toggle("", isOn: $row.isMarked)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: ResultEntryGrid.checkboxWidth)
            nameCell
            cell(.value)
            cell(.unit)
            if row.isQualitative && row.kind.hasValue {
                cell(.reference, width: ResultEntryGrid.widths[.reference])
            } else {
                cell(.lower)
                cell(.upper)
            }
            cell(.price)
            statusCell
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: ResultEntryGrid.deleteWidth)
            .help(row.kind == .panel ? "Удалить комплекс целиком" : "Удалить строку")
        }
        .frame(height: 30)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if row.isMarked { return Color.accentColor.opacity(0.08) }
        if row.kind == .panel { return Theme.gridHeader }
        return .clear
    }

    @ViewBuilder
    private var nameCell: some View {
        HStack(spacing: 0) {
            Group {
                if row.isNameEditable {
                    TextField("", text: $row.name, prompt: Text(row.kind == .service ? "Название услуги" : "Название показателя"))
                        .textFieldStyle(.plain)
                        .focused(focusedCell, equals: EntryCell(row: row.id, column: .name))
                        .overlay(alignment: .trailing) {
                            if issues.contains(where: { $0.field == .name }) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                } else {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .fontWeight(row.kind == .panel ? .semibold : .regular)
                            .lineLimit(1)
                            .help(row.name)
                        if row.kind == .panel {
                            Text("комплекс").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        if row.isQualitative {
                            Text("качеств.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, row.kind == .component ? 22 : 6)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Divider()
        }
        .frame(minWidth: ResultEntryGrid.nameMinWidth)
    }

    @ViewBuilder
    private func cell(_ column: EntryColumn, width: CGFloat? = nil) -> some View {
        let cellWidth = width ?? ResultEntryGrid.widths[column] ?? 90
        let issue = issues.first { $0.field.rawValue == fieldName(column) }
        let cellID = EntryCell(row: row.id, column: column)
        HStack(spacing: 0) {
            if column.isEditable(in: row) {
                TextField("", text: Binding(get: { column.value(in: row) }, set: { column.set($0, in: &row) }),
                          prompt: Text(placeholder(column)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(isNumeric(column) ? .trailing : .leading)
                    .monospacedDigit()
                    .focused(focusedCell, equals: cellID)
                    .padding(.horizontal, 6)
                    .frame(width: cellWidth, height: 30)
                    .background(focusedCell.wrappedValue == cellID ? Color.accentColor.opacity(0.1) : Color.clear)
                    .overlay {
                        if let issue {
                            Rectangle().strokeBorder(issue.severity == .error ? Color.red : Color.orange, lineWidth: 1.5)
                        } else if focusedCell.wrappedValue == cellID {
                            Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .help(issue?.message ?? column.title)
                    .accessibilityIdentifier("cell.\(column).\(row.name)")
            } else {
                Text(disabledText(column))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: cellWidth, height: 30)
            }
            Divider()
        }
    }

    @ViewBuilder
    private var statusCell: some View {
        HStack(spacing: 0) {
            Group {
                if let status = row.status {
                    StatusBadge(status: status, compact: true)
                } else {
                    Text(row.kind == .panel ? "стоимость комплекса" : "услуга")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: ResultEntryGrid.statusWidth, alignment: .leading)
            Divider()
        }
    }

    private func isNumeric(_ column: EntryColumn) -> Bool {
        [.value, .lower, .upper, .price].contains(column)
    }

    private func fieldName(_ column: EntryColumn) -> String {
        switch column {
        case .name: "name"
        case .value: "value"
        case .unit: "unit"
        case .lower: "lower"
        case .upper: "upper"
        case .reference: "reference"
        case .price: "price"
        }
    }

    private func placeholder(_ column: EntryColumn) -> String {
        switch column {
        case .value: row.isQualitative ? "текст" : "—"
        case .reference: "напр. отрицательно"
        case .price: row.pricePlaceholder.isEmpty ? "0" : row.pricePlaceholder
        default: ""
        }
    }

    private func disabledText(_ column: EntryColumn) -> String {
        switch (row.kind, column) {
        case (.component, .price): "в комплексе"
        case (.panel, _), (.service, _): ""
        default: ""
        }
    }
}
