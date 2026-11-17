import SwiftData
import SwiftUI

/// Состояние окна редактора обследования.
@MainActor
@Observable
final class ExaminationEditorModel {
    var draft: ExaminationDraft {
        didSet { if !isApplyingProgrammaticChange { isDirty = true } }
    }
    private(set) var isDirty = false
    private(set) var lastSavedAt: Date?
    var errorMessage: String?
    var infoMessage: String?
    /// Окно закрывается после сохранения или явного отказа — автосохранение не нужно.
    var didFinish = false

    let mode: EditorRequest.Mode
    let context: ModelContext
    private let originalStatus: ExaminationStatus?
    private var isApplyingProgrammaticChange = false

    init(request: EditorRequest, context: ModelContext) {
        self.mode = request.mode
        self.context = context
        let store = ExaminationStore(context: context)
        var status: ExaminationStatus?
        var loadError: String?
        switch request.mode {
        case .new:
            draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
        case .edit(let id):
            if let exam = store.examination(id: id) {
                draft = store.draft(from: exam)
                status = exam.status
            } else {
                draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
                loadError = StoreError.notFound.localizedDescription
            }
        case .repeatFrom(let id):
            if let exam = store.examination(id: id) {
                draft = store.repeatDraft(from: exam, factory: store.rowFactory())
            } else {
                draft = ExaminationDraft(currencyCode: AppSettings.defaultCurrency)
                loadError = StoreError.notFound.localizedDescription
            }
        }
        originalStatus = status
        errorMessage = loadError
    }

    private var store: ExaminationStore { ExaminationStore(context: context) }

    var windowTitle: String {
        switch mode {
        case .new: draft.examinationID == nil ? "Новое обследование" : "Черновик: \(draft.title.nilIfEmpty ?? "без названия")"
        case .edit: "Редактирование: \(draft.title.nilIfEmpty ?? "без названия")"
        case .repeatFrom: "Повтор: \(draft.title.nilIfEmpty ?? "без названия")"
        }
    }

    var issues: [EntryIssue] { DraftValidator.issues(in: draft) }
    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var markedCount: Int { draft.rows.filter(\.isMarked).count }
    var hasContent: Bool { !draft.rows.isEmpty || !draft.title.trimmed.isEmpty || !draft.comment.trimmed.isEmpty }

    // MARK: Каталог

    func isSelected(_ code: String) -> Bool {
        draft.rows.contains { $0.testCode == code && $0.kind != .service }
    }

    func toggle(_ entry: CatalogEntry) {
        if isSelected(entry.code) { remove(code: entry.code) } else { add(entry) }
    }

    func add(_ entry: CatalogEntry) {
        let factory = store.rowFactory()
        let fresh = factory.catalog.entry(entry.code) ?? entry
        draft.rows += factory.rows(for: fresh, laboratory: draft.laboratoryName, currency: draft.currencyCode)
    }

    func remove(code: String) {
        let ids = Set(draft.rows.filter { $0.testCode == code && $0.kind != .service }.map(\.id))
        EntryTableOperations.removeRows(ids: ids, from: &draft.rows)
    }

    func addService(name: String = "Взятие крови") {
        draft.rows.append(EntryRow(groupID: UUID(), kind: .service, testCode: nil, name: name))
    }

    func addCustomRow() {
        draft.rows.append(EntryRow(groupID: UUID(), kind: .single, testCode: nil, name: ""))
    }

    func removeRows(_ ids: Set<UUID>) {
        EntryTableOperations.removeRows(ids: ids, from: &draft.rows)
    }

    var emptyValueRowCount: Int { draft.valueRows.filter { $0.value.trimmed.isEmpty }.count }

    /// Удаляет строки показателей без результата (например, не выполненные компоненты комплекса).
    func removeEmptyValueRows() {
        removeRows(Set(draft.rows.filter { $0.kind.hasValue && $0.value.trimmed.isEmpty }.map(\.id)))
    }

    func removeMarked() {
        removeRows(Set(draft.rows.filter(\.isMarked).map(\.id)))
    }

    func setAllMarked(_ marked: Bool) {
        for index in draft.rows.indices { draft.rows[index].isMarked = marked }
    }

    // MARK: Повтор и референсы

    func repeatFrom(_ examination: Examination) {
        let repeated = store.repeatDraft(from: examination, factory: store.rowFactory())
        draft.rows = repeated.rows
        if draft.laboratoryName.trimmed.isEmpty { draft.laboratoryName = repeated.laboratoryName }
        if draft.title.trimmed.isEmpty { draft.title = repeated.title }
        infoMessage = "Скопирован список исследований (\(repeated.valueRows.count)). Результаты и расходы не переносятся."
    }

    /// Подставляет единицы и референсы из прошлых результатов выбранной лаборатории в пустые ячейки.
    func applyLaboratoryReferences() {
        let factory = store.rowFactory()
        var count = 0
        for index in draft.rows.indices {
            if factory.applyReference(to: &draft.rows[index], laboratory: draft.laboratoryName, overwrite: false) { count += 1 }
        }
        infoMessage = count == 0
            ? "Для «\(draft.laboratoryName)» нет сохранённых референсов по этим показателям."
            : "Подставлены референсы для \(count) показателей из прошлых бланков этой лаборатории. Сверьте с текущим бланком."
    }

    // MARK: Табличные операции

    func bulkFill(_ value: String, column: EntryColumn, scope: EntryTableOperations.FillScope) {
        let count = EntryTableOperations.bulkFill(value, column: column, scope: scope, rows: &draft.rows)
        infoMessage = "Заполнено ячеек: \(count)"
    }

    func pasteColumn(_ text: String, column: EntryColumn) {
        guard let first = draft.rows.first(where: { column.isEditable(in: $0) }) else {
            infoMessage = "В таблице нет строк для колонки «\(column.title)»"
            return
        }
        let count = EntryTableOperations.paste(text, at: EntryCell(row: first.id, column: column), into: &draft.rows)
        infoMessage = "Вставлено значений: \(count)"
    }

    // MARK: Сохранение

    /// ⌘S. Новое обследование сохраняется как черновик; уже завершённое — с сохранением статуса.
    @discardableResult
    func saveDraft() -> Bool {
        let finalize = originalStatus != nil && originalStatus != .draft
        return persist(finalize: finalize)
    }

    @discardableResult
    func save() -> Bool {
        guard persist(finalize: true) else { return false }
        didFinish = true
        return true
    }

    func autosaveIfNeeded() {
        guard isDirty, !didFinish, hasContent else { return }
        saveDraft()
    }

    func discard() {
        didFinish = true
    }

    private func persist(finalize: Bool) -> Bool {
        do {
            let exam = try store.save(draft, finalize: finalize)
            isApplyingProgrammaticChange = true
            draft.examinationID = exam.id
            if draft.title.trimmed.isEmpty { draft.title = exam.title }
            isApplyingProgrammaticChange = false
            isDirty = false
            lastSavedAt = .now
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
