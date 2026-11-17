import Foundation
import SwiftData

enum StoreError: LocalizedError {
    case invalidDraft([EntryIssue])
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidDraft(let issues):
            let first = issues.first?.message ?? ""
            return issues.count == 1 ? "Исправьте ошибку в таблице: \(first)."
                : "В таблице \(issues.count) ошибок. Первая: \(first)."
        case .notFound:
            return "Запись не найдена — возможно, она была удалена."
        }
    }
}

/// Операции с обследованиями: сохранение черновика, загрузка в редактор, повтор, дублирование, удаление.
@MainActor
struct ExaminationStore {
    let context: ModelContext

    // MARK: Чтение

    func examination(id: UUID) -> Examination? {
        var descriptor = FetchDescriptor<Examination>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allExaminations() -> [Examination] {
        (try? context.fetch(FetchDescriptor<Examination>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    func catalogIndex() -> CatalogIndex {
        CatalogIndex(tests: (try? context.fetch(FetchDescriptor<LabTest>())) ?? [])
    }

    func resultSnapshots() -> [ResultSnapshot] {
        ((try? context.fetch(FetchDescriptor<TestResult>())) ?? []).map(ResultSnapshot.init)
    }

    func expenseSnapshots() -> [ExpenseSnapshot] {
        ((try? context.fetch(FetchDescriptor<Expense>())) ?? []).map(ExpenseSnapshot.init)
    }

    func referenceHistory() -> ReferenceHistory {
        ReferenceHistory(results: resultSnapshots(), expenses: expenseSnapshots())
    }

    func rowFactory() -> DraftRowFactory {
        DraftRowFactory(catalog: catalogIndex(), history: referenceHistory())
    }

    // MARK: Лаборатории

    func laboratory(named name: String) -> Laboratory? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Laboratory>())) ?? []
        if let existing = all.first(where: { $0.name.searchNormalized == trimmed.searchNormalized }) {
            return existing
        }
        let lab = Laboratory(name: trimmed)
        context.insert(lab)
        return lab
    }

    // MARK: Пользовательские показатели

    /// Находит показатель по названию/синониму или создаёт пользовательский.
    func ensureTestCode(name: String, unit: String, isQualitative: Bool, category: TestCategory) -> String {
        let tests = (try? context.fetch(FetchDescriptor<LabTest>())) ?? []
        let normalized = name.searchNormalized
        if let match = tests.first(where: { !$0.isPanel && ($0.name.searchNormalized == normalized
            || $0.shortName.searchNormalized == normalized
            || $0.aliases.contains { $0.searchNormalized == normalized }) }) {
            return match.code
        }
        let code = "custom." + UUID().uuidString.lowercased()
        let maxOrder = tests.map(\.sortOrder).max() ?? 0
        context.insert(LabTest(code: code, name: name.trimmed, category: category, defaultUnit: unit,
                               aliases: [name.searchNormalized], isQualitative: isQualitative,
                               isCustom: true, sortOrder: maxOrder + 10))
        return code
    }

    // MARK: Сохранение

    /// Сохраняет черновик. `finalize == false` — сохранение как черновика (⌘S).
    @discardableResult
    func save(_ draft: ExaminationDraft, finalize: Bool) throws -> Examination {
        let errors = DraftValidator.errors(in: draft)
        guard errors.isEmpty else { throw StoreError.invalidDraft(errors) }

        let exam: Examination
        if let id = draft.examinationID, let existing = examination(id: id) {
            exam = existing
        } else {
            exam = Examination(id: draft.examinationID ?? UUID(), title: "", date: draft.date)
            context.insert(exam)
        }

        let title = draft.title.trimmed
        exam.title = title.isEmpty ? ExaminationDraft.defaultTitle(for: draft.date) : title
        exam.date = draft.date
        exam.comment = draft.comment.trimmed
        exam.laboratory = laboratory(named: draft.laboratoryName)
        exam.updatedAt = .now

        let oldResults = exam.results
        let oldExpenses = exam.expenses
        exam.results = []
        exam.expenses = []
        oldResults.forEach(context.delete)
        oldExpenses.forEach(context.delete)

        var panels: [UUID: EntryRow] = [:]
        for row in draft.rows where row.kind == .panel { panels[row.groupID] = row }

        var sortIndex = 0
        for row in draft.rows {
            if row.kind.hasValue {
                let code = row.testCode ?? ensureTestCode(name: row.name, unit: row.unit,
                                                          isQualitative: row.isQualitative, category: row.category)
                let panel = row.kind == .component ? panels[row.groupID] : nil
                let result = TestResult(testCode: code, testName: row.name.trimmed, category: row.category,
                                        panelCode: panel?.testCode, panelName: panel?.name.trimmed,
                                        groupID: row.groupID, sortIndex: sortIndex, rawValue: row.value,
                                        unit: row.unit.trimmed, reference: row.reference, isQualitative: row.isQualitative)
                context.insert(result)
                result.examination = exam
                sortIndex += 1
            }
            if row.kind.hasPrice, let amount = row.priceValue, amount > 0 {
                let category: ExpenseCategory = switch row.kind {
                case .single: .test
                case .panel: .panel
                default: .service
                }
                let expense = Expense(title: row.name.trimmed, amount: amount, currencyCode: draft.currencyCode,
                                      date: draft.date, category: category,
                                      testCode: row.kind == .service ? nil : row.testCode, groupID: row.groupID)
                context.insert(expense)
                expense.examination = exam
                expense.laboratory = exam.laboratory
            }
        }

        if finalize {
            let valueRows = draft.valueRows
            exam.status = (!valueRows.isEmpty && valueRows.allSatisfy { !$0.value.trimmed.isEmpty }) ? .completed : .awaitingResults
        } else {
            exam.status = .draft
        }
        try context.save()
        return exam
    }

    // MARK: Загрузка в редактор

    func draft(from exam: Examination) -> ExaminationDraft {
        var draft = ExaminationDraft(examinationID: exam.id, title: exam.title, date: exam.date,
                                     laboratoryName: exam.laboratory?.name ?? "", comment: exam.comment,
                                     currencyCode: exam.expenses.first?.currencyCode ?? AppSettings.defaultCurrency)
        let expensesByGroup = Dictionary(grouping: exam.expenses.filter { $0.groupID != nil }, by: { $0.groupID! })
        var emittedPanels = Set<UUID>()
        var usedExpenseIDs = Set<UUID>()

        for result in exam.sortedResults {
            if let panelName = result.panelName, !emittedPanels.contains(result.groupID) {
                emittedPanels.insert(result.groupID)
                let expense = expensesByGroup[result.groupID]?.first
                if let expense { usedExpenseIDs.insert(expense.id) }
                draft.rows.append(EntryRow(groupID: result.groupID, kind: .panel, testCode: result.panelCode,
                                           name: panelName, category: result.category,
                                           price: expense?.amount.editingString ?? ""))
            }
            var row = EntryRow(groupID: result.groupID, kind: result.panelName == nil ? .single : .component,
                               testCode: result.testCode, name: result.testName, category: result.category,
                               isQualitative: result.isQualitative, value: result.rawValue, unit: result.unit,
                               lower: Fmt.optionalNumber(result.referenceLower), upper: Fmt.optionalNumber(result.referenceUpper),
                               referenceText: result.referenceText ?? "")
            if row.kind == .single, let expense = expensesByGroup[result.groupID]?.first {
                usedExpenseIDs.insert(expense.id)
                row.price = expense.amount.editingString
            }
            draft.rows.append(row)
        }

        for expense in exam.expenses.sorted(by: { $0.createdAt < $1.createdAt }) where !usedExpenseIDs.contains(expense.id) {
            draft.rows.append(EntryRow(groupID: expense.groupID ?? UUID(), kind: .service, testCode: expense.testCode,
                                       name: expense.title, price: expense.amount.editingString))
        }
        return draft
    }

    /// Новый черновик на основе прошлого обследования: только список исследований.
    func repeatDraft(from exam: Examination, factory: DraftRowFactory) -> ExaminationDraft {
        let source = draft(from: exam)
        var result = ExaminationDraft(title: exam.title, date: .now, laboratoryName: source.laboratoryName,
                                      comment: "", currencyCode: source.currencyCode)
        result.rows = factory.repeatRows(from: source, laboratory: source.laboratoryName, currency: source.currencyCode)
        return result
    }

    // MARK: Дублирование и удаление

    /// Полная копия записи (без документов) со статусом «Черновик».
    @discardableResult
    func duplicate(_ exam: Examination) throws -> Examination {
        var copy = draft(from: exam)
        copy.examinationID = nil
        copy.title = exam.title + " (копия)"
        var groupMap: [UUID: UUID] = [:]
        copy.rows = copy.rows.map { row in
            var row = row
            row.id = UUID()
            let group = groupMap[row.groupID] ?? UUID()
            groupMap[row.groupID] = group
            row.groupID = group
            return row
        }
        return try save(copy, finalize: false)
    }

    /// Удаляет обследования вместе с файлами вложений.
    func delete(_ exams: [Examination], fileStorage: FileStorageService) throws {
        for exam in exams {
            for attachment in exam.attachments {
                fileStorage.deleteFile(named: attachment.storedFileName)
            }
            context.delete(exam)
        }
        try context.save()
        context.undoManager?.removeAllActions()
    }
}
