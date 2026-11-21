import SwiftUI

/// Фильтр обзора показателей по статусу последнего значения.
enum IndicatorFilter: String, CaseIterable, Identifiable {
    case all, deviations, inRange, below, above, noReference
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Все"
        case .deviations: "Вне референса"
        case .inRange: "В пределах"
        case .below: "Ниже"
        case .above: "Выше"
        case .noReference: "Без референса"
        }
    }

    var color: Color {
        switch self {
        case .all: .accentColor
        case .deviations: .orange
        case .inRange: ResultStatus.inRange.color
        case .below: ResultStatus.below.color
        case .above: ResultStatus.above.color
        case .noReference: ResultStatus.noReference.color
        }
    }

    func includes(_ status: ResultStatus) -> Bool {
        switch self {
        case .all: true
        case .deviations: status.isDeviation
        case .inRange: status == .inRange
        case .below: status == .below
        case .above: status == .above
        case .noReference: status == .noReference
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
    var filter: IndicatorFilter = .all
    var period: DynamicsPeriod = .all
    /// Выбранная единица отображения для каждого показателя.
    var units: [String: String] = [:]
    var searchText = ""
}

struct ComparisonState {
    var examinationA: UUID?
    var examinationB: UUID?
    var filter: ComparisonFilter = .all
    var searchText = ""

    /// Меняет обследования местами одним изменением состояния. Вызов `swap(&state.a, &state.b)`
    /// на свойстве @Observable-модели — два одновременных доступа к нему, и Swift аварийно
    /// завершает приложение («Simultaneous accesses … requires exclusive access»).
    mutating func swapExaminations() {
        (examinationA, examinationB) = (examinationB, examinationA)
    }
}

/// Сводка по показателю для списка в разделе «Динамика».
struct IndicatorSummary: Identifiable, Hashable {
    var id: String { code }
    let code: String
    /// Название из справочника: результаты хранят названия из бланков, и у одного показателя
    /// они разные («Холестерин ЛПВП» и «Холестерин-ЛПВП»). Карточка объединяет все измерения,
    /// поэтому её заголовок не должен меняться после импорта бланка другой лаборатории.
    /// Название последнего бланка — только если показателя уже нет в справочнике.
    let name: String
    let category: TestCategory
    let latest: ResultSnapshot
    let count: Int
    /// Все названия показателя для поиска: справочник (название, краткое, синонимы) и бланки.
    let searchNames: [String]

    static func build(from results: [ResultSnapshot], catalog: CatalogIndex) -> [IndicatorSummary] {
        Dictionary(grouping: results.filter(\.isAnalyzable), by: \.testCode).compactMap { code, items in
            guard let latest = items.max(by: { ($0.date, $0.sortIndex) < ($1.date, $1.sortIndex) }) else { return nil }
            let entry = catalog.entry(code)
            let catalogNames = entry.map { [$0.name, $0.shortName] + $0.aliases } ?? []
            let names = (catalogNames + items.map(\.testName)).filter { !$0.isEmpty }.uniqued(by: \.searchNormalized)
            return IndicatorSummary(code: code, name: entry?.name ?? latest.testName, category: latest.category,
                                    latest: latest, count: items.count, searchNames: names)
        }
        .sorted { ($0.category.sortIndex, $0.name) < ($1.category.sortIndex, $1.name) }
    }

    func matches(_ query: String) -> Bool {
        query.searchNormalized.isEmpty || searchNames.contains { $0.matchesSearch(query) }
    }
}
