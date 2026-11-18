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
                QuickActionsRow(
                    newExamination: newExamination,
                    importDocument: { navigation?.importDocument(nil) },
                    showDynamics: { navigation?.openDynamicsOverview() },
                    compare: { navigation?.show(.comparison) }
                )

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

/// Крупные кнопки самых частых действий, чтобы с главной было понятно, куда нажимать.
private struct QuickActionsRow: View {
    let newExamination: () -> Void
    let importDocument: () -> Void
    let showDynamics: () -> Void
    let compare: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
            QuickActionButton(title: "Новое обследование", subtitle: "Ввести результаты вручную",
                              systemImage: "plus.circle.fill", color: .accentColor, action: newExamination)
                .help("Новое обследование (⌘N)")
                .accessibilityIdentifier("dashboard.action.new")
            QuickActionButton(title: "Загрузить бланк", subtitle: "PDF или фото — значения распознаются",
                              systemImage: "doc.text.viewfinder", color: .indigo, action: importDocument)
                .help("Распознать бланк из PDF или фото (⌘I)")
                .accessibilityIdentifier("dashboard.action.import")
            QuickActionButton(title: "Динамика", subtitle: "Графики всех показателей во времени",
                              systemImage: "chart.xyaxis.line", color: .green, action: showDynamics)
                .accessibilityIdentifier("dashboard.action.dynamics")
            QuickActionButton(title: "Сравнение", subtitle: "Что изменилось между двумя обследованиями",
                              systemImage: "rectangle.split.2x1", color: .orange, action: compare)
                .accessibilityIdentifier("dashboard.action.compare")
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isHovered ? color.opacity(0.6) : Theme.separator, lineWidth: isHovered ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
