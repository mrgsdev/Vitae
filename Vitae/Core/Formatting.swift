import Foundation

/// Единые правила отображения чисел, дат и денег.
enum Fmt {
    static func number(_ value: Double, maxFraction: Int = 3) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(
            .number
                .precision(.fractionLength(0...maxFraction))
                .grouping(.never)
                .locale(AppLocale.locale)
        )
    }

    static func optionalNumber(_ value: Double?, maxFraction: Int = 3) -> String {
        value.map { number($0, maxFraction: maxFraction) } ?? ""
    }

    /// Число со знаком. Используется «−» (U+2212) для отрицательных значений.
    static func signedNumber(_ value: Double, maxFraction: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        let body = number(abs(value), maxFraction: maxFraction)
        if value > 0 { return "+" + body }
        if value < 0 { return "−" + body }
        return body
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return signedNumber(value, maxFraction: 1) + " %"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.locale))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(AppLocale.locale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(AppLocale.locale))
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(AppLocale.locale))
    }

    static func monthShort(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(AppLocale.locale))
    }

    static func money(_ amount: Decimal, currency: String) -> String {
        amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(0...2))
                .locale(AppLocale.locale)
        )
    }

    /// Суммы в разных валютах никогда не складываются — выводятся через «+».
    static func moneyTotals(_ totals: [String: Decimal], emptyText: String = "—") -> String {
        let items = totals.filter { $0.value != 0 }
            .sorted { CurrencyCatalog.order($0.key) < CurrencyCatalog.order($1.key) }
        guard !items.isEmpty else { return emptyText }
        return items.map { money($0.value, currency: $0.key) }.joined(separator: " + ")
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func count(_ value: Int, one: String, few: String, many: String) -> String {
        "\(value) " + plural(value, one: one, few: few, many: many)
    }

    /// Русские формы множественного числа.
    static func plural(_ value: Int, one: String, few: String, many: String) -> String {
        let n = abs(value) % 100
        let n1 = n % 10
        if n > 10 && n < 20 { return many }
        if n1 > 1 && n1 < 5 { return few }
        if n1 == 1 { return one }
        return many
    }
}
