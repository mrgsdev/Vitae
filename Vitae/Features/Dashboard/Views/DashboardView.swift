import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.navigationModel) private var navigation
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Examination.date, order: .reverse) private var examinations: [Examination]
    @Query private var results: [TestResult]
    @Query private var expenses: [Expense]
    @Query(filter: #Predicate<Reminder> { !$0.isCompleted }, sort: \Reminder.dueDate) private var reminders: [Reminder]

    @State private var searchText = ""

    var body: some View {
        Group {
            if examinations.isEmpty {
                DashboardEmptyState(
                    newExamination: newExamination,
                    importDocument: { navigation?.importDocument(nil) },
                    restore: { navigation?.apply(.importExportAction(.restoreBackup)) }
                )
            } else if !searchText.trimmed.isEmpty {
                QuickSearchResultsView(results: QuickSearchResults(query: searchText, examinations: examinations, results: results))
            } else {
                content(DashboardModel(examinations: examinations, results: results, expenses: expenses))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .navigationTitle("Главная")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Быстрый поиск")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newExamination) {
                    Label("Новое обследование", systemImage: "plus")
                }
                .help("Новое обследование (⌘N)")
                .accessibilityIdentifier("dashboard.newExamination")
            }
        }
    }

    private var subtitle: String {
        guard let last = examinations.first(where: { $0.status != .draft }) else { return "Обследований пока нет" }
        return "Последнее обследование: \(Fmt.date(last.date))"
    }

    private func newExamination() {
        openWindow(id: WindowID.editor, value: EditorRequest.new())
    }

    private func content(_ model: DashboardModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    if let last = model.lastExamination {
                        LastExaminationCard(examination: last)
                    }
                    StatusSummaryCard(summary: model.summary)
                }

                if model.draftCount > 0 {
                    DraftsBanner(count: model.draftCount) { navigation?.show(.examinations) }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    RecentChangesCard(changes: model.summary.changes)
                    DeviationsCard(deviations: model.summary.deviations)
                    YearExpensesCard(model: model)
                    UpcomingRemindersCard(reminders: Array(reminders.prefix(4)))
                }
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DraftsBanner: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "pencil.circle.fill").foregroundStyle(.secondary)
            Text("Незавершённых черновиков: \(count)")
            Spacer()
            Button("Показать", action: open)
        }
        .card(padding: 12)
    }
}
