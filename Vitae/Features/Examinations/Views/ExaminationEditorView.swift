import SwiftData
import SwiftUI

/// Окно создания/редактирования обследования.
struct ExaminationEditorWindow: View {
    let request: EditorRequest
    @Environment(\.modelContext) private var context
    @State private var model: ExaminationEditorModel?

    var body: some View {
        Group {
            if let model {
                ExaminationEditorView(model: model)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .onAppear {
            if model == nil { model = ExaminationEditorModel(request: request, context: context) }
        }
    }
}

struct ExaminationEditorView: View {
    @Bindable var model: ExaminationEditorModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Laboratory.name) private var laboratories: [Laboratory]
    @Query(sort: \Examination.date, order: .reverse) private var examinations: [Examination]

    @State private var showBulkFill = false
    @State private var showPasteColumn = false
    @State private var showCancelConfirmation = false
    @State private var repeatCandidate: Examination?
    @State private var showEmptyRowsPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            EditorHeaderForm(draft: $model.draft, laboratories: laboratories.map(\.name))
                .padding(16)
            Divider()
            HSplitView {
                CatalogPickerPane(model: model)
                    .frame(minWidth: 240, idealWidth: 270, maxWidth: 360)
                VStack(spacing: 0) {
                    gridToolbar
                    Divider()
                    if model.draft.rows.isEmpty {
                        emptyGrid
                    } else {
                        ResultEntryGrid(rows: $model.draft.rows, issues: model.issues)
                    }
                }
                .frame(minWidth: 680)
                .layoutPriority(1)
            }
            Divider()
            footer
        }
        .navigationTitle(model.windowTitle)
        .toolbar { toolbar }
        .focusedSceneValue(\.editorActions, EditorActions(saveDraft: { model.saveDraft() }, save: finish))
        .onDisappear { model.autosaveIfNeeded() }
        .sheet(isPresented: $showBulkFill) {
            BulkFillSheet { value, column, scope in model.bulkFill(value, column: column, scope: scope) }
        }
        .sheet(isPresented: $showPasteColumn) {
            PasteColumnSheet { text, column in model.pasteColumn(text, column: column) }
        }
        .confirmationDialog("Сохранить изменения?", isPresented: $showCancelConfirmation) {
            Button("Сохранить черновик") {
                if model.saveDraft() { model.discard(); dismiss() }
            }
            Button("Не сохранять", role: .destructive) {
                model.discard()
                dismiss()
            }
            Button("Продолжить редактирование", role: .cancel) {}
        } message: {
            Text("Несохранённые изменения будут потеряны.")
        }
        .confirmationDialog("Заменить список анализов?", isPresented: Binding(get: { repeatCandidate != nil }, set: { if !$0 { repeatCandidate = nil } }),
                            presenting: repeatCandidate) { exam in
            Button("Заменить") { model.repeatFrom(exam) }
        } message: { exam in
            Text("Текущие строки таблицы будут заменены списком из обследования «\(exam.title)». Результаты и расходы не копируются.")
        }
        .confirmationDialog("Есть показатели без результата", isPresented: $showEmptyRowsPrompt) {
            Button("Сохранить как ожидающие результата") { performFinish() }
            Button("Удалить пустые строки и сохранить") {
                model.removeEmptyValueRows()
                performFinish()
            }
            Button("Продолжить ввод", role: .cancel) {}
        } message: {
            Text("Без результата: \(model.emptyValueRowCount). Если результаты ещё придут, сохраните их как ожидающие — обследование получит статус «Ожидает результатов».")
        }
        .alert("Не удалось сохранить", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func finish() {
        if model.emptyValueRowCount > 0 && model.emptyValueRowCount < model.draft.valueRows.count {
            showEmptyRowsPrompt = true
        } else {
            performFinish()
        }
    }

    private func performFinish() {
        if model.save() {
            if let id = model.draft.examinationID {
                environment.pendingRoute = .examination(id)
            }
            dismiss()
        }
    }

    private func cancel() {
        if model.isDirty && model.hasContent {
            showCancelConfirmation = true
        } else {
            model.discard()
            dismiss()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                let candidates = examinations.filter { $0.status != .draft && $0.id != model.draft.examinationID }.prefix(15)
                if candidates.isEmpty {
                    Text("Нет завершённых обследований")
                }
                ForEach(Array(candidates)) { exam in
                    Button("\(Fmt.shortDate(exam.date)) — \(exam.title)") {
                        if model.draft.rows.isEmpty { model.repeatFrom(exam) } else { repeatCandidate = exam }
                    }
                }
            } label: {
                Label("Повторить прошлое", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Скопировать список исследований из прошлого обследования (без результатов и расходов)")

            Button {
                showPasteColumn = true
            } label: {
                Label("Вставить столбец", systemImage: "doc.on.clipboard")
            }
            .help("Вставить столбец значений из Excel или Numbers")

            Button {
                showBulkFill = true
            } label: {
                Label("Массовое заполнение", systemImage: "square.grid.3x3.fill.square")
            }
            .help("Заполнить колонку одним значением")
            .disabled(model.draft.rows.isEmpty)
        }
    }

    private var gridToolbar: some View {
        HStack(spacing: 12) {
            if model.markedCount > 0 {
                Text("Отмечено: \(model.markedCount)").foregroundStyle(.secondary)
                Button("Снять отметки") { model.setAllMarked(false) }
                Button("Удалить отмеченные", role: .destructive) { model.removeMarked() }
            } else {
                Text("Результаты").font(.headline)
                Text("Tab, ↑ ↓ и Return — переход по ячейкам; ⌘V — вставка столбца из Excel")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.applyLaboratoryReferences()
            } label: {
                Label("Референсы лаборатории", systemImage: "text.badge.checkmark")
            }
            .disabled(model.draft.laboratoryName.trimmed.isEmpty || model.draft.rows.isEmpty)
            .help("Заполнить пустые референсы значениями из прошлых бланков этой лаборатории")
            Menu {
                Button("Строка показателя") { model.addCustomRow() }
                Button("Услуга (взятие крови и т. п.)") { model.addService() }
            } label: {
                Label("Добавить строку", systemImage: "plus")
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var emptyGrid: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Выберите анализы в каталоге слева").font(.title3)
            Text("или повторите список из прошлого обследования кнопкой «Повторить прошлое».")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summaryText).monospacedDigit()
                HStack(spacing: 8) {
                    if let info = model.infoMessage {
                        Text(info).foregroundStyle(.secondary)
                    }
                    if model.errorCount > 0 {
                        Label("Ошибок в таблице: \(model.errorCount)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    if let saved = model.lastSavedAt {
                        Text("Черновик сохранён в \(saved.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    } else if model.isDirty {
                        Text("Есть несохранённые изменения").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer()
            Button("Отмена", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Сохранить черновик") { model.saveDraft() }
                .help("Сохранить черновик (⌘S)")
                .accessibilityIdentifier("editor.saveDraft")
            Button("Сохранить", action: finish)
                .buttonStyle(.borderedProminent)
                .help("Сохранить обследование (⌘↩)")
                .accessibilityIdentifier("editor.save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var summaryText: String {
        let draft = model.draft
        let count = draft.valueRows.count
        var parts = [Fmt.count(count, one: "показатель", few: "показателя", many: "показателей"),
                     "заполнено \(draft.filledCount)"]
        if draft.deviationCount > 0 { parts.append("вне референса \(draft.deviationCount)") }
        let total = draft.totalPrice
        if total > 0 { parts.append("итого \(Fmt.money(total, currency: draft.currencyCode))") }
        return parts.joined(separator: " · ")
    }
}

/// Поля заголовка обследования. Компактный вариант — для узких панелей (проверка OCR).
struct EditorHeaderForm: View {
    @Binding var draft: ExaminationDraft
    let laboratories: [String]
    var compact = false

    var body: some View {
        if compact { compactLayout } else { wideLayout }
    }

    private var titleField: some View {
        TextField("Например, «Ежегодный чек-ап»", text: $draft.title)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("editor.title")
    }

    private var datePicker: some View {
        DatePicker("Дата", selection: $draft.date, displayedComponents: [.date])
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
    }

    private var currencyPicker: some View {
        Picker("Валюта", selection: $draft.currencyCode) {
            ForEach(CurrencyCatalog.codes, id: \.self) { code in
                Text("\(code) \(CurrencyCatalog.symbol(code))").tag(code)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var commentField: some View {
        TextField("Подготовка, самочувствие, назначивший врач…", text: $draft.comment, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
    }

    private var wideLayout: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                label("Название").gridColumnAlignment(.trailing)
                titleField
                label("Дата").gridColumnAlignment(.trailing)
                HStack(spacing: 10) {
                    datePicker
                    label("Валюта")
                    currencyPicker
                    Spacer(minLength: 0)
                }
            }
            GridRow {
                label("Лаборатория")
                LaboratoryField(text: $draft.laboratoryName, laboratories: laboratories)
                    .accessibilityIdentifier("editor.laboratory")
                label("Комментарий")
                commentField
            }
        }
    }

    private var compactLayout: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                label("Название").gridColumnAlignment(.trailing)
                titleField
            }
            GridRow {
                label("Дата")
                HStack(spacing: 12) {
                    datePicker
                    currencyPicker
                    Spacer(minLength: 0)
                }
            }
            GridRow {
                label("Лаборатория")
                LaboratoryField(text: $draft.laboratoryName, laboratories: laboratories)
            }
            GridRow {
                label("Комментарий")
                commentField
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
