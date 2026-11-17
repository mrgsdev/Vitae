import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - DTO

struct BackupEnvelope: Codable, Equatable {
    var format: String
    var formatVersion: Int
    var schemaVersion: String
    var appVersion: String
    var exportedAt: Date
    var checksum: String
    var payload: BackupPayload
}

struct BackupPayload: Codable, Equatable {
    var profile: ProfileDTO?
    var laboratories: [LaboratoryDTO]
    var labTests: [LabTestDTO]
    var examinations: [ExaminationDTO]
    var standaloneExpenses: [ExpenseDTO]
    var reminders: [ReminderDTO]
}

struct ProfileDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date?
    var sex: String
    var notes: String
}

struct LaboratoryDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var phone: String
    var website: String
    var notes: String
}

struct LabTestDTO: Codable, Equatable {
    var code: String
    var name: String
    var shortName: String
    var category: String
    var unit: String
    var aliases: [String]
    var details: String
    var isQualitative: Bool
    var isPanel: Bool
    var panelCode: String?
    var isCustom: Bool
    var isFavorite: Bool
    var sortOrder: Int
}

struct TestResultDTO: Codable, Equatable {
    var id: UUID
    var testCode: String
    var testName: String
    var category: String
    var panelCode: String?
    var panelName: String?
    var groupID: UUID
    var sortIndex: Int
    var rawValue: String
    var unit: String
    var referenceLower: Double?
    var referenceUpper: Double?
    var referenceText: String?
    var isQualitative: Bool
    var note: String
}

struct ExpenseDTO: Codable, Equatable {
    var id: UUID
    var title: String
    /// Сумма хранится строкой, чтобы не терять точность Decimal.
    var amount: String
    var currency: String
    var date: Date
    var category: String
    var testCode: String?
    var groupID: UUID?
    var laboratoryID: UUID?
    var note: String
}

struct AttachmentDTO: Codable, Equatable {
    var id: UUID
    var originalFileName: String
    var contentType: String
    var fileSize: Int64
    var note: String
    var createdAt: Date
    /// Содержимое файла (Base64), если при экспорте включены документы.
    var data: String?
}

struct ExaminationDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var date: Date
    var comment: String
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var laboratoryID: UUID?
    var results: [TestResultDTO]
    var expenses: [ExpenseDTO]
    var attachments: [AttachmentDTO]
}

struct ReminderDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var repeatRule: String
    var isCompleted: Bool
    var completedAt: Date?
    var testCodes: [String]
    var notificationsEnabled: Bool
}

// MARK: - Errors & report

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case unsupportedVersion(Int)
    case checksumMismatch
    case integrity(String)

    var errorDescription: String? {
        switch self {
        case .notABackup: "Файл не является резервной копией Vitae."
        case .unsupportedVersion(let v): "Резервная копия создана более новой версией приложения (формат \(v)). Обновите Vitae."
        case .checksumMismatch: "Контрольная сумма не совпадает: файл повреждён или изменён."
        case .integrity(let message): "Нарушена целостность данных: \(message)"
        }
    }
}

struct BackupSummary: Equatable {
    var examinations: Int
    var results: Int
    var expenses: Int
    var attachments: Int
    var attachmentsWithData: Int
    var laboratories: Int
    var customTests: Int
    var reminders: Int
    var exportedAt: Date
    var schemaVersion: String
}

struct RestoreReport: Equatable {
    var addedExaminations = 0
    var skippedExaminations = 0
    var addedResults = 0
    var addedExpenses = 0
    var addedAttachments = 0
    var missingAttachmentFiles = 0
    var addedLaboratories = 0
    var addedTests = 0
    var addedReminders = 0
}

enum RestoreMode: String, CaseIterable, Identifiable {
    case merge, replace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .merge: "Объединить с текущими данными"
        case .replace: "Заменить все данные"
        }
    }
}

// MARK: - Service

/// Полный экспорт базы в JSON с версионированием и контрольной суммой SHA-256.
@MainActor
struct BackupService {
    static let formatName = "VitaeBackup"
    static let formatVersion = 1

    let context: ModelContext
    let fileStorage: FileStorageService

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoFormatter.date(from: string) { return date }
            if let date = ISO8601DateFormatter().date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неверный формат даты")
        }
        return decoder
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func checksum(of payload: BackupPayload) throws -> String {
        let data = try makeEncoder().encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Export

    func makePayload(includeAttachments: Bool) throws -> BackupPayload {
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
        let labs = try context.fetch(FetchDescriptor<Laboratory>(sortBy: [SortDescriptor(\.name)]))
        let tests = try context.fetch(FetchDescriptor<LabTest>(sortBy: [SortDescriptor(\.sortOrder)]))
        let exams = try context.fetch(FetchDescriptor<Examination>(sortBy: [SortDescriptor(\.date)]))
        let expenses = try context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
        let reminders = try context.fetch(FetchDescriptor<Reminder>(sortBy: [SortDescriptor(\.dueDate)]))

        return BackupPayload(
            profile: profile.map { ProfileDTO(id: $0.id, name: $0.name, birthDate: $0.birthDate, sex: $0.sexRaw, notes: $0.notes) },
            laboratories: labs.map { LaboratoryDTO(id: $0.id, name: $0.name, address: $0.address, phone: $0.phone, website: $0.website, notes: $0.notes) },
            labTests: tests.filter { $0.isCustom || $0.isFavorite }.map(Self.dto),
            examinations: try exams.map { try examinationDTO($0, includeAttachments: includeAttachments) },
            standaloneExpenses: expenses.filter { $0.examination == nil }.map(Self.dto),
            reminders: reminders.map {
                ReminderDTO(id: $0.id, title: $0.title, notes: $0.notes, dueDate: $0.dueDate, repeatRule: $0.repeatRaw,
                            isCompleted: $0.isCompleted, completedAt: $0.completedAt, testCodes: $0.testCodes,
                            notificationsEnabled: $0.notificationsEnabled)
            }
        )
    }

    private static func dto(_ test: LabTest) -> LabTestDTO {
        LabTestDTO(code: test.code, name: test.name, shortName: test.shortName, category: test.categoryRaw, unit: test.defaultUnit,
                   aliases: test.aliases, details: test.details, isQualitative: test.isQualitative, isPanel: test.isPanel,
                   panelCode: test.panelCode, isCustom: test.isCustom, isFavorite: test.isFavorite, sortOrder: test.sortOrder)
    }

    private static func dto(_ expense: Expense) -> ExpenseDTO {
        ExpenseDTO(id: expense.id, title: expense.title, amount: expense.amount.plainString, currency: expense.currencyCode,
                   date: expense.date, category: expense.categoryRaw, testCode: expense.testCode, groupID: expense.groupID,
                   laboratoryID: expense.laboratory?.id, note: expense.note)
    }

    private func examinationDTO(_ exam: Examination, includeAttachments: Bool) throws -> ExaminationDTO {
        ExaminationDTO(
            id: exam.id, title: exam.title, date: exam.date, comment: exam.comment, status: exam.statusRaw,
            createdAt: exam.createdAt, updatedAt: exam.updatedAt, laboratoryID: exam.laboratory?.id,
            results: exam.sortedResults.map {
                TestResultDTO(id: $0.id, testCode: $0.testCode, testName: $0.testName, category: $0.categoryRaw,
                              panelCode: $0.panelCode, panelName: $0.panelName, groupID: $0.groupID, sortIndex: $0.sortIndex,
                              rawValue: $0.rawValue, unit: $0.unit, referenceLower: $0.referenceLower,
                              referenceUpper: $0.referenceUpper, referenceText: $0.referenceText,
                              isQualitative: $0.isQualitative, note: $0.note)
            },
            expenses: exam.expenses.sorted { $0.createdAt < $1.createdAt }.map(Self.dto),
            attachments: exam.attachments.sorted { $0.createdAt < $1.createdAt }.map { attachment in
                let data = includeAttachments ? (try? fileStorage.data(for: attachment.storedFileName))?.base64EncodedString() : nil
                return AttachmentDTO(id: attachment.id, originalFileName: attachment.originalFileName,
                                     contentType: attachment.contentTypeIdentifier, fileSize: attachment.fileSize,
                                     note: attachment.note, createdAt: attachment.createdAt, data: data)
            }
        )
    }

    func exportData(includeAttachments: Bool, now: Date = .now) throws -> Data {
        let payload = try makePayload(includeAttachments: includeAttachments)
        let envelope = BackupEnvelope(
            format: Self.formatName, formatVersion: Self.formatVersion, schemaVersion: VitaeSchema.versionString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            exportedAt: now, checksum: try Self.checksum(of: payload), payload: payload
        )
        let data = try Self.makeEncoder().encode(envelope)
        AppLog.backup.info("Резервная копия сформирована")
        return data
    }

    // MARK: Import

    /// Читает и проверяет файл: формат, версия, контрольная сумма, ссылочная целостность.
    static func read(_ data: Data) throws -> BackupEnvelope {
        struct Header: Decodable { var format: String?; var formatVersion: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == formatName,
              let version = header.formatVersion else { throw BackupError.notABackup }
        guard version <= formatVersion else { throw BackupError.unsupportedVersion(version) }

        let envelope: BackupEnvelope
        do {
            envelope = try makeDecoder().decode(BackupEnvelope.self, from: migrate(data, from: version))
        } catch {
            throw BackupError.integrity("структура файла не соответствует формату")
        }
        guard try checksum(of: envelope.payload) == envelope.checksum else { throw BackupError.checksumMismatch }
        try validateIntegrity(envelope.payload)
        return envelope
    }

    /// Точка расширения для будущих версий формата: старые версии приводятся к текущей.
    static func migrate(_ data: Data, from version: Int) -> Data {
        data
    }

    static func validateIntegrity(_ payload: BackupPayload) throws {
        let labIDs = Set(payload.laboratories.map(\.id))
        guard labIDs.count == payload.laboratories.count else { throw BackupError.integrity("повторяющиеся лаборатории") }

        let examIDs = payload.examinations.map(\.id)
        guard Set(examIDs).count == examIDs.count else { throw BackupError.integrity("повторяющиеся обследования") }

        let resultIDs = payload.examinations.flatMap { $0.results.map(\.id) }
        guard Set(resultIDs).count == resultIDs.count else { throw BackupError.integrity("повторяющиеся результаты") }

        let allExpenses = payload.examinations.flatMap(\.expenses) + payload.standaloneExpenses
        guard Set(allExpenses.map(\.id)).count == allExpenses.count else { throw BackupError.integrity("повторяющиеся расходы") }

        for exam in payload.examinations {
            if let lab = exam.laboratoryID, !labIDs.contains(lab) {
                throw BackupError.integrity("ссылка на несуществующую лабораторию")
            }
            guard ExaminationStatus(rawValue: exam.status) != nil else { throw BackupError.integrity("неизвестный статус обследования") }
            for attachment in exam.attachments {
                if let data = attachment.data, Data(base64Encoded: data) == nil {
                    throw BackupError.integrity("повреждённое вложение")
                }
            }
        }
        for expense in allExpenses {
            guard Decimal(string: expense.amount, locale: AppLocale.posix) != nil else { throw BackupError.integrity("неверная сумма расхода") }
            if let lab = expense.laboratoryID, !labIDs.contains(lab) { throw BackupError.integrity("ссылка на несуществующую лабораторию") }
        }
        let codes = payload.labTests.map(\.code)
        guard Set(codes).count == codes.count else { throw BackupError.integrity("повторяющиеся коды показателей") }
    }

    static func summary(of envelope: BackupEnvelope) -> BackupSummary {
        let p = envelope.payload
        let attachments = p.examinations.flatMap(\.attachments)
        return BackupSummary(
            examinations: p.examinations.count,
            results: p.examinations.reduce(0) { $0 + $1.results.count },
            expenses: p.examinations.reduce(0) { $0 + $1.expenses.count } + p.standaloneExpenses.count,
            attachments: attachments.count,
            attachmentsWithData: attachments.filter { $0.data != nil }.count,
            laboratories: p.laboratories.count,
            customTests: p.labTests.filter(\.isCustom).count,
            reminders: p.reminders.count,
            exportedAt: envelope.exportedAt,
            schemaVersion: envelope.schemaVersion
        )
    }

    // MARK: Restore

    /// Удаляет все пользовательские данные (встроенный справочник сохраняется, избранное сбрасывается).
    func eraseAllData() throws {
        for attachment in try context.fetch(FetchDescriptor<Attachment>()) {
            fileStorage.deleteFile(named: attachment.storedFileName)
        }
        try context.fetch(FetchDescriptor<Examination>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Expense>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Laboratory>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Reminder>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<UserProfile>()).forEach(context.delete)
        for test in try context.fetch(FetchDescriptor<LabTest>()) {
            if test.isCustom { context.delete(test) } else { test.isFavorite = false }
        }
        try context.save()
        context.undoManager?.removeAllActions()
    }

    func restore(_ envelope: BackupEnvelope, mode: RestoreMode) throws -> RestoreReport {
        if mode == .replace { try eraseAllData() }
        var report = RestoreReport()
        let payload = envelope.payload

        if let profile = payload.profile, try context.fetch(FetchDescriptor<UserProfile>()).isEmpty {
            let model = UserProfile(id: profile.id, name: profile.name, birthDate: profile.birthDate,
                                    sex: BiologicalSex(rawValue: profile.sex) ?? .unspecified, notes: profile.notes)
            context.insert(model)
        }

        var labs: [UUID: Laboratory] = [:]
        for lab in try context.fetch(FetchDescriptor<Laboratory>()) { labs[lab.id] = lab }
        for dto in payload.laboratories where labs[dto.id] == nil {
            let lab = Laboratory(id: dto.id, name: dto.name, address: dto.address, phone: dto.phone, website: dto.website, notes: dto.notes)
            context.insert(lab)
            labs[dto.id] = lab
            report.addedLaboratories += 1
        }

        var tests: [String: LabTest] = [:]
        for test in try context.fetch(FetchDescriptor<LabTest>()) { tests[test.code] = test }
        for dto in payload.labTests {
            if let existing = tests[dto.code] {
                if dto.isFavorite { existing.isFavorite = true }
                continue
            }
            guard dto.isCustom else { continue }
            let test = LabTest(code: dto.code, name: dto.name, shortName: dto.shortName,
                               category: TestCategory(rawValue: dto.category) ?? .other, defaultUnit: dto.unit,
                               aliases: dto.aliases, details: dto.details, isQualitative: dto.isQualitative,
                               isPanel: dto.isPanel, panelCode: dto.panelCode, isCustom: true,
                               isFavorite: dto.isFavorite, sortOrder: dto.sortOrder)
            context.insert(test)
            tests[dto.code] = test
            report.addedTests += 1
        }

        let existingExams = Set(try context.fetch(FetchDescriptor<Examination>()).map(\.id))
        let existingExpenses = Set(try context.fetch(FetchDescriptor<Expense>()).map(\.id))
        for dto in payload.examinations {
            guard !existingExams.contains(dto.id) else { report.skippedExaminations += 1; continue }
            let exam = Examination(id: dto.id, title: dto.title, date: dto.date, comment: dto.comment,
                                   status: ExaminationStatus(rawValue: dto.status) ?? .completed,
                                   createdAt: dto.createdAt, updatedAt: dto.updatedAt)
            context.insert(exam)
            exam.laboratory = dto.laboratoryID.flatMap { labs[$0] }
            for r in dto.results {
                let result = TestResult(id: r.id, testCode: r.testCode, testName: r.testName,
                                        category: TestCategory(rawValue: r.category) ?? .other, panelCode: r.panelCode,
                                        panelName: r.panelName, groupID: r.groupID, sortIndex: r.sortIndex,
                                        rawValue: r.rawValue, unit: r.unit,
                                        reference: ReferenceRange(lower: r.referenceLower, upper: r.referenceUpper, text: r.referenceText),
                                        isQualitative: r.isQualitative, note: r.note)
                context.insert(result)
                result.examination = exam
                report.addedResults += 1
            }
            for e in dto.expenses where !existingExpenses.contains(e.id) {
                let expense = makeExpense(e, labs: labs)
                expense.examination = exam
                report.addedExpenses += 1
            }
            for a in dto.attachments {
                guard let base64 = a.data, let data = Data(base64Encoded: base64) else {
                    report.missingAttachmentFiles += 1
                    continue
                }
                let type = UTTypeHelper.type(identifier: a.contentType)
                let stored = try fileStorage.store(data: data, originalFileName: a.originalFileName, contentType: type)
                let attachment = Attachment(id: a.id, originalFileName: a.originalFileName, storedFileName: stored.storedFileName,
                                            contentTypeIdentifier: a.contentType, fileSize: stored.size, note: a.note, createdAt: a.createdAt)
                context.insert(attachment)
                attachment.examination = exam
                report.addedAttachments += 1
            }
            report.addedExaminations += 1
        }

        for e in payload.standaloneExpenses where !existingExpenses.contains(e.id) {
            _ = makeExpense(e, labs: labs)
            report.addedExpenses += 1
        }

        let existingReminders = Set(try context.fetch(FetchDescriptor<Reminder>()).map(\.id))
        for r in payload.reminders where !existingReminders.contains(r.id) {
            context.insert(Reminder(id: r.id, title: r.title, notes: r.notes, dueDate: r.dueDate,
                                    repeatRule: ReminderRepeat(rawValue: r.repeatRule) ?? .none, isCompleted: r.isCompleted,
                                    completedAt: r.completedAt, testCodes: r.testCodes, notificationsEnabled: r.notificationsEnabled))
            report.addedReminders += 1
        }

        try context.save()
        context.undoManager?.removeAllActions()
        AppLog.backup.info("Восстановление из резервной копии завершено")
        return report
    }

    private func makeExpense(_ dto: ExpenseDTO, labs: [UUID: Laboratory]) -> Expense {
        let expense = Expense(id: dto.id, title: dto.title,
                              amount: Decimal(string: dto.amount, locale: AppLocale.posix) ?? 0,
                              currencyCode: dto.currency, date: dto.date,
                              category: ExpenseCategory(rawValue: dto.category) ?? .other,
                              testCode: dto.testCode, groupID: dto.groupID, note: dto.note)
        context.insert(expense)
        expense.laboratory = dto.laboratoryID.flatMap { labs[$0] }
        return expense
    }
}

enum UTTypeHelper {
    static func type(identifier: String) -> UTType {
        UTType(identifier) ?? .data
    }
}
