import Foundation

/// Строка таблицы обследований (снимок для сортировки и фильтрации).
struct ExaminationRow: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let title: String
    let laboratoryName: String
    let resultCount: Int
    let deviationCount: Int
    let costTotals: [String: Decimal]
    let costSortKey: Decimal
    let status: ExaminationStatus
    let statusSortKey: Int
    let year: Int
    let searchText: String

    init(_ exam: Examination) {
        id = exam.id
        date = exam.date
        title = exam.title
        laboratoryName = exam.laboratory?.name ?? ""
        resultCount = exam.results.count
        deviationCount = exam.deviationCount
        costTotals = exam.costTotals
        let primary = costTotals.sorted { CurrencyCatalog.order($0.key) < CurrencyCatalog.order($1.key) }.first?.value
        costSortKey = primary ?? 0
        status = exam.status
        statusSortKey = exam.status.sortIndex
        year = exam.date.year()
        searchText = ([exam.title, exam.laboratory?.name ?? "", exam.comment, Fmt.shortDate(exam.date)]
                      + exam.results.map(\.testName)).joined(separator: " ").searchNormalized
    }

    var costText: String { Fmt.moneyTotals(costTotals) }
}

struct ExaminationGroup: Identifiable {
    var id: Int { year }
    let year: Int
    let rows: [ExaminationRow]

    var title: String {
        "\(year) · " + Fmt.count(rows.count, one: "обследование", few: "обследования", many: "обследований")
    }
}

/// Состояние списка обследований (сохраняется при переключении разделов).
struct ExaminationsListState {
    var searchText = ""
    var statusFilter: ExaminationStatus?
    var laboratoryFilter: String?
    var yearFilter: Int?
    var onlyDeviations = false
    var groupByYear = true
    var showInspector = false
    var selection: Set<UUID> = []
    var sortOrder: [KeyPathComparator<ExaminationRow>] = [KeyPathComparator(\ExaminationRow.date, order: .reverse)]

    var hasActiveFilters: Bool {
        statusFilter != nil || laboratoryFilter != nil || yearFilter != nil || onlyDeviations
    }

    mutating func resetFilters() {
        statusFilter = nil
        laboratoryFilter = nil
        yearFilter = nil
        onlyDeviations = false
    }

    func apply(to rows: [ExaminationRow]) -> [ExaminationRow] {
        let query = searchText.searchNormalized
        return rows.filter { row in
            (query.isEmpty || row.searchText.contains(query))
                && (statusFilter == nil || row.status == statusFilter)
                && (laboratoryFilter == nil || row.laboratoryName == laboratoryFilter)
                && (yearFilter == nil || row.year == yearFilter)
                && (!onlyDeviations || row.deviationCount > 0)
        }
        .sorted(using: sortOrder)
    }

    func groups(for rows: [ExaminationRow]) -> [ExaminationGroup] {
        let grouped = Dictionary(grouping: rows, by: \.year)
        let descending = sortOrder.first?.keyPath == \ExaminationRow.date ? sortOrder.first?.order == .reverse : true
        return grouped.keys.sorted(by: descending ? (>) : (<)).map { ExaminationGroup(year: $0, rows: grouped[$0] ?? []) }
    }
}
