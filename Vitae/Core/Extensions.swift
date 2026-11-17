import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// Нормализация для поиска и сопоставления: нижний регистр, «ё» → «е», схлопнутые пробелы.
    var searchNormalized: String {
        lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func matchesSearch(_ query: String) -> Bool {
        let q = query.searchNormalized
        guard !q.isEmpty else { return true }
        return searchNormalized.contains(q)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

extension Array {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

extension Date {
    func startOfDay(calendar: Calendar = AppLocale.calendar) -> Date {
        calendar.startOfDay(for: self)
    }

    func year(calendar: Calendar = AppLocale.calendar) -> Int {
        calendar.component(.year, from: self)
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Строка для полей ввода (без разделителей групп, с десятичной запятой).
    var editingString: String {
        formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(AppLocale.locale))
    }

    /// Машинное представление для JSON/CSV (точка как разделитель).
    var plainString: String {
        NSDecimalNumber(decimal: self).description(withLocale: AppLocale.posix)
    }

    func rounded(scale: Int = 2) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
