import Foundation

enum DynamicsMode: String, CaseIterable, Identifiable {
    case indicator, comparison
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indicator: "Показатель"
        case .comparison: "Сравнение обследований"
        }
    }
}

enum ComparisonFilter: String, CaseIterable, Identifiable {
    case all, common, statusChanged, deviations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все показатели"
        case .common: "Только общие"
        case .statusChanged: "Изменился статус"
        case .deviations: "Есть отклонения"
        }
    }

    func includes(_ row: ComparisonRow) -> Bool {
        switch self {
        case .all: true
        case .common: row.isInBoth
        case .statusChanged: row.statusChanged
        case .deviations: (row.a?.status.isDeviation ?? false) || (row.b?.status.isDeviation ?? false)
        }
    }
}

struct DynamicsState {
    var mode: DynamicsMode = .indicator
    var selectedCode: String?
    var period: DynamicsPeriod = .all
    /// Выбранная единица отображения для каждого показателя.
    var units: [String: String] = [:]
    var searchText = ""
    var comparisonA: UUID?
    var comparisonB: UUID?
    var comparisonFilter: ComparisonFilter = .all
}

/// Сводка по показателю для списка в разделе «Динамика».
struct IndicatorSummary: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let category: TestCategory
    let latest: ResultSnapshot
    let count: Int

    static func build(from results: [ResultSnapshot]) -> [IndicatorSummary] {
        Dictionary(grouping: results.filter(\.isAnalyzable), by: \.testCode).compactMap { code, items in
            guard let latest = items.max(by: { ($0.date, $0.sortIndex) < ($1.date, $1.sortIndex) }) else { return nil }
            return IndicatorSummary(code: code, name: latest.testName, category: latest.category, latest: latest, count: items.count)
        }
        .sorted { ($0.category.sortIndex, $0.name) < ($1.category.sortIndex, $1.name) }
    }
}
