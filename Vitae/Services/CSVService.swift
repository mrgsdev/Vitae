import Foundation

struct CSVTable: Equatable {
    var headers: [String]
    var rows: [[String]]
    var delimiter: Character
}

/// Чтение и запись CSV (RFC 4180, разделитель «;» для совместимости с русским Excel).
enum CSV {
    static let defaultDelimiter: Character = ";"

    static func escape(_ field: String, delimiter: Character = defaultDelimiter) -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// UTF-8 с BOM, чтобы Excel корректно открывал кириллицу.
    static func encode(headers: [String], rows: [[String]], delimiter: Character = defaultDelimiter) -> Data {
        let lines = ([headers] + rows).map { $0.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    static func decodeText(_ data: Data) -> String? {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }
        if let text = String(data: body, encoding: .utf8) { return text }
        if let text = String(data: body, encoding: .windowsCP1251) { return text }
        return String(data: body, encoding: .isoLatin1)
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [";", "\t", ","]
        var best: Character = defaultDelimiter
        var bestCount = 0
        for candidate in candidates {
            var count = 0
            var inQuotes = false
            for ch in firstLine {
                if ch == "\"" { inQuotes.toggle() } else if ch == candidate && !inQuotes { count += 1 }
            }
            if count > bestCount { best = candidate; bestCount = count }
        }
        return best
    }

    static func parse(_ text: String, delimiter: Character? = nil) -> CSVTable {
        let delimiter = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == delimiter {
                endField()
            } else if ch == "\n" || ch == "\r\n" {
                endRow()
            } else if ch == "\r" {
                if let next = iterator.next(), next != "\n" { pending = next }
                endRow()
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }

        let headers = rows.first?.map(\.trimmed) ?? []
        let body = Array(rows.dropFirst()).map { $0.map(\.trimmed) }
        return CSVTable(headers: headers, rows: body, delimiter: delimiter)
    }
}

// MARK: - Export

enum CSVExporter {
    static let resultHeaders = ["Дата", "Обследование", "Лаборатория", "Код", "Показатель", "Комплекс", "Результат",
                                "Единица", "Нижняя граница", "Верхняя граница", "Референс", "Статус"]
    static let expenseHeaders = ["Дата", "Название", "Категория", "Обследование", "Лаборатория", "Сумма", "Валюта"]

    static func results(_ results: [ResultSnapshot]) -> Data {
        let rows = results.sorted { ($0.date, $0.sortIndex) < ($1.date, $1.sortIndex) }.map { r in
            [Fmt.shortDate(r.date), r.examinationTitle, r.laboratoryName ?? "", r.testCode, r.testName, r.panelName ?? "",
             r.rawValue, r.unit, Fmt.optionalNumber(r.reference.lower), Fmt.optionalNumber(r.reference.upper),
             r.reference.text ?? "", r.status.title]
        }
        return CSV.encode(headers: resultHeaders, rows: rows)
    }

    static func expenses(_ expenses: [ExpenseSnapshot]) -> Data {
        let rows = expenses.sorted { $0.date < $1.date }.map { e in
            [Fmt.shortDate(e.date), e.title, e.category.title, e.examinationTitle ?? "", e.laboratoryName ?? "",
             e.amount.editingString, e.currencyCode]
        }
        return CSV.encode(headers: expenseHeaders, rows: rows)
    }
}

// MARK: - Import

enum CSVField: String, CaseIterable, Identifiable, Hashable {
    case date, examination, laboratory, testName, value, unit, lower, upper, reference, price, currency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: "Дата"
        case .examination: "Обследование"
        case .laboratory: "Лаборатория"
        case .testName: "Показатель"
        case .value: "Результат"
        case .unit: "Единица"
        case .lower: "Нижняя граница"
        case .upper: "Верхняя граница"
        case .reference: "Референс (строкой)"
        case .price: "Стоимость"
        case .currency: "Валюта"
        }
    }

    var isRequired: Bool { self == .date || self == .testName || self == .value }

    var headerHints: [String] {
        switch self {
        case .date: ["дата", "date", "дата взятия"]
        case .examination: ["обследование", "examination", "панель", "исследование"]
        case .laboratory: ["лаборатория", "laboratory", "lab"]
        case .testName: ["показатель", "анализ", "название", "test", "name", "indicator"]
        case .value: ["результат", "значение", "result", "value"]
        case .unit: ["единица", "ед", "ед. изм", "unit", "units"]
        case .lower: ["нижняя граница", "мин", "min", "lower", "от"]
        case .upper: ["верхняя граница", "макс", "max", "upper", "до"]
        case .reference: ["референс", "норма", "reference", "range", "референсные значения"]
        case .price: ["стоимость", "цена", "сумма", "price", "cost"]
        case .currency: ["валюта", "currency"]
        }
    }
}

struct CSVMapping: Equatable {
    var columns: [CSVField: Int] = [:]

    static func autoDetect(headers: [String]) -> CSVMapping {
        var mapping = CSVMapping()
        let normalized = headers.map(\.searchNormalized)
        for field in CSVField.allCases {
            if let index = normalized.firstIndex(where: { header in field.headerHints.contains(header) }),
               !mapping.columns.values.contains(index) {
                mapping.columns[field] = index
                continue
            }
            if let index = normalized.firstIndex(where: { header in
                field.headerHints.contains { hint in hint.count > 3 && header.contains(hint) }
            }), !mapping.columns.values.contains(index) {
                mapping.columns[field] = index
            }
        }
        return mapping
    }

    var missingRequired: [CSVField] { CSVField.allCases.filter { $0.isRequired && columns[$0] == nil } }
}

struct CSVImportResult {
    var drafts: [ExaminationDraft]
    var skippedRows: [Int]
    var unmatchedNames: Set<String>
}

enum CSVImporter {
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmed
        guard !s.isEmpty else { return nil }
        if let date = LabReportParser.firstDate(in: s) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: String(s.prefix(10)))
    }

    /// Группирует строки CSV в черновики обследований по дате, названию и лаборатории.
    static func makeDrafts(table: CSVTable, mapping: CSVMapping, catalog: CatalogIndex, defaultCurrency: String) -> CSVImportResult {
        let matcher = CatalogMatcher(catalog: catalog)
        var groups: [String: ExaminationDraft] = [:]
        var order: [String] = []
        var skipped: [Int] = []
        var unmatched = Set<String>()

        func cell(_ row: [String], _ field: CSVField) -> String {
            guard let index = mapping.columns[field], index < row.count else { return "" }
            return row[index].trimmed
        }

        for (index, row) in table.rows.enumerated() {
            let name = cell(row, .testName)
            let value = cell(row, .value)
            guard let date = parseDate(cell(row, .date)), !name.isEmpty, !value.isEmpty else {
                skipped.append(index + 2)
                continue
            }
            let lab = cell(row, .laboratory)
            let title = cell(row, .examination)
            let day = AppLocale.calendar.startOfDay(for: date)
            let key = "\(day.timeIntervalSince1970)|\(title.searchNormalized)|\(lab.searchNormalized)"
            if groups[key] == nil {
                let currency = cell(row, .currency).uppercased()
                groups[key] = ExaminationDraft(title: title.isEmpty ? "Импорт CSV · \(Fmt.date(date))" : title, date: date,
                                               laboratoryName: lab, comment: "Импортировано из CSV",
                                               currencyCode: CurrencyCatalog.codes.contains(currency) ? currency : defaultCurrency)
                order.append(key)
            }

            let entry = matcher.exactMatch(name)
            if entry == nil { unmatched.insert(name) }
            var reference = ReferenceRange.parse(cell(row, .reference))
            if let lower = NumberParsing.double(cell(row, .lower)) { reference.lower = lower }
            if let upper = NumberParsing.double(cell(row, .upper)) { reference.upper = upper }
            let parsed = ParsedValue.parse(value)

            var entryRow = EntryRow(groupID: UUID(), kind: .single, testCode: entry?.code, name: entry?.name ?? name,
                                    category: entry?.category ?? .other,
                                    isQualitative: entry?.isQualitative ?? (!parsed.isNumeric && reference.text != nil),
                                    value: value, unit: cell(row, .unit).nilIfEmpty ?? entry?.unit ?? "",
                                    lower: Fmt.optionalNumber(reference.lower), upper: Fmt.optionalNumber(reference.upper),
                                    referenceText: reference.text ?? "")
            if let price = NumberParsing.decimal(cell(row, .price)) { entryRow.price = price.editingString }
            groups[key]?.rows.append(entryRow)
        }
        return CSVImportResult(drafts: order.compactMap { groups[$0] }, skippedRows: skipped, unmatchedNames: unmatched)
    }
}
