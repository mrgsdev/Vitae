import Foundation

/// Данные главного экрана, рассчитанные из базы.
struct DashboardModel {
    let lastExamination: Examination?
    let summary: DashboardSummary
    let expenses: [ExpenseSnapshot]
    let currentYear: Int
    let draftCount: Int

    init(examinations: [Examination], results: [TestResult], expenses: [Expense], now: Date = .now) {
        lastExamination = examinations.first { $0.status != .draft }
        summary = DashboardAnalytics.summarize(results.map(ResultSnapshot.init))
        self.expenses = expenses.map(ExpenseSnapshot.init)
        currentYear = now.year()
        draftCount = examinations.filter { $0.status == .draft }.count
    }

    var yearTotals: [String: Decimal] {
        guard let interval = ExpenseAnalytics.yearInterval(currentYear) else { return [:] }
        return ExpenseAnalytics.totals(expenses.filter { interval.contains($0.date) })
    }

    var previousYearTotals: [String: Decimal] {
        guard let interval = ExpenseAnalytics.yearInterval(currentYear - 1) else { return [:] }
        return ExpenseAnalytics.totals(expenses.filter { interval.contains($0.date) })
    }

    /// Основная валюта для графика: валюта с наибольшим числом трат в этом году, иначе из настроек.
    var primaryCurrency: String {
        let thisYear = yearTotals
        if let top = thisYear.max(by: { $0.value < $1.value })?.key { return top }
        return ExpenseAnalytics.currencies(in: expenses).first ?? AppSettings.defaultCurrency
    }

    var monthlyTotals: [MonthlyTotal] {
        ExpenseAnalytics.monthlyTotals(expenses, currency: primaryCurrency, year: currentYear)
    }
}

/// Результаты быстрого поиска на главной.
struct QuickSearchResults {
    let examinations: [Examination]
    let indicators: [ResultSnapshot]

    init(query: String, examinations: [Examination], results: [TestResult]) {
        let q = query.searchNormalized
        self.examinations = examinations.filter { exam in
            exam.title.matchesSearch(q) || exam.laboratoryName.matchesSearch(q) || exam.comment.matchesSearch(q)
                || Fmt.shortDate(exam.date).contains(q)
        }
        let snapshots = results.map(ResultSnapshot.init).filter { $0.isAnalyzable && $0.testName.matchesSearch(q) }
        let latest = Dictionary(grouping: snapshots, by: \.testCode).values.compactMap { $0.max { $0.date < $1.date } }
        indicators = latest.sorted { $0.testName < $1.testName }
    }

    var isEmpty: Bool { examinations.isEmpty && indicators.isEmpty }
}
