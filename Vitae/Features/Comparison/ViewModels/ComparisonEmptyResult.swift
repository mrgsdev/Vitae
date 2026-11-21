import Foundation

/// Почему в таблице сравнения не осталось ни одной строки. Без пояснения пустая таблица
/// выглядит как сбой: не видно, что все показатели отсеял фильтр «Показать» или поиск.
enum ComparisonEmptyResult: Equatable {
    /// В обоих обследованиях нет внесённых результатов.
    case noResults
    /// Ни одна строка не подходит под фильтр «Показать».
    case filter(ComparisonFilter)
    /// Строки под фильтр есть, но поиск по названию ничего не нашёл.
    case search(String)

    /// `rows` — все строки сравнения, `visible` — оставшиеся после фильтра и поиска.
    /// `nil`, если показывать есть что.
    init?(rows: [ComparisonRow], visible: [ComparisonRow], filter: ComparisonFilter, searchText: String) {
        guard visible.isEmpty else { return nil }
        if rows.isEmpty {
            self = .noResults
        } else if !rows.contains(where: filter.includes) {
            self = .filter(filter)
        } else {
            self = .search(searchText)
        }
    }
}

extension ComparisonFilter {
    /// Чем объяснить, что под фильтр не попал ни один показатель.
    var emptyExplanation: String {
        switch self {
        case .all: "В обследованиях нет показателей."
        case .common: "У выбранных обследований нет общих показателей."
        case .statusChanged: "Ни у одного общего показателя статус не изменился."
        case .deviations: "Ни один показатель не выходит за референсные значения."
        }
    }
}
