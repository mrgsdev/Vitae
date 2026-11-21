import Foundation
import SwiftData

// MARK: - UserProfile

/// Профиль владельца данных. Пол и возраст не используются для автоматической оценки результатов.
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var birthDate: Date?
    var sexRaw: String
    var notes: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", birthDate: Date? = nil, sex: BiologicalSex = .unspecified, notes: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.sexRaw = sex.rawValue
        self.notes = notes
        self.createdAt = createdAt
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }
}

// MARK: - Laboratory

@Model
final class Laboratory {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var phone: String
    var website: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Examination.laboratory)
    var examinations: [Examination] = []

    @Relationship(deleteRule: .nullify, inverse: \Expense.laboratory)
    var expenses: [Expense] = []

    init(id: UUID = UUID(), name: String, address: String = "", phone: String = "", website: String = "", notes: String = "", createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.address = address
        self.phone = phone
        self.website = website
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - LabTest

/// Показатель или комплексное исследование из справочника.
/// Связь с результатами — по стабильному коду, поэтому удаление пользовательского
/// показателя не затрагивает историю (в результатах хранятся снимки названий и единиц).
@Model
final class LabTest {
    @Attribute(.unique) var code: String
    var name: String
    var shortName: String
    var categoryRaw: String
    var defaultUnit: String
    var aliases: [String]
    var details: String
    var isQualitative: Bool
    var isPanel: Bool
    var panelCode: String?
    var isCustom: Bool
    var isFavorite: Bool
    var sortOrder: Int
    var createdAt: Date

    init(code: String, name: String, shortName: String = "", category: TestCategory, defaultUnit: String = "",
         aliases: [String] = [], details: String = "", isQualitative: Bool = false, isPanel: Bool = false,
         panelCode: String? = nil, isCustom: Bool = false, isFavorite: Bool = false, sortOrder: Int = 0, createdAt: Date = .now) {
        self.code = code
        self.name = name
        self.shortName = shortName
        self.categoryRaw = category.rawValue
        self.defaultUnit = defaultUnit
        self.aliases = aliases
        self.details = details
        self.isQualitative = isQualitative
        self.isPanel = isPanel
        self.panelCode = panelCode
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var category: TestCategory {
        get { TestCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var displayName: String {
        shortName.isEmpty || shortName == name ? name : "\(name) (\(shortName))"
    }
}

// MARK: - Examination

@Model
final class Examination {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var comment: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    var laboratory: Laboratory?

    @Relationship(deleteRule: .cascade, inverse: \TestResult.examination)
    var results: [TestResult] = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.examination)
    var expenses: [Expense] = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.examination)
    var attachments: [Attachment] = []

    init(id: UUID = UUID(), title: String, date: Date, comment: String = "", status: ExaminationStatus = .completed,
         createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.date = date
        self.comment = comment
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ExaminationStatus {
        get { ExaminationStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var sortedResults: [TestResult] {
        results.sorted { ($0.sortIndex, $0.testName) < ($1.sortIndex, $1.testName) }
    }

    var deviationCount: Int { results.filter { $0.status.isDeviation }.count }

    var costTotals: [String: Decimal] {
        expenses.reduce(into: [:]) { $0[$1.currencyCode, default: 0] += $1.amount }
    }

    var laboratoryName: String { laboratory?.name ?? "" }
}

// MARK: - TestResult

/// Результат измерения. Хранит собственные референсы, единицы и снимки названий,
/// чтобы история оставалась корректной при изменении справочника.
@Model
final class TestResult {
    @Attribute(.unique) var id: UUID
    var testCode: String
    var testName: String
    var categoryRaw: String
    var panelCode: String?
    var panelName: String?
    var groupID: UUID
    var sortIndex: Int
    var rawValue: String
    var numericValue: Double?
    var comparatorRaw: String?
    var textValue: String?
    var unit: String
    var referenceLower: Double?
    var referenceUpper: Double?
    var referenceText: String?
    var isQualitative: Bool
    var note: String

    var examination: Examination?

    init(id: UUID = UUID(), testCode: String, testName: String, category: TestCategory, panelCode: String? = nil,
         panelName: String? = nil, groupID: UUID = UUID(), sortIndex: Int = 0, rawValue: String, unit: String,
         reference: ReferenceRange = ReferenceRange(), isQualitative: Bool = false, note: String = "") {
        let parsed = ParsedValue.parse(rawValue)
        self.id = id
        self.testCode = testCode
        self.testName = testName
        self.categoryRaw = category.rawValue
        self.panelCode = panelCode
        self.panelName = panelName
        self.groupID = groupID
        self.sortIndex = sortIndex
        self.rawValue = rawValue.trimmed
        self.numericValue = parsed.numeric
        self.comparatorRaw = parsed.comparator?.rawValue
        self.textValue = parsed.text
        self.unit = unit
        self.referenceLower = reference.lower
        self.referenceUpper = reference.upper
        self.referenceText = reference.text
        self.isQualitative = isQualitative
        self.note = note
    }

    var category: TestCategory { TestCategory(rawValue: categoryRaw) ?? .other }

    var parsedValue: ParsedValue {
        ParsedValue(numeric: numericValue, comparator: comparatorRaw.flatMap(Comparator.init(rawValue:)), text: textValue)
    }

    var reference: ReferenceRange {
        ReferenceRange(lower: referenceLower, upper: referenceUpper, text: referenceText)
    }

    var status: ResultStatus { ReferenceEvaluator.status(for: parsedValue, reference: reference) }

    var date: Date { examination?.date ?? .distantPast }
}

// MARK: - Expense

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var title: String
    var amount: Decimal
    var currencyCode: String
    var date: Date
    var categoryRaw: String
    var testCode: String?
    var groupID: UUID?
    var note: String
    var createdAt: Date

    var examination: Examination?
    var laboratory: Laboratory?

    init(id: UUID = UUID(), title: String, amount: Decimal, currencyCode: String, date: Date,
         category: ExpenseCategory = .test, testCode: String? = nil, groupID: UUID? = nil, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.categoryRaw = category.rawValue
        self.testCode = testCode
        self.groupID = groupID
        self.note = note
        self.createdAt = createdAt
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Attachment

/// Метаданные документа. Сам файл хранится в Application Support (FileStorageService), а не в базе.
@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var originalFileName: String
    var storedFileName: String
    var contentTypeIdentifier: String
    var fileSize: Int64
    var note: String
    var createdAt: Date

    var examination: Examination?

    init(id: UUID = UUID(), originalFileName: String, storedFileName: String, contentTypeIdentifier: String,
         fileSize: Int64, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileSize = fileSize
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Reminder

@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var repeatRaw: String
    var isCompleted: Bool
    var completedAt: Date?
    var testCodes: [String]
    var notificationsEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, notes: String = "", dueDate: Date, repeatRule: ReminderRepeat = .none,
         isCompleted: Bool = false, completedAt: Date? = nil, testCodes: [String] = [], notificationsEnabled: Bool = true, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.repeatRaw = ReminderSchedule(rule: repeatRule, anchoredTo: dueDate).raw
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.testCodes = testCodes
        self.notificationsEnabled = notificationsEnabled
        self.createdAt = createdAt
    }

    /// Правило повтора с исходным днём месяца (см. `ReminderSchedule`).
    var schedule: ReminderSchedule {
        get { ReminderSchedule(raw: repeatRaw) }
        set { repeatRaw = newValue.raw }
    }

    var repeatRule: ReminderRepeat { schedule.rule }
}
