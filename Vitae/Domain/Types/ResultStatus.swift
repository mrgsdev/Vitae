import Foundation

/// Статус результата относительно референса лаборатории.
/// Статус не является оценкой здоровья: приложение не ставит диагнозов.
enum ResultStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inRange
    case below
    case above
    /// Качественный результат не совпадает с текстовым референсом.
    case outsideReference
    /// Нет референса или по имеющимся данным оценить нельзя.
    case noReference
    /// Результат ещё не внесён.
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inRange: "В пределах референса"
        case .below: "Ниже референса"
        case .above: "Выше референса"
        case .outsideReference: "Не совпадает с референсом"
        case .noReference: "Нет данных для оценки"
        case .pending: "Нет результата"
        }
    }

    var shortTitle: String {
        switch self {
        case .inRange: "В пределах"
        case .below: "Ниже"
        case .above: "Выше"
        case .outsideReference: "Не совпадает"
        case .noReference: "Нет данных"
        case .pending: "Ожидается"
        }
    }

    var symbolName: String {
        switch self {
        case .inRange: "checkmark.circle.fill"
        case .below: "arrow.down.circle.fill"
        case .above: "arrow.up.circle.fill"
        case .outsideReference: "exclamationmark.circle.fill"
        case .noReference: "questionmark.circle"
        case .pending: "clock"
        }
    }

    var isDeviation: Bool {
        self == .below || self == .above || self == .outsideReference
    }

    var sortRank: Int {
        switch self {
        case .above: 0
        case .below: 1
        case .outsideReference: 2
        case .noReference: 3
        case .inRange: 4
        case .pending: 5
        }
    }
}

enum ReferenceEvaluator {
    /// Определяет статус значения по референсу.
    /// Для значений со знаком сравнения («<0,5») статус выставляется только когда
    /// весь возможный интервал однозначно попадает в одну из зон; иначе — «Нет данных для оценки».
    /// Лабораторные величины считаются неотрицательными.
    static func status(for value: ParsedValue, reference: ReferenceRange) -> ResultStatus {
        if value.isEmpty { return .pending }

        if let number = value.numeric {
            guard reference.hasNumericBounds else { return .noReference }
            let lower = reference.lower ?? -Double.infinity
            let upper = reference.upper ?? Double.infinity

            var low = number, high = number
            var lowOpen = false, highOpen = false
            switch value.comparator {
            case nil: break
            case .less?: low = min(0, number); high = number; highOpen = true
            case .lessOrEqual?: low = min(0, number); high = number
            case .greater?: low = number; high = .infinity; lowOpen = true
            case .greaterOrEqual?: low = number; high = .infinity
            }

            if high < lower || (high == lower && highOpen && value.comparator != nil) { return .below }
            if low > upper || (low == upper && lowOpen) { return .above }
            if low >= lower && high <= upper { return .inRange }
            return .noReference
        }

        guard let expected = reference.text?.nilIfEmpty, let actual = value.text?.nilIfEmpty else {
            return .noReference
        }
        return QualitativeMatcher.matches(actual, expected) ? .inRange : .outsideReference
    }

    static func status(rawValue: String, reference: ReferenceRange) -> ResultStatus {
        status(for: ParsedValue.parse(rawValue), reference: reference)
    }
}
