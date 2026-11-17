import Foundation

/// Строка таблицы ввода результатов.
struct EntryRow: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Отдельный показатель (значение + стоимость).
        case single
        /// Заголовок комплексного исследования (только стоимость).
        case panel
        /// Компонент комплекса (только значение).
        case component
        /// Услуга без результата: взятие крови, выезд и т. п.
        case service

        var hasValue: Bool { self == .single || self == .component }
        var hasPrice: Bool { self != .component }
    }

    var id: UUID = UUID()
    var groupID: UUID
    var kind: Kind
    var testCode: String?
    var name: String
    var category: TestCategory = .other
    var isQualitative: Bool = false
    var value: String = ""
    var unit: String = ""
    var lower: String = ""
    var upper: String = ""
    var referenceText: String = ""
    var price: String = ""
    /// Подсказка в поле стоимости (прошлая цена). Не сохраняется как расход.
    var pricePlaceholder: String = ""
    /// Отметка строки для массовых действий.
    var isMarked: Bool = false

    var parsedValue: ParsedValue { ParsedValue.parse(value) }

    var reference: ReferenceRange {
        ReferenceRange(lower: NumberParsing.double(lower), upper: NumberParsing.double(upper), text: referenceText)
    }

    var status: ResultStatus? {
        kind.hasValue ? ReferenceEvaluator.status(for: parsedValue, reference: reference) : nil
    }

    var priceValue: Decimal? { NumberParsing.decimal(price) }

    var isNameEditable: Bool { kind == .service || testCode == nil }

    var hasEnteredData: Bool {
        !value.trimmed.isEmpty || !price.trimmed.isEmpty
    }
}

/// Черновик обследования — состояние редактора до сохранения в базу.
struct ExaminationDraft: Equatable, Sendable {
    var examinationID: UUID?
    var title: String = ""
    var date: Date = .now
    var laboratoryName: String = ""
    var comment: String = ""
    var currencyCode: String = "RUB"
    var rows: [EntryRow] = []

    var valueRows: [EntryRow] { rows.filter { $0.kind.hasValue } }
    var filledCount: Int { valueRows.filter { !$0.value.trimmed.isEmpty }.count }
    var isComplete: Bool { !valueRows.isEmpty && filledCount == valueRows.count }
    var deviationCount: Int { valueRows.filter { $0.status?.isDeviation == true }.count }

    var totalPrice: Decimal {
        rows.filter(\.kind.hasPrice).compactMap(\.priceValue).reduce(Decimal(0), +)
    }

    var selectedCodes: Set<String> {
        Set(rows.compactMap { row -> String? in
            guard row.kind != .service else { return nil }
            return row.testCode
        })
    }

    static func defaultTitle(for date: Date) -> String {
        "Обследование \(Fmt.date(date))"
    }
}

/// Проблема в строке черновика.
struct EntryIssue: Identifiable, Hashable, Sendable {
    enum Field: String, Sendable { case name, value, unit, lower, upper, reference, price }
    enum Severity: Sendable { case error, warning }

    var id: String { "\(rowID)-\(field.rawValue)" }
    let rowID: UUID
    let field: Field
    let severity: Severity
    let message: String
}

enum DraftValidator {
    static func issues(in draft: ExaminationDraft) -> [EntryIssue] {
        draft.rows.flatMap(issues(in:))
    }

    static func errors(in draft: ExaminationDraft) -> [EntryIssue] {
        issues(in: draft).filter { $0.severity == .error }
    }

    static func issues(in row: EntryRow) -> [EntryIssue] {
        var result: [EntryIssue] = []
        if row.isNameEditable && row.name.trimmed.isEmpty {
            result.append(EntryIssue(rowID: row.id, field: .name, severity: .error, message: "Укажите название"))
        }
        if row.kind.hasValue {
            let lower = row.lower.trimmed, upper = row.upper.trimmed
            if !lower.isEmpty && NumberParsing.double(lower) == nil {
                result.append(EntryIssue(rowID: row.id, field: .lower, severity: .error, message: "Нижняя граница должна быть числом"))
            }
            if !upper.isEmpty && NumberParsing.double(upper) == nil {
                result.append(EntryIssue(rowID: row.id, field: .upper, severity: .error, message: "Верхняя граница должна быть числом"))
            }
            if let l = NumberParsing.double(lower), let u = NumberParsing.double(upper), l > u {
                result.append(EntryIssue(rowID: row.id, field: .upper, severity: .error, message: "Нижняя граница больше верхней"))
            }
            if !row.isQualitative, !row.value.trimmed.isEmpty, !row.parsedValue.isNumeric {
                result.append(EntryIssue(rowID: row.id, field: .value, severity: .warning,
                                         message: "Значение не распознано как число и будет сохранено как текст"))
            }
        }
        if row.kind.hasPrice {
            let price = row.price.trimmed
            if !price.isEmpty {
                if let amount = NumberParsing.decimal(price) {
                    if amount < 0 {
                        result.append(EntryIssue(rowID: row.id, field: .price, severity: .error, message: "Стоимость не может быть отрицательной"))
                    }
                } else {
                    result.append(EntryIssue(rowID: row.id, field: .price, severity: .error, message: "Стоимость должна быть числом"))
                }
            }
        }
        return result
    }
}
