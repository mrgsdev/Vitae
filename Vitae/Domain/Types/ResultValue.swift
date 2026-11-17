import Foundation

/// Знак сравнения перед числом: «<0,5», «>100».
enum Comparator: String, Codable, CaseIterable, Sendable {
    case less = "<"
    case lessOrEqual = "≤"
    case greater = ">"
    case greaterOrEqual = "≥"
}

/// Разобранное значение результата: число (возможно со знаком сравнения) или текст.
struct ParsedValue: Hashable, Sendable {
    var numeric: Double?
    var comparator: Comparator?
    var text: String?

    var isEmpty: Bool { numeric == nil && (text?.trimmed.isEmpty ?? true) }
    var isExactNumber: Bool { numeric != nil && comparator == nil }
    var isNumeric: Bool { numeric != nil }

    static func parse(_ raw: String) -> ParsedValue {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return ParsedValue() }

        var body = trimmed
        var comparator: Comparator?
        let prefixes: [(String, Comparator)] = [
            ("<=", .lessOrEqual), (">=", .greaterOrEqual), ("≤", .lessOrEqual), ("≥", .greaterOrEqual),
            ("<", .less), (">", .greater), ("менее", .less), ("более", .greater), ("меньше", .less), ("больше", .greater)
        ]
        let lower = body.lowercased()
        for (prefix, value) in prefixes where lower.hasPrefix(prefix) {
            comparator = value
            body = String(body.dropFirst(prefix.count)).trimmed
            break
        }
        if let number = NumberParsing.double(body) {
            return ParsedValue(numeric: number, comparator: comparator, text: nil)
        }
        return ParsedValue(numeric: nil, comparator: nil, text: trimmed)
    }
}

/// Референсный интервал конкретной лаборатории (хранится вместе с результатом).
struct ReferenceRange: Hashable, Codable, Sendable {
    var lower: Double?
    var upper: Double?
    /// Текстовый референс для качественных показателей («отрицательно»).
    var text: String?

    init(lower: Double? = nil, upper: Double? = nil, text: String? = nil) {
        self.lower = lower
        self.upper = upper
        self.text = text?.nilIfEmpty
    }

    var hasNumericBounds: Bool { lower != nil || upper != nil }
    var isEmpty: Bool { !hasNumericBounds && text == nil }

    var displayText: String {
        switch (lower, upper) {
        case let (l?, u?): return "\(Fmt.number(l))–\(Fmt.number(u))"
        case let (l?, nil): return "≥ \(Fmt.number(l))"
        case let (nil, u?): return "≤ \(Fmt.number(u))"
        default: return text ?? "—"
        }
    }

    /// Разбор строки референса: «3,5–5,5», «< 5», «до 5», «> 1», «от 1», «отрицательно».
    static func parse(_ raw: String) -> ReferenceRange {
        let s = raw.trimmed
        guard !s.isEmpty else { return ReferenceRange() }
        let number = #"([0-9]+(?:[.,][0-9]+)?)"#

        if let match = s.firstMatch(of: try! Regex(number + #"\s*(?:-|–|—|\.\.\.|…)\s*"# + number)) {
            let l = NumberParsing.double(String(match.output[1].substring ?? ""))
            let u = NumberParsing.double(String(match.output[2].substring ?? ""))
            if let l, let u, l <= u { return ReferenceRange(lower: l, upper: u) }
        }
        let lower = s.lowercased()
        if let match = lower.firstMatch(of: try! Regex(#"^(?:<=|<|≤|до|менее|меньше)\s*"# + number)) {
            return ReferenceRange(upper: NumberParsing.double(String(match.output[1].substring ?? "")))
        }
        if let match = lower.firstMatch(of: try! Regex(#"^(?:>=|>|≥|от|более|больше|свыше)\s*"# + number)) {
            return ReferenceRange(lower: NumberParsing.double(String(match.output[1].substring ?? "")))
        }
        if NumberParsing.double(s) != nil { return ReferenceRange() }
        return ReferenceRange(text: s)
    }
}

/// Сравнение качественных результатов с учётом распространённых синонимов.
enum QualitativeMatcher {
    private static let negative: Set<String> = [
        "отрицательно", "отрицательный", "отр", "отриц", "negative", "neg", "не обнаружено", "не обнаружен",
        "не обнаружены", "не выявлено", "не выявлены", "нет", "abs", "absent", "not detected", "-"
    ]
    private static let positive: Set<String> = [
        "положительно", "положительный", "пол", "полож", "positive", "pos", "обнаружено", "обнаружен",
        "выявлено", "detected", "present", "+"
    ]

    static func canonical(_ value: String) -> String {
        var s = value.searchNormalized
        while s.hasSuffix(".") { s.removeLast() }
        if negative.contains(s) { return "negative" }
        if positive.contains(s) { return "positive" }
        return s
    }

    static func matches(_ actual: String, _ expected: String) -> Bool {
        canonical(actual) == canonical(expected)
    }
}
