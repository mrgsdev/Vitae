import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Bindable var navigation: NavigationModel
    @Environment(AppEnvironment.self) private var environment

    @Query(sort: \Examination.date, order: .reverse) private var examinations: [Examination]
    @Query private var results: [TestResult]
    @Query private var tests: [LabTest]

    @State private var includeAttachments = true
    @State private var pendingRestore: PendingRestore?
    @State private var csvImport: CSVImportSession?
    @State private var reportExamID: UUID?
    @State private var reportTestCode: String?
    @State private var reportYear: Int?
    @State private var message: (title: String, text: String)?
    @State private var backups: [URL] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 16, alignment: .top)], spacing: 16) {
                documentCard
                backupCard
                csvCard
                reportsCard
                localBackupsCard
            }
            .padding(24)
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle("Импорт и экспорт")
        .onAppear {
            refreshBackups()
            handlePendingAction()
        }
        .onChange(of: navigation.importExportAction) { _, _ in handlePendingAction() }
        .sheet(item: $pendingRestore) { restore in
            RestoreBackupSheet(restore: restore) { mode in performRestore(restore, mode: mode) }
        }
        .sheet(item: $csvImport) { session in
            CSVMappingSheet(session: session) { drafts in importDrafts(drafts) }
        }
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message?.text ?? "")
        }
    }

    // MARK: Cards

    private var documentCard: some View {
        Card(title: "Документы с результатами", systemImage: "doc.text.viewfinder") {
            Text("Распознавание PDF и изображений бланков (Vision). Значения проверяются вручную перед сохранением.")
                .foregroundStyle(.secondary)
            Button {
                navigation.importDocument(nil)
            } label: {
                Label("Импортировать документ…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("importExport.document")
        }
    }

    private var backupCard: some View {
        Card(title: "Резервная копия (JSON)", systemImage: "externaldrive") {
            Text("Полный экспорт базы: обследования, результаты, расходы, лаборатории, собственные показатели и напоминания. Файл содержит версию схемы и контрольную сумму SHA-256.")
                .foregroundStyle(.secondary)
            Toggle("Включить прикреплённые документы", isOn: $includeAttachments)
            HStack {
                Button {
                    Task { await ExportActions.exportBackup(environment: environment, includeAttachments: includeAttachments) }
                } label: {
                    Label("Экспортировать…", systemImage: "square.and.arrow.up")
                }
                Button {
                    Task { await chooseBackupFile() }
                } label: {
                    Label("Восстановить из копии…", systemImage: "square.and.arrow.down")
                }
            }
            Text("Файл резервной копии содержит медицинские данные в открытом виде — храните его в надёжном месте.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var csvCard: some View {
        Card(title: "CSV", systemImage: "tablecells") {
            Text("Таблицы для Excel и Numbers (разделитель «;», UTF-8). При импорте колонки сопоставляются вручную.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Экспорт результатов…") { Task { await ExportActions.exportResultsCSV(environment: environment) } }
                Button("Экспорт расходов…") { Task { await ExportActions.exportExpensesCSV(environment: environment) } }
            }
            Button {
                Task { await chooseCSVFile() }
            } label: {
                Label("Импорт результатов из CSV…", systemImage: "square.and.arrow.down")
            }
        }
    }

    /// Показатели для «Истории показателя» — с теми же названиями, что и в «Динамике».
    private var indicators: [IndicatorSummary] {
        IndicatorSummary.build(from: results.map(ResultSnapshot.init), catalog: CatalogIndex(tests: tests))
    }

    private var reportsCard: some View {
        let years = Array(Set(examinations.map { $0.date.year() })).sorted(by: >)
        return Card(title: "Отчёты PDF", systemImage: "doc.richtext") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Обследование").foregroundStyle(.secondary)
                    Picker("Обследование", selection: $reportExamID) {
                        Text("Выберите…").tag(UUID?.none)
                        ForEach(examinations) { Text("\(Fmt.shortDate($0.date)) — \($0.title)").tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    Button("Сохранить PDF…") { Task { await exportExaminationReport() } }
                        .disabled(reportExamID == nil)
                }
                GridRow {
                    Text("История показателя").foregroundStyle(.secondary)
                    Picker("Показатель", selection: $reportTestCode) {
                        Text("Выберите…").tag(String?.none)
                        ForEach(indicators) { Text($0.name).tag(String?.some($0.code)) }
                    }
                    .labelsHidden()
                    Button("Сохранить PDF…") { Task { await exportHistoryReport() } }
                        .disabled(reportTestCode == nil)
                }
                GridRow {
                    Text("Финансовый отчёт").foregroundStyle(.secondary)
                    Picker("Период", selection: $reportYear) {
                        Text("За всё время").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                    .labelsHidden()
                    Button("Сохранить PDF…") { Task { await exportFinancialReport() } }
                }
                GridRow {
                    Text("Сравнение").foregroundStyle(.secondary)
                    Text("Выберите обследования в разделе «Сравнение»").font(.caption).foregroundStyle(.secondary)
                    Button("Открыть…") {
                        navigation.show(.comparison)
                    }
                }
            }
        }
    }

    private var localBackupsCard: some View {
        Card(title: "Автоматические копии на этом Mac", systemImage: "clock.arrow.circlepath",
             trailing: AppSettings.autoBackupEnabled ? "каждые \(AppSettings.autoBackupIntervalDays) дн." : "выключены") {
            if backups.isEmpty {
                Text("Копий пока нет.").foregroundStyle(.secondary)
            } else {
                ForEach(backups.prefix(5), id: \.self) { url in
                    HStack {
                        Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                        Text(url.deletingPathExtension().lastPathComponent).font(.callout.monospacedDigit())
                        Spacer()
                        Button("Восстановить…") { loadBackup(from: url) }
                            .buttonStyle(.link)
                    }
                }
            }
            HStack {
                Button("Создать копию сейчас") {
                    do {
                        try AutoBackupService.createBackup(context: environment.context, fileStorage: environment.fileStorage)
                        refreshBackups()
                    } catch {
                        message = ("Не удалось создать копию", error.localizedDescription)
                    }
                }
                Button("Показать в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([backups.first ?? AppDirectories.backups])
                }
            }
        }
    }

    // MARK: Actions

    private func refreshBackups() {
        backups = AutoBackupService.backupFiles()
    }

    private func handlePendingAction() {
        guard let action = navigation.importExportAction else { return }
        navigation.importExportAction = nil
        Task {
            switch action {
            case .restoreBackup: await chooseBackupFile()
            case .importCSV: await chooseCSVFile()
            }
        }
    }

    private func chooseBackupFile() async {
        guard let url = await FilePanels.open(title: "Восстановить из резервной копии", contentTypes: [.json]).first else { return }
        loadBackup(from: url)
    }

    private func loadBackup(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try BackupService.read(data)
            pendingRestore = PendingRestore(envelope: envelope, fileName: url.lastPathComponent)
        } catch {
            message = ("Резервная копия не принята", error.localizedDescription)
        }
    }

    private func performRestore(_ restore: PendingRestore, mode: RestoreMode) {
        do {
            let outcome = try BackupRestorer(context: environment.context, fileStorage: environment.fileStorage)
                .restore(restore.envelope, mode: mode)
            let report = outcome.report
            var text = "Добавлено обследований: \(report.addedExaminations), результатов: \(report.addedResults), расходов: \(report.addedExpenses), документов: \(report.addedAttachments)."
            if report.skippedExaminations > 0 { text += " Пропущено уже существующих обследований: \(report.skippedExaminations)." }
            if report.missingAttachmentFiles > 0 { text += " Документов без содержимого в копии: \(report.missingAttachmentFiles)." }
            if let safety = outcome.safetyBackup {
                text += " Прежние данные сохранены в копии «\(safety.deletingPathExtension().lastPathComponent)»."
            }
            message = ("Восстановление завершено", text)
        } catch {
            message = ("Не удалось восстановить", error.localizedDescription)
        }
        // И после ошибки: страховочная копия могла записаться до сбоя самого восстановления.
        refreshBackups()
    }

    private func chooseCSVFile() async {
        guard let url = await FilePanels.open(title: "Импорт результатов из CSV",
                                              contentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]).first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = CSV.decodeText(data) else {
            message = ("Не удалось прочитать файл", "Проверьте, что это текстовый CSV-файл.")
            return
        }
        let table = CSV.parse(text)
        guard !table.headers.isEmpty, !table.rows.isEmpty else {
            message = ("Пустой файл", "В файле нет строк с данными.")
            return
        }
        csvImport = CSVImportSession(table: table, fileName: url.lastPathComponent, catalog: environment.examinationStore.catalogIndex())
    }

    private func importDrafts(_ drafts: [ExaminationDraft]) {
        var saved = 0
        var failures: [String] = []
        for draft in drafts {
            do {
                try environment.examinationStore.save(draft, finalize: true)
                saved += 1
            } catch {
                failures.append("\(draft.title): \(error.localizedDescription)")
            }
        }
        message = failures.isEmpty
            ? ("Импорт завершён", "Создано обследований: \(saved).")
            : ("Импорт завершён с ошибками", "Создано: \(saved). Ошибки:\n" + failures.joined(separator: "\n"))
    }

    private func exportExaminationReport() async {
        guard let id = reportExamID, let exam = examinations.first(where: { $0.id == id }) else { return }
        await ExaminationActions(environment: environment).exportPDF(exam)
    }

    private func exportHistoryReport() async {
        guard let code = reportTestCode, let name = indicators.first(where: { $0.code == code })?.name else { return }
        let history = results.map(ResultSnapshot.init).filter { $0.testCode == code && $0.isAnalyzable }
        let series = DynamicsCalculator.series(from: history)
        let renderer = ImageRenderer(content: DynamicsChart(series: series, interactive: false)
            .frame(width: 900, height: 340).padding(10).background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        let data = PDFReportService.historyReport(testName: name, series: series, chart: renderer.cgImage)
        do {
            try await FilePanels.export(data, title: "История показателя", suggestedName: FilePanels.safeFileName("История — \(name).pdf"), contentType: .pdf)
        } catch {
            message = ("Не удалось сохранить отчёт", error.localizedDescription)
        }
    }

    private func exportFinancialReport() async {
        let snapshots = environment.examinationStore.expenseSnapshots()
        let data: Data
        if let year = reportYear, let interval = ExpenseAnalytics.yearInterval(year) {
            data = PDFReportService.financialReport(expenses: snapshots.filter { interval.contains($0.date) }, periodTitle: "\(year) год")
        } else {
            data = PDFReportService.financialReport(expenses: snapshots, periodTitle: "За всё время")
        }
        do {
            try await FilePanels.export(data, title: "Финансовый отчёт", suggestedName: "Финансовый отчёт.pdf", contentType: .pdf)
        } catch {
            message = ("Не удалось сохранить отчёт", error.localizedDescription)
        }
    }
}

struct PendingRestore: Identifiable {
    let id = UUID()
    let envelope: BackupEnvelope
    let fileName: String
}

struct RestoreBackupSheet: View {
    let restore: PendingRestore
    let perform: (RestoreMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RestoreMode = .merge
    @State private var confirmReplace = false

    var body: some View {
        let summary = BackupService.summary(of: restore.envelope)
        VStack(alignment: .leading, spacing: 14) {
            Label("Резервная копия проверена", systemImage: "checkmark.seal.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
            Text(restore.fileName).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                InfoRow(title: "Создана", value: Fmt.dateTime(summary.exportedAt))
                InfoRow(title: "Версия схемы", value: summary.schemaVersion)
                InfoRow(title: "Обследований", value: "\(summary.examinations)")
                InfoRow(title: "Результатов", value: "\(summary.results)")
                InfoRow(title: "Расходов", value: "\(summary.expenses)")
                InfoRow(title: "Документов", value: "\(summary.attachmentsWithData) из \(summary.attachments) с содержимым")
                InfoRow(title: "Лабораторий / своих показателей", value: "\(summary.laboratories) / \(summary.customTests)")
                InfoRow(title: "Напоминаний", value: "\(summary.reminders)")
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Picker("Режим", selection: $mode) {
                ForEach(RestoreMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text(mode == .merge
                 ? "Новые записи будут добавлены, существующие (с теми же идентификаторами) останутся без изменений."
                 : "Все текущие данные будут удалены и заменены содержимым копии. Перед заменой автоматически создаётся страховочная копия.")
                .font(.callout)
                .foregroundStyle(mode == .replace ? .red : .secondary)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Восстановить") {
                    if mode == .replace { confirmReplace = true } else { perform(mode); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
        .confirmationDialog("Заменить все данные?", isPresented: $confirmReplace) {
            Button("Заменить", role: .destructive) { perform(.replace); dismiss() }
        } message: {
            Text("Текущие обследования, результаты, расходы и документы будут удалены. Это действие нельзя отменить.")
        }
    }
}
