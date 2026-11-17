import Foundation

/// Последние известные референсы конкретной лаборатории и последние цены.
/// Используется только для подстановки подсказок — универсальные нормы приложение не применяет.
struct ReferenceHistory: Sendable {
    struct Entry: Sendable {
        let unit: String
        let reference: ReferenceRange
        let date: Date
    }

    private var references: [String: Entry] = [:]
    private var prices: [String: (amount: Decimal, currency: String, date: Date)] = [:]

    init(results: [ResultSnapshot] = [], expenses: [ExpenseSnapshot] = []) {
        for result in results where result.examinationStatus != .draft {
            guard let lab = result.laboratoryName?.searchNormalized, !lab.isEmpty, !result.reference.isEmpty else { continue }
            let key = Self.key(result.testCode, lab)
            if let existing = references[key], existing.date > result.date { continue }
            references[key] = Entry(unit: result.unit, reference: result.reference, date: result.date)
        }
        for expense in expenses {
            let key = expense.priceKey
            if let existing = prices[key], existing.date > expense.date { continue }
            prices[key] = (expense.amount, expense.currencyCode, expense.date)
        }
    }

    private static func key(_ code: String, _ lab: String) -> String { code + "|" + lab }

    func reference(for code: String, laboratory: String) -> Entry? {
        let lab = laboratory.searchNormalized
        guard !lab.isEmpty else { return nil }
        return references[Self.key(code, lab)]
    }

    func lastPrice(for key: String) -> (amount: Decimal, currency: String)? {
        prices[key].map { ($0.amount, $0.currency) }
    }
}

/// Создание строк таблицы ввода из справочника.
struct DraftRowFactory: Sendable {
    let catalog: CatalogIndex
    let history: ReferenceHistory

    func rows(for entry: CatalogEntry, laboratory: String, currency: String) -> [EntryRow] {
        let groupID = UUID()
        if entry.isPanel {
            var rows = [EntryRow(groupID: groupID, kind: .panel, testCode: entry.code, name: entry.name,
                                 category: entry.category, pricePlaceholder: placeholder(for: entry.code, currency: currency))]
            for component in catalog.components(of: entry.code) {
                rows.append(makeRow(component, kind: .component, groupID: groupID, laboratory: laboratory, currency: currency))
            }
            return rows
        }
        return [makeRow(entry, kind: .single, groupID: groupID, laboratory: laboratory, currency: currency)]
    }

    func makeRow(_ entry: CatalogEntry, kind: EntryRow.Kind, groupID: UUID, laboratory: String, currency: String) -> EntryRow {
        var row = EntryRow(groupID: groupID, kind: kind, testCode: entry.code, name: entry.name,
                           category: entry.category, isQualitative: entry.isQualitative, unit: entry.unit)
        applyReference(to: &row, laboratory: laboratory, overwrite: true)
        if kind.hasPrice { row.pricePlaceholder = placeholder(for: entry.code, currency: currency) }
        return row
    }

    /// Подставляет единицу и референсы из прошлого результата этой же лаборатории.
    @discardableResult
    func applyReference(to row: inout EntryRow, laboratory: String, overwrite: Bool) -> Bool {
        guard row.kind.hasValue, let code = row.testCode,
              let entry = history.reference(for: code, laboratory: laboratory) else { return false }
        let hasRefs = !row.lower.trimmed.isEmpty || !row.upper.trimmed.isEmpty || !row.referenceText.trimmed.isEmpty
        guard overwrite || !hasRefs else { return false }
        row.unit = entry.unit
        row.lower = Fmt.optionalNumber(entry.reference.lower)
        row.upper = Fmt.optionalNumber(entry.reference.upper)
        row.referenceText = entry.reference.text ?? ""
        return true
    }

    func placeholder(for key: String, currency: String) -> String {
        guard let last = history.lastPrice(for: key), last.currency == currency else { return "" }
        return "ранее \(Fmt.money(last.amount, currency: last.currency))"
    }

    /// Повторение обследования: копируется только список исследований.
    /// Результаты и фактические расходы не переносятся.
    func repeatRows(from source: ExaminationDraft, laboratory: String, currency: String) -> [EntryRow] {
        var groupMap: [UUID: UUID] = [:]
        return source.rows.map { original in
            let newGroup = groupMap[original.groupID] ?? UUID()
            groupMap[original.groupID] = newGroup
            var row = EntryRow(groupID: newGroup, kind: original.kind, testCode: original.testCode, name: original.name,
                               category: original.category, isQualitative: original.isQualitative, unit: original.unit)
            if row.kind.hasValue {
                if let code = row.testCode, let entry = catalog.entry(code), row.unit.isEmpty { row.unit = entry.unit }
                applyReference(to: &row, laboratory: laboratory, overwrite: true)
            }
            if row.kind.hasPrice {
                let key = row.kind == .service ? "title:" + row.name.searchNormalized : (row.testCode ?? "title:" + row.name.searchNormalized)
                row.pricePlaceholder = placeholder(for: key, currency: currency)
            }
            return row
        }
    }
}
