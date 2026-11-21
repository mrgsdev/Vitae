import SwiftUI

/// Пояснение поверх пустой таблицы сравнения.
struct ComparisonEmptyView: View {
    let result: ComparisonEmptyResult
    /// Сбросить фильтр «Показать» на «Все показатели».
    let showAll: () -> Void

    var body: some View {
        switch result {
        case .noResults:
            EmptyStateView(title: "Нет результатов для сравнения", systemImage: "rectangle.split.2x1",
                           message: "В выбранных обследованиях пока нет внесённых значений.")
        case .filter(let filter):
            EmptyStateView(title: "Нет показателей под фильтр",
                           systemImage: "line.3.horizontal.decrease.circle",
                           message: "\(filter.emptyExplanation) Выберите другой вариант в списке «Показать».",
                           actionTitle: "Показать все показатели", action: showAll)
        case .search(let text):
            ContentUnavailableView.search(text: text)
        }
    }
}
