import Foundation

struct MonthlyTotal: Identifiable, Hashable, Sendable {
    var id: Date { month }
    let month: Date
    let amount: Decimal
}

struct YearlyTotal: Identifiable, Hashable, Sendable {
    var id: Int { year }
    let year: Int
    let amount: Decimal
}

struct LaboratoryTotal: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let amount: Decimal
    let count: Int
}

struct PricePoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let amount: Decimal
    let laboratoryName: String?
}

/// Позиция, для которой отслеживается история цен.
struct TrackedPrice: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let purchases: Int
    let firstAmount: Decimal
    let lastAmount: Decimal
    let lastDate: Date

    var change: Decimal { lastAmount - firstAmount }
    var percentChange: Double? {
        firstAmount == 0 ? nil : (lastAmount - firstAmount).doubleValue / firstAmount.doubleValue * 100
    }
}

/// Денежные расчёты на Decimal. Разные валюты никогда не складываются без явного курса.
enum ExpenseAnalytics {
    static func totals(_ items: [ExpenseSnapshot]) -> [String: Decimal] {
        items.reduce(into: [:]) { $0[$1.currencyCode, default: 0] += $1.amount }
    }

    static func currencies(in items: [ExpenseSnapshot]) -> [String] {
        Set(items.map(\.currencyCode)).sorted { CurrencyCatalog.order($0) < CurrencyCatalog.order($1) }
    }

    static func total(_ items: [ExpenseSnapshot], currency: String, in interval: DateInterval? = nil) -> Decimal {
        items.filter { $0.currencyCode == currency && (interval?.contains($0.date) ?? true) }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    static func yearInterval(_ year: Int, calendar: Calendar = AppLocale.calendar) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        return DateInterval(start: start, end: end.addingTimeInterval(-0.001))
    }

    static func monthInterval(containing date: Date, calendar: Calendar = AppLocale.calendar) -> DateInterval? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return DateInterval(start: interval.start, end: interval.end.addingTimeInterval(-0.001))
    }

    static func monthlyTotals(_ items: [ExpenseSnapshot], currency: String, year: Int,
                              calendar: Calendar = AppLocale.calendar) -> [MonthlyTotal] {
        (1...12).compactMap { month -> MonthlyTotal? in
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let interval = monthInterval(containing: start, calendar: calendar) else { return nil }
            return MonthlyTotal(month: start, amount: total(items, currency: currency, in: interval))
        }
    }

    static func yearlyTotals(_ items: [ExpenseSnapshot], currency: String,
                             calendar: Calendar = AppLocale.calendar) -> [YearlyTotal] {
        let filtered = items.filter { $0.currencyCode == currency }
        let grouped = Dictionary(grouping: filtered) { calendar.component(.year, from: $0.date) }
        return grouped.map { YearlyTotal(year: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.year < $1.year }
    }

    static func byLaboratory(_ items: [ExpenseSnapshot], currency: String) -> [LaboratoryTotal] {
        let filtered = items.filter { $0.currencyCode == currency }
        let grouped = Dictionary(grouping: filtered) { $0.laboratoryName?.nilIfEmpty ?? "Без лаборатории" }
        return grouped.map { LaboratoryTotal(name: $0.key, amount: $0.value.reduce(Decimal(0)) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
    }

    static func priceHistory(_ items: [ExpenseSnapshot], key: String, currency: String) -> [PricePoint] {
        items.filter { $0.priceKey == key && $0.currencyCode == currency }
            .sorted { $0.date < $1.date }
            .map { PricePoint(id: $0.id, date: $0.date, amount: $0.amount, laboratoryName: $0.laboratoryName) }
    }

    static func trackedPrices(_ items: [ExpenseSnapshot], currency: String) -> [TrackedPrice] {
        let filtered = items.filter { $0.currencyCode == currency && $0.category != .other }
        let grouped = Dictionary(grouping: filtered, by: \.priceKey)
        return grouped.compactMap { key, values -> TrackedPrice? in
            let sorted = values.sorted { $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            return TrackedPrice(key: key, title: last.title, purchases: sorted.count,
                                firstAmount: first.amount, lastAmount: last.amount, lastDate: last.date)
        }
        .sorted { ($0.purchases, $0.lastDate) > ($1.purchases, $1.lastDate) }
    }

    /// Итог в основной валюте по курсам пользователя. nil, если для какой-то валюты курса нет.
    static func convertedTotal(_ totals: [String: Decimal], to base: String, rates: [String: Decimal]) -> Decimal? {
        var sum = Decimal(0)
        for (currency, amount) in totals {
            if currency == base {
                sum += amount
            } else if let rate = rates[currency], rate > 0 {
                sum += amount * rate
            } else {
                return nil
            }
        }
        return sum.rounded(scale: 2)
    }
}
