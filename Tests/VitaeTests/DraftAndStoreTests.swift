import Foundation
import SwiftData
import Testing
@testable import Vitae

/// Изолированное окружение: база в памяти и временная папка для файлов.
@MainActor
struct TestEnvironment {
    let container: ModelContainer
    let fileStorage: FileStorageService
    var context: ModelContext { container.mainContext }
    var store: ExaminationStore { ExaminationStore(context: context) }

    init(seed: Bool = true) throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HTTests-\(UUID().uuidString)", isDirectory: true)
        fileStorage = FileStorageService(baseURL: dir)
        if seed { try CatalogSeeder.seedIfNeeded(context: container.mainContext) }
    }

    func entry(_ code: String) -> CatalogEntry {
        store.catalogIndex().entry(code)!
    }

    func draft(title: String = "Тест", date: Date = .now, lab: String = "Инвитро", codes: [String]) -> ExaminationDraft {
        let factory = store.rowFactory()
        var draft = ExaminationDraft(title: title, date: date, laboratoryName: lab, currencyCode: "RUB")
        for code in codes { draft.rows += factory.rows(for: entry(code), laboratory: lab, currency: "RUB") }
        return draft
    }
}

extension ExaminationDraft {
    mutating func set(_ code: String, value: String, lower: String = "", upper: String = "", price: String? = nil) {
        guard let index = rows.firstIndex(where: { $0.testCode == code }) else { return }
        rows[index].value = value
        rows[index].lower = lower
        rows[index].upper = upper
        if let price { rows[index].price = price }
    }

    mutating func setPrice(_ code: String, _ price: String) {
        guard let index = rows.firstIndex(where: { $0.testCode == code && $0.kind.hasPrice }) else { return }
        rows[index].price = price
    }
}

@Suite("Табличный ввод")
struct EntryTableTests {
    private func sampleRows() -> [EntryRow] {
        let panel = UUID()
        return [
            EntryRow(groupID: panel, kind: .panel, testCode: "cbc", name: "ОАК"),
            EntryRow(groupID: panel, kind: .component, testCode: "cbc.hgb", name: "Гемоглобин"),
            EntryRow(groupID: panel, kind: .component, testCode: "cbc.wbc", name: "Лейкоциты"),
            EntryRow(groupID: UUID(), kind: .single, testCode: "ferritin", name: "Ферритин"),
            EntryRow(groupID: UUID(), kind: .service, testCode: nil, name: "Взятие крови")
        ]
    }

    @Test func pasteColumnSkipsRowsWithoutValue() {
        var rows = sampleRows()
        let filled = EntryTableOperations.paste("145\n6,2\n88", at: EntryCell(row: rows[0].id, column: .value), into: &rows)
        #expect(filled == 3)
        #expect(rows[1].value == "145")
        #expect(rows[2].value == "6,2")
        #expect(rows[3].value == "88")
        #expect(rows[0].value.isEmpty)
    }

    @Test func pasteMultipleColumnsAndRanges() {
        var rows = sampleRows()
        EntryTableOperations.paste("145\tг/л\n6,2\t×10⁹/л", at: EntryCell(row: rows[1].id, column: .value), into: &rows)
        #expect(rows[1].unit == "г/л")
        #expect(rows[2].unit == "×10⁹/л")

        EntryTableOperations.paste("130 - 160\n4,0–9,0", at: EntryCell(row: rows[1].id, column: .lower), into: &rows)
        #expect(rows[1].lower == "130")
        #expect(rows[1].upper == "160")
        #expect(rows[2].lower == "4")
        #expect(rows[2].upper == "9")
    }

    @Test func pastePriceSkipsComponents() {
        var rows = sampleRows()
        EntryTableOperations.paste("590\n650\n200", at: EntryCell(row: rows[0].id, column: .price), into: &rows)
        #expect(rows[0].price == "590")
        #expect(rows[1].price.isEmpty)
        #expect(rows[3].price == "650")
        #expect(rows[4].price == "200")
    }

    @Test func bulkFillScopes() {
        var rows = sampleRows()
        rows[3].unit = "нг/мл"
        #expect(EntryTableOperations.bulkFill("г/л", column: .unit, scope: .empty, rows: &rows) == 2)
        #expect(rows[3].unit == "нг/мл")
        rows[1].isMarked = true
        #expect(EntryTableOperations.bulkFill("X", column: .unit, scope: .marked, rows: &rows) == 1)
        #expect(rows[1].unit == "X")
        #expect(EntryTableOperations.bulkFill("100", column: .price, scope: .all, rows: &rows) == 3)
    }

    @Test func keyboardNeighborsSkipUneditableRows() {
        let rows = sampleRows()
        let next = EntryTableOperations.neighbor(of: EntryCell(row: rows[2].id, column: .value), offset: 1, in: rows)
        #expect(next?.row == rows[3].id)
        let up = EntryTableOperations.neighbor(of: EntryCell(row: rows[1].id, column: .value), offset: -1, in: rows)
        #expect(up == nil)
    }

    @Test func removingPanelRemovesComponents() {
        var rows = sampleRows()
        EntryTableOperations.removeRows(ids: [rows[0].id], from: &rows)
        #expect(rows.count == 2)
        #expect(!rows.contains { $0.kind == .component })
    }

    @Test func validatorReportsErrors() {
        var draft = ExaminationDraft()
        draft.rows = [EntryRow(groupID: UUID(), kind: .single, testCode: "x", name: "X", value: "5", lower: "abc", upper: "3", price: "-1")]
        let errors = DraftValidator.errors(in: draft)
        #expect(errors.contains { $0.field == .lower })
        #expect(errors.contains { $0.field == .price })
        draft.rows[0].lower = "10"
        draft.rows[0].price = "100"
        #expect(DraftValidator.errors(in: draft).contains { $0.message.contains("больше") })
    }
}

@MainActor
@Suite("Хранилище обследований")
struct ExaminationStoreTests {
    @Test func seedingIsIdempotent() throws {
        let env = try TestEnvironment()
        let count = try env.context.fetchCount(FetchDescriptor<LabTest>())
        #expect(count == CatalogSeedData.entries.count)
        #expect(try CatalogSeeder.seedIfNeeded(context: env.context) == 0)
        // В стартовом справочнике есть все показатели из ТЗ.
        for code in ["cbc", "glucose", "hba1c", "lipid.chol", "lipid.ldl", "lipid.hdl", "lipid.tg", "alt", "ast", "bili.total", "ggt",
                     "creatinine", "urea", "uric_acid", "tsh", "ferritin", "vitd", "b12", "crp", "electrolytes", "calcium", "magnesium",
                     "protein", "albumin", "testosterone", "shbg", "psa", "apob", "lpa", "homocysteine", "insulin"] {
            #expect(env.store.catalogIndex().entry(code) != nil, "нет показателя \(code)")
        }
    }

    @Test func savingCreatesResultsExpensesAndStatus() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["cbc", "ferritin"])
        draft.set("cbc.hgb", value: "128", lower: "130", upper: "160")
        draft.set("ferritin", value: "88", lower: "30", upper: "400", price: "850")
        draft.setPrice("cbc", "590")
        draft.rows.append(EntryRow(groupID: UUID(), kind: .service, testCode: nil, name: "Взятие крови", price: "199"))

        let exam = try env.store.save(draft, finalize: true)
        #expect(exam.results.count == env.store.catalogIndex().components(of: "cbc").count + 1)
        #expect(exam.status == .awaitingResults, "не все значения заполнены")
        #expect(exam.expenses.count == 3)
        #expect(exam.costTotals["RUB"] == Decimal(1639))
        #expect(exam.laboratory?.name == "Инвитро")
        let hgb = try #require(exam.results.first { $0.testCode == "cbc.hgb" })
        #expect(hgb.panelName == "Общий анализ крови")
        #expect(hgb.status == .below)
        #expect(hgb.referenceLower == 130)
        #expect(exam.deviationCount == 1)
    }

    @Test func completeExaminationAndDraftStatus() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "40")
        #expect(try env.store.save(draft, finalize: true).status == .completed)
        var second = env.draft(codes: ["vitd"])
        second.title = ""
        let saved = try env.store.save(second, finalize: false)
        #expect(saved.status == .draft)
        #expect(saved.title.hasPrefix("Обследование"))
    }

    @Test func invalidDraftIsRejected() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "40", lower: "abc")
        #expect(throws: StoreError.self) { try env.store.save(draft, finalize: true) }
    }

    @Test func draftRoundTripPreservesStructure() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["lipid", "glucose"])
        draft.set("lipid.ldl", value: "3,1", upper: "3,0")
        draft.set("glucose", value: "5,3", lower: "4,1", upper: "5,9", price: "350")
        draft.setPrice("lipid", "1200")
        draft.comment = "натощак"
        let exam = try env.store.save(draft, finalize: true)

        let loaded = env.store.draft(from: exam)
        #expect(loaded.examinationID == exam.id)
        #expect(loaded.comment == "натощак")
        #expect(loaded.rows.filter { $0.kind == .panel }.count == 1)
        #expect(loaded.rows.first { $0.kind == .panel }?.price == "1200")
        #expect(loaded.rows.first { $0.testCode == "glucose" }?.price == "350")
        #expect(loaded.rows.first { $0.testCode == "lipid.ldl" }?.upper == "3")
        #expect(loaded.valueRows.count == draft.valueRows.count)

        // Повторное сохранение того же черновика не плодит записи.
        try env.store.save(loaded, finalize: true)
        #expect(try env.context.fetchCount(FetchDescriptor<Examination>()) == 1)
        #expect(try env.context.fetchCount(FetchDescriptor<TestResult>()) == draft.valueRows.count)
        #expect(try env.context.fetchCount(FetchDescriptor<Expense>()) == 2)
    }

    @Test func repeatCopiesOnlyTestList() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["cbc", "ferritin"])
        draft.set("ferritin", value: "88", lower: "30", upper: "400", price: "850")
        draft.set("cbc.hgb", value: "150", lower: "130", upper: "160")
        draft.setPrice("cbc", "590")
        let exam = try env.store.save(draft, finalize: true)

        let repeated = env.store.repeatDraft(from: exam, factory: env.store.rowFactory())
        #expect(repeated.examinationID == nil)
        #expect(repeated.rows.count == draft.rows.count)
        #expect(repeated.rows.allSatisfy { $0.value.isEmpty && $0.price.isEmpty })
        // Референсы подставлены из прошлого бланка той же лаборатории, цена — только подсказкой.
        let ferritin = try #require(repeated.rows.first { $0.testCode == "ferritin" })
        #expect(ferritin.lower == "30")
        #expect(ferritin.pricePlaceholder.contains("850"))
        #expect(Set(repeated.rows.map(\.groupID)).isDisjoint(with: Set(draft.rows.map(\.groupID))))
    }

    @Test func referencesFromOtherLaboratoryAreNotApplied() throws {
        let env = try TestEnvironment()
        var draft = env.draft(lab: "Инвитро", codes: ["ferritin"])
        draft.set("ferritin", value: "88", lower: "30", upper: "400")
        try env.store.save(draft, finalize: true)
        let other = env.draft(lab: "Гемотест", codes: ["ferritin"])
        #expect(other.rows[0].lower.isEmpty, "референсы другой лаборатории не подставляются")
        let same = env.draft(lab: "инвитро", codes: ["ferritin"])
        #expect(same.rows[0].lower == "30")
    }

    @Test func unknownNamesBecomeCustomTests() throws {
        let env = try TestEnvironment()
        var draft = ExaminationDraft(title: "Импорт", laboratoryName: "Лаб")
        draft.rows = [
            EntryRow(groupID: UUID(), kind: .single, testCode: nil, name: "Цинк", value: "14", unit: "мкмоль/л"),
            EntryRow(groupID: UUID(), kind: .single, testCode: nil, name: "ферритин", value: "50", unit: "нг/мл")
        ]
        let exam = try env.store.save(draft, finalize: true)
        let codes = Set(exam.results.map(\.testCode))
        #expect(codes.contains("ferritin"), "известное название сопоставлено со справочником")
        #expect(codes.contains { $0.hasPrefix("custom.") })
        let custom = try env.context.fetch(FetchDescriptor<LabTest>()).filter(\.isCustom)
        #expect(custom.map(\.name) == ["Цинк"])
    }

    @Test func duplicateCreatesDraftCopy() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "88", price: "850")
        let exam = try env.store.save(draft, finalize: true)
        let copy = try env.store.duplicate(exam)
        #expect(copy.id != exam.id)
        #expect(copy.status == .draft)
        #expect(copy.title.hasSuffix("(копия)"))
        #expect(copy.results.first?.rawValue == "88")
        #expect(Set(copy.results.map(\.id)).isDisjoint(with: Set(exam.results.map(\.id))))
    }

    @Test func deleteRemovesAttachmentFiles() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "88")
        let exam = try env.store.save(draft, finalize: true)
        let stored = try env.fileStorage.store(data: Data("PDF".utf8), originalFileName: "бланк.pdf", contentType: .pdf)
        let attachment = Vitae.Attachment(originalFileName: stored.originalFileName, storedFileName: stored.storedFileName,
                                    contentTypeIdentifier: "com.adobe.pdf", fileSize: stored.size)
        env.context.insert(attachment)
        attachment.examination = exam
        try env.context.save()
        #expect(env.fileStorage.fileExists(stored.storedFileName))

        try env.store.delete([exam], fileStorage: env.fileStorage)
        #expect(!env.fileStorage.fileExists(stored.storedFileName))
        #expect(try env.context.fetchCount(FetchDescriptor<Examination>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<TestResult>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<Vitae.Attachment>()) == 0)
    }

    /// Удаление явно убирает результаты и расходы обследования и не трогает соседние
    /// (каскад SwiftData падал, если таблица загрузила результаты только через связь).
    @Test func deleteRemovesOnlyOwnResultsAndExpenses() throws {
        let env = try TestEnvironment()
        var first = env.draft(title: "Первое", codes: ["ferritin", "vitd"])
        first.set("ferritin", value: "40", price: "500")
        first.set("vitd", value: "30", price: "900")
        var second = env.draft(title: "Второе", codes: ["ferritin"])
        second.set("ferritin", value: "55", price: "600")
        let a = try env.store.save(first, finalize: true)
        let b = try env.store.save(second, finalize: true)
        _ = [a, b].map(ExaminationRow.init)

        try env.store.delete([a], fileStorage: env.fileStorage)
        #expect(env.store.allExaminations().map(\.id) == [b.id])
        let results = try env.context.fetch(FetchDescriptor<TestResult>())
        #expect(results.map(\.rawValue) == ["55"])
        #expect(try env.context.fetch(FetchDescriptor<Expense>()).map(\.amount) == [600])

        try BackupService(context: env.context, fileStorage: env.fileStorage).eraseAllData()
        #expect(try env.context.fetchCount(FetchDescriptor<Examination>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<TestResult>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<Expense>()) == 0)
    }

    @Test func customTestLifecycleKeepsHistory() throws {
        let env = try TestEnvironment()
        let catalog = CatalogStore(context: env.context)
        var form = LabTestForm()
        form.name = "Панель микроэлементов"
        form.isPanel = true
        form.category = .vitamins
        form.components = [.init(name: "Цинк", unit: "мкмоль/л"), .init(name: "Селен", unit: "мкг/л")]
        let panel = try catalog.saveCustom(form, editing: nil)
        #expect(catalog.components(of: panel.code).count == 2)

        let index = env.store.catalogIndex()
        let rows = env.store.rowFactory().rows(for: try #require(index.entry(panel.code)), laboratory: "", currency: "RUB")
        var draft = ExaminationDraft(title: "Микроэлементы")
        draft.rows = rows
        draft.rows[1].value = "14"
        let exam = try env.store.save(draft, finalize: true)

        try catalog.deleteCustom(panel)
        #expect(catalog.test(code: panel.code) == nil)
        #expect(exam.results.count == 2, "история сохраняется после удаления показателя")
        #expect(exam.results.contains { $0.testName == "Цинк" && $0.rawValue == "14" })
    }
}

@MainActor
@Suite("Файловое хранилище")
struct FileStorageTests {
    @Test func storeReadDeleteAndOrphans() throws {
        let env = try TestEnvironment(seed: false)
        let a = try env.fileStorage.store(data: Data([1, 2, 3]), originalFileName: "a.png", contentType: .png)
        let b = try env.fileStorage.store(data: Data([4, 5]), originalFileName: "b.jpg", contentType: .jpeg)
        #expect(a.storedFileName.hasSuffix(".png"))
        #expect(try env.fileStorage.data(for: a.storedFileName) == Data([1, 2, 3]))
        #expect(env.fileStorage.totalSize() == 5)
        #expect(env.fileStorage.removeOrphans(keeping: [a.storedFileName]) == 1)
        #expect(!env.fileStorage.fileExists(b.storedFileName))
        env.fileStorage.deleteFile(named: a.storedFileName)
        #expect(env.fileStorage.allStoredFileNames().isEmpty)
    }

    @Test func rejectsUnsupportedTypes() throws {
        let env = try TestEnvironment(seed: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("text".utf8).write(to: url)
        #expect(throws: FileStorageError.self) { try env.fileStorage.importFile(at: url) }
        #expect(FileStorageService.isSupported(URL(fileURLWithPath: "/tmp/x.heic")))
        #expect(!FileStorageService.isSupported(URL(fileURLWithPath: "/tmp/x.docx")))
    }
}
