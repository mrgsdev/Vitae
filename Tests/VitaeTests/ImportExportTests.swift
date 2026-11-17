import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Vitae

@MainActor
private func populatedEnvironment() throws -> TestEnvironment {
    let env = try TestEnvironment()
    var first = env.draft(title: "Весна", date: AppLocale.calendar.date(from: DateComponents(year: 2024, month: 4, day: 2))!, codes: ["cbc", "ferritin"])
    first.set("cbc.hgb", value: "128", lower: "130", upper: "160")
    first.set("ferritin", value: "18", lower: "30", upper: "400", price: "650,50")
    first.setPrice("cbc", "590")
    let exam = try env.store.save(first, finalize: true)

    var second = env.draft(title: "Осень", date: AppLocale.calendar.date(from: DateComponents(year: 2025, month: 10, day: 5))!, lab: "Гемотест", codes: ["ferritin", "urine"])
    second.set("ferritin", value: "88", lower: "30", upper: "400", price: "850")
    if let index = second.rows.firstIndex(where: { $0.testCode == "urine.protein" }) {
        second.rows[index].value = "отрицательно"
        second.rows[index].referenceText = "отрицательно"
    }
    try env.store.save(second, finalize: true)

    let stored = try env.fileStorage.store(data: Data("%PDF-1.4 test".utf8), originalFileName: "бланк.pdf", contentType: .pdf)
    let attachment = Vitae.Attachment(originalFileName: stored.originalFileName, storedFileName: stored.storedFileName,
                                contentTypeIdentifier: "com.adobe.pdf", fileSize: stored.size)
    env.context.insert(attachment)
    attachment.examination = exam
    env.context.insert(Expense(title: "Консультация", amount: Decimal(string: "1500")!, currencyCode: "RUB", date: .now, category: .other))
    env.context.insert(Reminder(title: "Повторить ферритин", dueDate: .now.addingTimeInterval(86_400 * 30), repeatRule: .halfYear))
    env.context.insert(UserProfile(name: "Тестовый пользователь"))
    try env.context.save()
    return env
}

@MainActor
@Suite("Резервное копирование JSON")
struct BackupTests {
    @Test func roundTripRestoresEverything() throws {
        let source = try populatedEnvironment()
        let data = try BackupService(context: source.context, fileStorage: source.fileStorage).exportData(includeAttachments: true)
        let envelope = try BackupService.read(data)
        #expect(envelope.formatVersion == BackupService.formatVersion)
        #expect(envelope.schemaVersion == "1.0.0")

        let summary = BackupService.summary(of: envelope)
        #expect(summary.examinations == 2)
        #expect(summary.attachmentsWithData == 1)

        let target = try TestEnvironment()
        let report = try BackupService(context: target.context, fileStorage: target.fileStorage).restore(envelope, mode: .merge)
        #expect(report.addedExaminations == 2)
        #expect(report.addedAttachments == 1)
        #expect(try target.context.fetchCount(FetchDescriptor<TestResult>()) == source.context.fetchCount(FetchDescriptor<TestResult>()))
        #expect(try target.context.fetchCount(FetchDescriptor<Expense>()) == source.context.fetchCount(FetchDescriptor<Expense>()))
        #expect(try target.context.fetchCount(FetchDescriptor<Reminder>()) == 1)
        #expect(try target.context.fetch(FetchDescriptor<UserProfile>()).first?.name == "Тестовый пользователь")

        let expense = try #require(try target.context.fetch(FetchDescriptor<Expense>()).first { $0.title == "Ферритин" && $0.amount < 700 })
        #expect(expense.amount == Decimal(string: "650.5"), "Decimal без потери точности")

        let attachment = try #require(try target.context.fetch(FetchDescriptor<Vitae.Attachment>()).first)
        #expect(try target.fileStorage.data(for: attachment.storedFileName) == Data("%PDF-1.4 test".utf8))

        // Повторное объединение не создаёт дубликатов.
        let again = try BackupService(context: target.context, fileStorage: target.fileStorage).restore(envelope, mode: .merge)
        #expect(again.addedExaminations == 0)
        #expect(again.skippedExaminations == 2)
    }

    @Test func replaceModeErasesCurrentData() throws {
        let source = try populatedEnvironment()
        let envelope = try BackupService.read(try BackupService(context: source.context, fileStorage: source.fileStorage).exportData(includeAttachments: false))
        let target = try TestEnvironment()
        var draft = target.draft(title: "Лишнее", codes: ["glucose"])
        draft.set("glucose", value: "5")
        try target.store.save(draft, finalize: true)
        _ = try BackupService(context: target.context, fileStorage: target.fileStorage).restore(envelope, mode: .replace)
        let titles = try target.context.fetch(FetchDescriptor<Examination>()).map(\.title).sorted()
        #expect(titles == ["Весна", "Осень"])
        #expect(try target.context.fetchCount(FetchDescriptor<LabTest>()) == CatalogSeedData.entries.count)
    }

    @Test func tamperedFileFailsChecksum() throws {
        let env = try populatedEnvironment()
        let data = try BackupService(context: env.context, fileStorage: env.fileStorage).exportData(includeAttachments: false)
        var text = try #require(String(data: data, encoding: .utf8))
        text = text.replacingOccurrences(of: "\"rawValue\" : \"128\"", with: "\"rawValue\" : \"182\"")
        #expect(throws: BackupError.checksumMismatch) { try BackupService.read(Data(text.utf8)) }
    }

    @Test func rejectsForeignAndFutureFiles() throws {
        #expect(throws: BackupError.notABackup) { try BackupService.read(Data("{\"hello\":1}".utf8)) }
        let future = Data("{\"format\":\"VitaeBackup\",\"formatVersion\":99}".utf8)
        #expect(throws: BackupError.unsupportedVersion(99)) { try BackupService.read(future) }
    }

    @Test func integrityValidation() throws {
        let lab = UUID()
        let exam = ExaminationDTO(id: UUID(), title: "x", date: .now, comment: "", status: "completed", createdAt: .now, updatedAt: .now,
                                  laboratoryID: lab, results: [], expenses: [], attachments: [])
        let payload = BackupPayload(profile: nil, laboratories: [], labTests: [], examinations: [exam], standaloneExpenses: [], reminders: [])
        #expect(throws: BackupError.self) { try BackupService.validateIntegrity(payload) }
        let duplicated = BackupPayload(profile: nil, laboratories: [], labTests: [], examinations: [exam, exam], standaloneExpenses: [], reminders: [])
        #expect(throws: BackupError.integrity("повторяющиеся обследования")) { try BackupService.validateIntegrity(duplicated) }
    }
}

@MainActor
@Suite("CSV")
struct CSVTests {
    @Test func escapingAndParsingRoundTrip() {
        let rows = [["1", "Текст; с разделителем", "Кавычки \"внутри\""], ["2", "Перевод\nстроки", ""]]
        let data = CSV.encode(headers: ["№", "А", "Б"], rows: rows)
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
        let table = CSV.parse(CSV.decodeText(data)!)
        #expect(table.delimiter == ";")
        #expect(table.headers == ["№", "А", "Б"])
        #expect(table.rows == rows)
    }

    @Test func detectsDelimiters() {
        #expect(CSV.parse("a,b,c\n1,2,3").delimiter == ",")
        #expect(CSV.parse("a\tb\n1\t2").delimiter == "\t")
        #expect(CSV.parse("a;b\n1;2").rows == [["1", "2"]])
    }

    @Test func exportResultsAndExpenses() throws {
        let env = try populatedEnvironment()
        let results = CSV.parse(CSV.decodeText(CSVExporter.results(env.store.resultSnapshots()))!)
        #expect(results.headers == CSVExporter.resultHeaders)
        #expect(results.rows.contains { $0[4] == "Гемоглобин" && $0[6] == "128" && $0[11] == "Ниже референса" })
        let expenses = CSV.parse(CSV.decodeText(CSVExporter.expenses(env.store.expenseSnapshots()))!)
        #expect(expenses.rows.contains { $0[1] == "Ферритин" && $0[5] == "650,5" && $0[6] == "RUB" })
    }

    @Test func importWithColumnMapping() throws {
        let env = try TestEnvironment()
        let text = """
        Дата;Лаборатория;Анализ;Результат;Ед. изм;Референс;Цена
        12.03.2024;Инвитро;Гемоглобин;145;г/л;130-160;
        12.03.2024;Инвитро;Ферритин;18;нг/мл;30 - 400;650
        12.03.2024;Инвитро;Цинк;14;мкмоль/л;11-18;400
        05.09.2024;Гемотест;Ферритин;42;нг/мл;20-300;720
        ;;Пустая;;;;
        """
        let table = CSV.parse(text)
        let mapping = CSVMapping.autoDetect(headers: table.headers)
        #expect(mapping.columns[.date] == 0)
        #expect(mapping.columns[.testName] == 2)
        #expect(mapping.columns[.value] == 3)
        #expect(mapping.columns[.reference] == 5)
        #expect(mapping.columns[.price] == 6)
        #expect(mapping.missingRequired.isEmpty)

        let result = CSVImporter.makeDrafts(table: table, mapping: mapping, catalog: env.store.catalogIndex(), defaultCurrency: "RUB")
        #expect(result.drafts.count == 2)
        #expect(result.skippedRows == [6])
        #expect(result.unmatchedNames == ["Цинк"])
        let first = result.drafts[0]
        #expect(first.laboratoryName == "Инвитро")
        #expect(first.rows.count == 3)
        #expect(first.rows[0].testCode == "cbc.hgb")
        #expect(first.rows[0].lower == "130")
        #expect(first.rows[1].price == "650")

        for draft in result.drafts { try env.store.save(draft, finalize: true) }
        #expect(try env.context.fetchCount(FetchDescriptor<Examination>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<Expense>()) == 3)
    }
}

@MainActor
@Suite("PDF-отчёты")
struct PDFTests {
    private func text(_ data: Data) throws -> (String, Int) {
        let document = try #require(PDFDocument(data: data))
        return (document.string ?? "", document.pageCount)
    }

    @Test func examinationReport() throws {
        let env = try populatedEnvironment()
        let exam = try #require(env.store.allExaminations().first { $0.title == "Весна" })
        let data = PDFReportService.examinationReport(title: exam.title, date: exam.date, laboratory: exam.laboratory?.name, status: exam.status,
                                                      comment: "натощак", results: exam.sortedResults.map(ResultSnapshot.init),
                                                      expenses: exam.expenses.map(ExpenseSnapshot.init),
                                                      profile: .init(name: "Иван", birthDate: nil))
        let (content, pages) = try text(data)
        #expect(pages >= 1)
        #expect(content.contains("Гемоглобин"))
        #expect(content.contains("Ниже"))
        #expect(content.contains("не является медицинским заключением"))
    }

    @Test func longTablesPaginate() throws {
        let results = (0..<120).map { i in
            ResultSnapshot(date: .now, testCode: "t\(i)", testName: "Показатель \(i)", sortIndex: i, rawValue: "\(i)", unit: "ед",
                           reference: ReferenceRange(lower: 0, upper: 50))
        }
        let data = PDFReportService.examinationReport(title: "Большой отчёт", date: .now, laboratory: nil, status: .completed,
                                                      comment: "", results: results, expenses: [], profile: nil)
        let (content, pages) = try text(data)
        #expect(pages >= 3)
        #expect(content.contains("Показатель 119"))
    }

    @Test func comparisonHistoryAndFinancialReports() throws {
        let env = try populatedEnvironment()
        let exams = env.store.allExaminations().sorted { $0.date < $1.date }
        let rows = ComparisonEngine.compare(exams[0].sortedResults.map(ResultSnapshot.init), exams[1].sortedResults.map(ResultSnapshot.init))
        let comparison = try text(PDFReportService.comparisonReport(titleA: exams[0].title, dateA: exams[0].date,
                                                                    titleB: exams[1].title, dateB: exams[1].date, rows: rows)).0
        #expect(comparison.contains("Ферритин"))

        let history = env.store.resultSnapshots().filter { $0.testCode == "ferritin" }
        let historyText = try text(PDFReportService.historyReport(testName: "Ферритин", series: DynamicsCalculator.series(from: history), chart: nil)).0
        #expect(historyText.contains("Измерения"))
        #expect(historyText.contains("88"))

        let finance = try text(PDFReportService.financialReport(expenses: env.store.expenseSnapshots(), periodTitle: "Всё время")).0
        #expect(finance.contains("Финансовый отчёт"))
        #expect(finance.contains("Консультация"))
    }
}
