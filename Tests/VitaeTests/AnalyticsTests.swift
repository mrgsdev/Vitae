import Foundation
import Testing
@testable import Vitae

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    AppLocale.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
}

private func result(_ code: String, _ raw: String, _ unit: String, _ date: Date, lower: Double? = nil, upper: Double? = nil,
                    exam: UUID = UUID(), status: ExaminationStatus = .completed, lab: String = "Лаб") -> ResultSnapshot {
    ResultSnapshot(examinationID: exam, examinationTitle: "Обследование", examinationStatus: status, date: date, laboratoryName: lab,
                   testCode: code, testName: code, rawValue: raw, unit: unit, reference: ReferenceRange(lower: lower, upper: upper))
}

@Suite("Динамика")
struct DynamicsTests {
    @Test func seriesConvertsCompatibleUnitsAndSeparatesIncompatible() {
        let history = [
            result("glucose", "90", "мг/дл", day(2023, 1, 10), lower: 74, upper: 106),
            result("glucose", "5,0", "ммоль/л", day(2024, 1, 10), lower: 4.1, upper: 5.9),
            result("glucose", "5,6", "ммоль/л", day(2025, 1, 10), lower: 4.1, upper: 5.9),
            result("glucose", "7", "непонятно", day(2025, 2, 10))
        ]
        let series = DynamicsCalculator.series(from: history)
        #expect(series.unit == "ммоль/л")
        #expect(series.points.count == 3)
        #expect(series.incompatible.count == 1)
        let first = series.points[0]
        #expect(first.wasConverted)
        #expect(abs(first.value - 4.995) < 0.01)
        #expect(abs((first.reference.lower ?? 0) - 4.107) < 0.01)
    }

    @Test func statistics() throws {
        let history = [
            result("ferritin", "18", "нг/мл", day(2023, 4, 1)),
            result("ferritin", "42", "нг/мл", day(2023, 10, 1)),
            result("ferritin", "88", "нг/мл", day(2025, 6, 1)),
            result("ferritin", ">500", "нг/мл", day(2025, 7, 1))
        ]
        let stats = try #require(DynamicsCalculator.series(from: history).statistics)
        #expect(stats.first == 18)
        #expect(stats.last == 88)
        #expect(stats.minimum == 18)
        #expect(stats.maximum == 88)
        #expect(abs(stats.mean - 49.333) < 0.01)
        #expect(stats.absoluteChange == 70)
        #expect(abs((stats.percentChange ?? 0) - 388.89) < 0.01)
        #expect(stats.count == 3, "значения со знаком сравнения не входят в статистику")
    }

    @Test func periodFilterAndDraftsExcluded() {
        let now = day(2026, 1, 1)
        let history = [
            result("vitd", "19", "нг/мл", day(2022, 1, 1)),
            result("vitd", "34", "нг/мл", day(2025, 10, 1)),
            result("vitd", "41", "нг/мл", day(2025, 12, 1), status: .draft)
        ]
        let series = DynamicsCalculator.series(from: history, period: .sixMonths, now: now)
        #expect(series.points.map(\.value) == [34])
        #expect(DynamicsCalculator.series(from: history, period: .all, now: now).points.count == 2)
    }

    @Test func latestChangeUsesComparablePreviousValue() throws {
        let history = [
            result("cbc.hgb", "140", "г/л", day(2023, 1, 1)),
            result("cbc.hgb", "15", "г/дл", day(2024, 1, 1))
        ]
        let change = try #require(DynamicsCalculator.latestChange(for: history))
        #expect(change.previousValue == 14)
        #expect(change.currentValue == 15)
        #expect(change.absoluteChange == 1)
        #expect(change.unit == "г/дл")
    }

    @Test func dashboardSummaryCountsLatestValues() {
        let results = [
            result("a", "1", "u", day(2023, 1, 1), lower: 2, upper: 3),
            result("a", "2,5", "u", day(2024, 1, 1), lower: 2, upper: 3),
            result("b", "10", "u", day(2024, 1, 1), lower: 0, upper: 5),
            result("c", "1", "u", day(2024, 1, 1), lower: 2, upper: nil),
            result("d", "1", "u", day(2024, 1, 1))
        ]
        let summary = DashboardAnalytics.summarize(results)
        #expect(summary.total == 4)
        #expect(summary.count(.inRange) == 1)
        #expect(summary.count(.above) == 1)
        #expect(summary.count(.below) == 1)
        #expect(summary.count(.noReference) == 1)
        #expect(summary.deviations.count == 2)
        #expect(summary.changes.count == 1)
    }
}

@Suite("Сравнение обследований")
struct ComparisonTests {
    @Test func comparesWithConversionAndDetectsIncompatibility() throws {
        let a = UUID(), b = UUID()
        let first = [
            result("glucose", "5,0", "ммоль/л", day(2024, 1, 1), lower: 4.1, upper: 5.9, exam: a),
            result("lpa", "30", "мг/дл", day(2024, 1, 1), upper: 30, exam: a),
            result("cbc.hgb", "140", "г/л", day(2024, 1, 1), lower: 130, upper: 160, exam: a),
            result("tsh", "2", "мкМЕ/мл", day(2024, 1, 1), exam: a)
        ]
        let second = [
            result("glucose", "108", "мг/дл", day(2025, 1, 1), lower: 74, upper: 106, exam: b),
            result("lpa", "82", "нмоль/л", day(2025, 1, 1), upper: 75, exam: b),
            result("cbc.hgb", "150", "г/л", day(2025, 1, 1), lower: 130, upper: 160, exam: b),
            result("vitd", "41", "нг/мл", day(2025, 1, 1), exam: b)
        ]
        let rows = ComparisonEngine.compare(first, second)
        let glucose = try #require(rows.first { $0.testCode == "glucose" })
        #expect(glucose.compatibility == .converted(fromUnit: "мг/дл"))
        #expect(abs((glucose.valueB ?? 0) - 5.995) < 0.01)
        #expect(abs((glucose.difference ?? 0) - 0.995) < 0.01)
        #expect(glucose.statusChanged)

        let lpa = try #require(rows.first { $0.testCode == "lpa" })
        #expect(lpa.compatibility == .incompatible)
        #expect(lpa.difference == nil)

        let hgb = try #require(rows.first { $0.testCode == "cbc.hgb" })
        #expect(hgb.compatibility == .same)
        #expect(hgb.difference == 10)
        #expect(abs((hgb.percentChange ?? 0) - 7.142857) < 0.0001)

        #expect(rows.first { $0.testCode == "tsh" }?.compatibility == .missing)
        #expect(rows.first { $0.testCode == "vitd" }?.compatibility == .missing)
    }

    @Test func qualitativeRows() {
        let a = [ResultSnapshot(date: day(2024, 1, 1), testCode: "urine.protein", testName: "Белок", rawValue: "отрицательно", unit: "",
                                reference: ReferenceRange(text: "отрицательно"))]
        let b = [ResultSnapshot(date: day(2025, 1, 1), testCode: "urine.protein", testName: "Белок", rawValue: "следы", unit: "",
                                reference: ReferenceRange(text: "отрицательно"))]
        let row = ComparisonEngine.compare(a, b)[0]
        #expect(row.compatibility == .qualitative)
        #expect(row.statusChanged)
        #expect(row.difference == nil)
    }
}

@Suite("Расходы")
struct ExpenseTests {
    private let items: [ExpenseSnapshot] = [
        ExpenseSnapshot(date: day(2024, 3, 1), title: "Ферритин", amount: Decimal(string: "650")!, currencyCode: "RUB", testCode: "ferritin", laboratoryName: "Инвитро"),
        ExpenseSnapshot(date: day(2025, 3, 1), title: "Ферритин", amount: Decimal(string: "850")!, currencyCode: "RUB", testCode: "ferritin", laboratoryName: "Инвитро"),
        ExpenseSnapshot(date: day(2025, 3, 1), title: "Взятие крови", amount: Decimal(string: "199.99")!, currencyCode: "RUB", category: .service, laboratoryName: "Инвитро"),
        ExpenseSnapshot(date: day(2025, 5, 2), title: "Vitamin D", amount: Decimal(string: "45.50")!, currencyCode: "USD", testCode: "vitd", laboratoryName: "Quest"),
        ExpenseSnapshot(date: day(2025, 5, 20), title: "Ферритин", amount: Decimal(string: "900")!, currencyCode: "RUB", testCode: "ferritin", laboratoryName: "Гемотест")
    ]

    @Test func totalsArePerCurrency() {
        let totals = ExpenseAnalytics.totals(items)
        #expect(totals["RUB"] == Decimal(string: "2599.99"))
        #expect(totals["USD"] == Decimal(string: "45.5"))
        #expect(totals.count == 2)
        #expect(Fmt.moneyTotals(totals).contains("+"), "разные валюты выводятся отдельно")
    }

    @Test func decimalPrecision() {
        let cents = (0..<10).map { _ in ExpenseSnapshot(date: day(2025, 1, 1), title: "x", amount: Decimal(string: "0.1")!, currencyCode: "RUB") }
        #expect(ExpenseAnalytics.total(cents, currency: "RUB") == Decimal(1))
    }

    @Test func monthlyYearlyAndLaboratories() {
        let monthly = ExpenseAnalytics.monthlyTotals(items, currency: "RUB", year: 2025)
        #expect(monthly.count == 12)
        #expect(monthly[2].amount == Decimal(string: "1049.99"))
        #expect(monthly[4].amount == Decimal(900))
        #expect(monthly[4 - 1].amount == 0)
        let yearly = ExpenseAnalytics.yearlyTotals(items, currency: "RUB")
        #expect(yearly.map(\.year) == [2024, 2025])
        let labs = ExpenseAnalytics.byLaboratory(items, currency: "RUB")
        #expect(labs.first?.name == "Инвитро")
        #expect(labs.first?.amount == Decimal(string: "1699.99"))
    }

    @Test func priceHistoryOfSingleTest() throws {
        let history = ExpenseAnalytics.priceHistory(items, key: "ferritin", currency: "RUB")
        #expect(history.map(\.amount) == [650, 850, 900].map { Decimal($0) })
        let tracked = try #require(ExpenseAnalytics.trackedPrices(items, currency: "RUB").first { $0.key == "ferritin" })
        #expect(tracked.purchases == 3)
        #expect(tracked.change == 250)
        #expect(abs((tracked.percentChange ?? 0) - 38.4615) < 0.001)
    }

    @Test func conversionRequiresRates() {
        let totals = ExpenseAnalytics.totals(items)
        #expect(ExpenseAnalytics.convertedTotal(totals, to: "RUB", rates: [:]) == nil)
        let converted = ExpenseAnalytics.convertedTotal(totals, to: "RUB", rates: ["USD": Decimal(90)])
        #expect(converted == Decimal(string: "6694.99"))
    }
}

@MainActor
@Suite("Сравнение: выбор обследований")
struct ComparisonStateTests {
    /// Кнопка «Поменять местами» меняет выбор в модели навигации без двойного доступа к свойству.
    @Test func swapExaminationsInNavigationModel() {
        let navigation = NavigationModel()
        let a = UUID(), b = UUID()
        navigation.compare(a, b)
        navigation.comparison.swapExaminations()
        #expect(navigation.comparison.examinationA == b)
        #expect(navigation.comparison.examinationB == a)
        navigation.comparison.examinationB = nil
        navigation.comparison.swapExaminations()
        #expect(navigation.comparison.examinationA == nil)
        #expect(navigation.comparison.examinationB == b)
    }
}
