import Foundation
import Testing
@testable import Vitae

private let dayA = AppLocale.calendar.date(from: DateComponents(year: 2025, month: 6, day: 25, hour: 9))!
private let dayB = AppLocale.calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 9))!

private func snapshot(_ code: String, _ raw: String, on date: Date, upper: Double = 10) -> ResultSnapshot {
    ResultSnapshot(date: date, testCode: code, testName: code, rawValue: raw, unit: "г/л",
                   reference: ReferenceRange(lower: 1, upper: upper))
}

/// Строки, отобранные так же, как в `ComparisonView`.
private func visible(_ rows: [ComparisonRow], _ filter: ComparisonFilter, _ search: String = "") -> [ComparisonRow] {
    rows.filter { filter.includes($0) && $0.testName.matchesSearch(search) }
}

@Suite("Сравнение: пустой результат")
struct ComparisonEmptyResultTests {
    /// Два общих показателя в норме и по одному только в A и только в B — как в данных `-uiTestingFixture`,
    /// где статус между выбранными обследованиями не меняется.
    private let rows = ComparisonEngine.compare(
        [snapshot("hemoglobin", "5", on: dayA), snapshot("ferritin", "4", on: dayA), snapshot("glucose", "5", on: dayA)],
        [snapshot("hemoglobin", "6", on: dayB), snapshot("ferritin", "3", on: dayB), snapshot("vitd", "7", on: dayB)]
    )

    @Test func filterWithoutMatchesExplainsFilter() {
        #expect(!rows.contains { $0.statusChanged })
        let result = ComparisonEmptyResult(rows: rows, visible: visible(rows, .statusChanged),
                                           filter: .statusChanged, searchText: "")
        #expect(result == .filter(.statusChanged))
    }

    @Test func filterWinsOverSearchWhenFilterAloneLeavesNothing() {
        let result = ComparisonEmptyResult(rows: rows, visible: visible(rows, .deviations, "ферритин"),
                                           filter: .deviations, searchText: "ферритин")
        #expect(result == .filter(.deviations))
    }

    @Test func searchWithoutMatchesExplainsSearch() {
        let result = ComparisonEmptyResult(rows: rows, visible: visible(rows, .common, "кальций"),
                                           filter: .common, searchText: "кальций")
        #expect(result == .search("кальций"))
    }

    @Test func noRowsAtAllIsNotBlamedOnFilter() {
        let result = ComparisonEmptyResult(rows: [], visible: [], filter: .statusChanged, searchText: "")
        #expect(result == .noResults)
    }

    @Test(arguments: ComparisonFilter.allCases)
    func nonEmptyTableNeedsNoExplanation(filter: ComparisonFilter) {
        let changed = ComparisonEngine.compare([snapshot("hemoglobin", "5", on: dayA)],
                                               [snapshot("hemoglobin", "12", on: dayB)])
        #expect(changed[0].statusChanged)
        #expect(ComparisonEmptyResult(rows: changed, visible: visible(changed, filter),
                                      filter: filter, searchText: "") == nil)
    }

    @Test func everyFilterHasExplanation() {
        for filter in ComparisonFilter.allCases {
            #expect(!filter.emptyExplanation.isEmpty)
        }
    }
}
