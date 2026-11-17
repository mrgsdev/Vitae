import Foundation

/// Неизменяемые снимки данных для расчётов. Логика работает со снимками,
/// поэтому её легко тестировать без SwiftData.
struct ResultSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let examinationID: UUID?
    let examinationTitle: String
    let examinationStatus: ExaminationStatus
    let date: Date
    let laboratoryName: String?
    let testCode: String
    let testName: String
    let category: TestCategory
    let panelCode: String?
    let panelName: String?
    let sortIndex: Int
    let rawValue: String
    let value: ParsedValue
    let unit: String
    let reference: ReferenceRange
    let isQualitative: Bool
    let status: ResultStatus

    init(id: UUID = UUID(), examinationID: UUID? = nil, examinationTitle: String = "", examinationStatus: ExaminationStatus = .completed,
         date: Date, laboratoryName: String? = nil, testCode: String, testName: String, category: TestCategory = .other,
         panelCode: String? = nil, panelName: String? = nil, sortIndex: Int = 0, rawValue: String, unit: String,
         reference: ReferenceRange = ReferenceRange(), isQualitative: Bool = false) {
        self.id = id
        self.examinationID = examinationID
        self.examinationTitle = examinationTitle
        self.examinationStatus = examinationStatus
        self.date = date
        self.laboratoryName = laboratoryName
        self.testCode = testCode
        self.testName = testName
        self.category = category
        self.panelCode = panelCode
        self.panelName = panelName
        self.sortIndex = sortIndex
        self.rawValue = rawValue
        self.value = ParsedValue.parse(rawValue)
        self.unit = unit
        self.reference = reference
        self.isQualitative = isQualitative
        self.status = ReferenceEvaluator.status(for: value, reference: reference)
    }

    init(_ result: TestResult) {
        let exam = result.examination
        id = result.id
        examinationID = exam?.id
        examinationTitle = exam?.title ?? ""
        examinationStatus = exam?.status ?? .completed
        date = exam?.date ?? .distantPast
        laboratoryName = exam?.laboratory?.name
        testCode = result.testCode
        testName = result.testName
        category = result.category
        panelCode = result.panelCode
        panelName = result.panelName
        sortIndex = result.sortIndex
        rawValue = result.rawValue
        value = result.parsedValue
        unit = result.unit
        reference = result.reference
        isQualitative = result.isQualitative
        status = ReferenceEvaluator.status(for: value, reference: reference)
    }

    /// Результат пригоден для аналитики: обследование не черновик и значение внесено.
    var isAnalyzable: Bool { examinationStatus != .draft && !value.isEmpty }

    var displayValue: String {
        if let number = value.numeric {
            let base = Fmt.number(number)
            return (value.comparator.map { $0.rawValue + " " } ?? "") + base
        }
        return value.text ?? "—"
    }
}

struct ExpenseSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let title: String
    let amount: Decimal
    let currencyCode: String
    let category: ExpenseCategory
    let testCode: String?
    let examinationID: UUID?
    let examinationTitle: String?
    let laboratoryName: String?

    init(id: UUID = UUID(), date: Date, title: String, amount: Decimal, currencyCode: String, category: ExpenseCategory = .test,
         testCode: String? = nil, examinationID: UUID? = nil, examinationTitle: String? = nil, laboratoryName: String? = nil) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.category = category
        self.testCode = testCode
        self.examinationID = examinationID
        self.examinationTitle = examinationTitle
        self.laboratoryName = laboratoryName
    }

    init(_ expense: Expense) {
        id = expense.id
        date = expense.examination?.date ?? expense.date
        title = expense.title
        amount = expense.amount
        currencyCode = expense.currencyCode
        category = expense.category
        testCode = expense.testCode
        examinationID = expense.examination?.id
        examinationTitle = expense.examination?.title
        laboratoryName = expense.laboratory?.name ?? expense.examination?.laboratory?.name
    }

    /// Ключ для истории цен: код показателя, а для услуг — нормализованное название.
    var priceKey: String { testCode ?? "title:" + title.searchNormalized }
}

/// Облегчённое представление записи справочника.
struct CatalogEntry: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let name: String
    let shortName: String
    let category: TestCategory
    let unit: String
    let aliases: [String]
    let details: String
    let isQualitative: Bool
    let isPanel: Bool
    let panelCode: String?
    let isCustom: Bool
    let isFavorite: Bool
    let sortOrder: Int

    init(code: String, name: String, shortName: String = "", category: TestCategory = .other, unit: String = "",
         aliases: [String] = [], details: String = "", isQualitative: Bool = false, isPanel: Bool = false,
         panelCode: String? = nil, isCustom: Bool = false, isFavorite: Bool = false, sortOrder: Int = 0) {
        self.code = code
        self.name = name
        self.shortName = shortName
        self.category = category
        self.unit = unit
        self.aliases = aliases
        self.details = details
        self.isQualitative = isQualitative
        self.isPanel = isPanel
        self.panelCode = panelCode
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
    }

    init(_ test: LabTest) {
        self.init(code: test.code, name: test.name, shortName: test.shortName, category: test.category,
                  unit: test.defaultUnit, aliases: test.aliases, details: test.details, isQualitative: test.isQualitative,
                  isPanel: test.isPanel, panelCode: test.panelCode, isCustom: test.isCustom, isFavorite: test.isFavorite,
                  sortOrder: test.sortOrder)
    }

    var displayName: String {
        shortName.isEmpty || shortName == name ? name : "\(name) (\(shortName))"
    }

    func matches(_ query: String) -> Bool {
        let q = query.searchNormalized
        guard !q.isEmpty else { return true }
        if name.searchNormalized.contains(q) || shortName.searchNormalized.contains(q) { return true }
        return aliases.contains { $0.searchNormalized.contains(q) }
    }
}

struct CatalogIndex: Sendable {
    let entries: [CatalogEntry]
    let byCode: [String: CatalogEntry]

    init(entries: [CatalogEntry]) {
        self.entries = entries.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        var map: [String: CatalogEntry] = [:]
        for entry in entries { map[entry.code] = entry }
        byCode = map
    }

    init(tests: [LabTest]) {
        self.init(entries: tests.map(CatalogEntry.init))
    }

    func components(of panelCode: String) -> [CatalogEntry] {
        entries.filter { $0.panelCode == panelCode }
    }

    var roots: [CatalogEntry] { entries.filter { $0.panelCode == nil } }

    func entry(_ code: String?) -> CatalogEntry? {
        guard let code else { return nil }
        return byCode[code]
    }
}
