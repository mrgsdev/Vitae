import Foundation

struct ExpenseRow: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let title: String
    let category: ExpenseCategory
    let categoryTitle: String
    let examinationID: UUID?
    let examinationTitle: String
    let laboratoryName: String
    let amount: Decimal
    let currencyCode: String
    let isStandalone: Bool

    init(_ expense: Expense) {
        id = expense.id
        date = expense.examination?.date ?? expense.date
        title = expense.title
        category = expense.category
        categoryTitle = expense.category.title
        examinationID = expense.examination?.id
        examinationTitle = expense.examination?.title ?? "—"
        laboratoryName = expense.laboratory?.name ?? expense.examination?.laboratory?.name ?? ""
        amount = expense.amount
        currencyCode = expense.currencyCode
        isStandalone = expense.examination == nil
    }
}

struct ExpensesState {
    var currency: String?
    var year: Int = Date.now.year()
    var searchText = ""
    var categoryFilter: ExpenseCategory?
    var laboratoryFilter: String?
    var selectedPriceKey: String?
    var selection: Set<UUID> = []
    var sortOrder: [KeyPathComparator<ExpenseRow>] = [KeyPathComparator(\ExpenseRow.date, order: .reverse)]

    func filter(_ rows: [ExpenseRow], currency: String) -> [ExpenseRow] {
        let query = searchText.searchNormalized
        return rows.filter { row in
            row.currencyCode == currency
                && (query.isEmpty || row.title.searchNormalized.contains(query) || row.examinationTitle.searchNormalized.contains(query)
                    || row.laboratoryName.searchNormalized.contains(query))
                && (categoryFilter == nil || row.category == categoryFilter)
                && (laboratoryFilter == nil || row.laboratoryName == laboratoryFilter)
        }
        .sorted(using: sortOrder)
    }
}
