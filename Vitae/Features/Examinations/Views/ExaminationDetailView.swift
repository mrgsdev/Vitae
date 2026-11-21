import SwiftData
import SwiftUI

enum ExaminationDetailTab: String, CaseIterable, Identifiable {
    case results, dynamics, expenses, documents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .results: "Результаты"
        case .dynamics: "Динамика"
        case .expenses: "Расходы"
        case .documents: "Документы"
        }
    }
}

/// Загружает обследование по идентификатору (для навигации и отдельных окон).
struct ExaminationDetailContainer: View {
    let examinationID: UUID
    @Query private var matches: [Examination]

    init(examinationID: UUID) {
        self.examinationID = examinationID
        _matches = Query(filter: #Predicate<Examination> { $0.id == examinationID })
    }

    var body: some View {
        if let exam = matches.first {
            ExaminationDetailView(examination: exam)
        } else {
            ContentUnavailableView("Обследование не найдено", systemImage: "questionmark.folder",
                                   description: Text("Возможно, оно было удалено."))
                .navigationTitle("Обследование не найдено")
        }
    }
}

/// Отдельное окно с карточкой обследования.
struct ExaminationWindowView: View {
    let examinationID: UUID?

    var body: some View {
        NavigationStack {
            if let examinationID {
                ExaminationDetailContainer(examinationID: examinationID)
            } else {
                ContentUnavailableView("Обследование не выбрано", systemImage: "list.clipboard")
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

struct ExaminationDetailView: View {
    @Bindable var examination: Examination
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.navigationModel) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var tab: ExaminationDetailTab = .results
    @State private var selectedResultID: UUID?
    @State private var showInspector = true
    @State private var showDeleteConfirmation = false

    private var actions: ExaminationActions { ExaminationActions(environment: environment) }

    var body: some View {
        VStack(spacing: 0) {
            ExaminationHeaderView(examination: examination)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Picker("Раздел", selection: $tab) {
                ForEach(ExaminationDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 12)
            .accessibilityIdentifier("examination.tabs")

            Divider()

            Group {
                switch tab {
                case .results:
                    ExaminationResultsTab(examination: examination, selection: $selectedResultID)
                case .dynamics:
                    ExaminationDynamicsTab(examination: examination)
                case .expenses:
                    ExaminationExpensesTab(examination: examination)
                case .documents:
                    ExaminationDocumentsTab(examination: examination)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .pageBackground()
        .onAppear {
            #if DEBUG
            if let initial = UITestingHooks.initialDetailTab { tab = initial }
            if UITestingHooks.selectsFirstResult {
                selectedResultID = examination.sortedResults.first { !$0.rawValue.isEmpty }?.id
            }
            #endif
        }
        .navigationTitle(examination.title)
        .navigationSubtitle([Fmt.date(examination.date), examination.laboratory?.name].compactMap { $0 }.joined(separator: " · "))
        .inspector(isPresented: Binding(get: { showInspector && tab == .results }, set: { showInspector = $0 })) {
            ResultInspector(result: examination.results.first { $0.id == selectedResultID })
                .inspectorColumnWidth(min: 260, ideal: 310, max: 420)
        }
        .toolbar { toolbar }
        .focusedSceneValue(\.printAction, PrintAction(title: examination.title) { actions.print(examination) })
        .confirmationDialog("Удалить обследование?", isPresented: $showDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                let id = examination.id
                if let navigation {
                    let section = navigation.selection ?? .examinations
                    navigation.paths[section] = []
                } else {
                    dismiss()
                }
                actions.delete(ids: [id])
            }
        } message: {
            Text(ExaminationActions.deleteMessage(count: 1))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                openWindow(id: WindowID.editor, value: EditorRequest.edit(examination.id))
            } label: {
                Label("Редактировать", systemImage: "square.and.pencil")
            }
            .help("Редактировать результаты и расходы")
            .accessibilityIdentifier("examination.edit")

            Menu {
                Button("Повторить обследование…") {
                    openWindow(id: WindowID.editor, value: EditorRequest.repeatFrom(examination.id))
                }
                Button("Дублировать") { _ = actions.duplicate(examination) }
                if navigation != nil {
                    Button("Открыть в новом окне") { openWindow(id: WindowID.examination, value: examination.id) }
                }
                Divider()
                Button("Экспорт в PDF…") { Task { await actions.exportPDF(examination) } }
                Button("Печать…") { actions.print(examination) }
                Divider()
                Button("Удалить…", role: .destructive) { showDeleteConfirmation = true }
            } label: {
                Label("Действия", systemImage: "ellipsis.circle")
            }
            .help("Действия с обследованием")

            if tab == .results {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Сведения", systemImage: "sidebar.right")
                }
                .help("Сведения о выбранном показателе")
            }
        }
    }
}

struct ExaminationHeaderView: View {
    let examination: Examination

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(examination.title)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text([Fmt.date(examination.date), examination.laboratory?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ExaminationStatusBadge(status: examination.status)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                StatTile(title: "Результатов", value: "\(examination.results.count)", systemImage: "number")
                StatTile(title: "Вне референса", value: "\(examination.deviationCount)",
                         color: examination.deviationCount > 0 ? .orange : .secondary, systemImage: "exclamationmark.circle")
                StatTile(title: "Стоимость", value: Fmt.moneyTotals(examination.costTotals), systemImage: "creditcard")
                StatTile(title: "Документов", value: "\(examination.attachments.count)", systemImage: "doc")
            }
            if !examination.comment.isEmpty {
                Label {
                    Text(examination.comment).textSelection(.enabled)
                } icon: {
                    Image(systemName: "text.bubble")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}
