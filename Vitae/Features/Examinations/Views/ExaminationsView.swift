import SwiftData
import SwiftUI

struct ExaminationsView: View {
    @Bindable var navigation: NavigationModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Examination.date, order: .reverse) private var examinations: [Examination]
    @State private var pendingDelete: Set<UUID> = []
    @State private var showDeleteConfirmation = false

    private var state: ExaminationsListState { navigation.examinations }
    private var actions: ExaminationActions { ExaminationActions(environment: environment) }

    var body: some View {
        let allRows = examinations.map(ExaminationRow.init)
        let rows = state.apply(to: allRows)
        Group {
            if examinations.isEmpty {
                EmptyStateView(title: "Обследований пока нет", systemImage: "list.clipboard",
                               message: "Создайте первое обследование или импортируйте документ с результатами.",
                               actionTitle: "Новое обследование") {
                    openWindow(id: WindowID.editor, value: EditorRequest.new())
                }
            } else {
                table(rows: rows)
                    .overlay {
                        if rows.isEmpty { ContentUnavailableView.search(text: state.searchText) }
                    }
            }
        }
        .navigationTitle("Обследования")
        .navigationSubtitle(subtitle(total: allRows.count, shown: rows.count))
        .searchable(text: $navigation.examinations.searchText, placement: .toolbar, prompt: "Название, лаборатория, показатель")
        .toolbar { toolbar(allRows: allRows) }
        .inspector(isPresented: $navigation.examinations.showInspector) {
            ExaminationInspector(examinationID: state.selection.count == 1 ? state.selection.first : nil)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .confirmationDialog("Удалить обследования?", isPresented: $showDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                actions.delete(ids: pendingDelete)
                navigation.examinations.selection.subtract(pendingDelete)
                pendingDelete = []
            }
            Button("Отмена", role: .cancel) { pendingDelete = [] }
        } message: {
            Text(ExaminationActions.deleteMessage(count: pendingDelete.count))
        }
        .focusedSceneValue(\.printAction, printAction)
    }

    private var printAction: PrintAction? {
        guard state.selection.count == 1, let id = state.selection.first,
              let exam = examinations.first(where: { $0.id == id }) else { return nil }
        return PrintAction(title: exam.title) { actions.print(exam) }
    }

    private func subtitle(total: Int, shown: Int) -> String {
        let base = Fmt.count(total, one: "обследование", few: "обследования", many: "обследований")
        return shown == total ? base : "Показано \(shown) из \(total)"
    }

    private func table(rows: [ExaminationRow]) -> some View {
        Table(of: ExaminationRow.self, selection: $navigation.examinations.selection, sortOrder: $navigation.examinations.sortOrder) {
            TableColumn("Дата", value: \.date) { row in
                Text(Fmt.shortDate(row.date)).monospacedDigit()
            }
            .width(min: 80, ideal: 92, max: 120)

            TableColumn("Название", value: \.title) { row in
                Text(row.title).lineLimit(1)
            }
            .width(min: 160, ideal: 260)

            TableColumn("Лаборатория", value: \.laboratoryName) { row in
                Text(row.laboratoryName.isEmpty ? "—" : row.laboratoryName)
                    .foregroundStyle(row.laboratoryName.isEmpty ? .secondary : .primary)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Анализов", value: \.resultCount) { row in
                Text("\(row.resultCount)").monospacedDigit()
            }
            .width(min: 60, ideal: 72, max: 90)

            TableColumn("Вне реф.", value: \.deviationCount) { row in
                Text(row.deviationCount == 0 ? "—" : "\(row.deviationCount)")
                    .monospacedDigit()
                    .foregroundStyle(row.deviationCount > 0 ? Color.orange : Color.secondary)
            }
            .width(min: 64, ideal: 76, max: 100)

            TableColumn("Стоимость", value: \.costSortKey) { row in
                Text(row.costText).monospacedDigit()
            }
            .width(min: 80, ideal: 110)

            TableColumn("Статус", value: \.statusSortKey) { row in
                ExaminationStatusBadge(status: row.status)
            }
            .width(min: 120, ideal: 190)
        } rows: {
            if state.groupByYear {
                ForEach(state.groups(for: rows)) { group in
                    Section(group.title) {
                        ForEach(group.rows) { row in TableRow(row) }
                    }
                }
            } else {
                ForEach(rows) { row in TableRow(row) }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(ids)
        } primaryAction: { ids in
            if let id = ids.first { navigation.openExamination(id) }
        }
        .onDeleteCommand {
            guard !state.selection.isEmpty else { return }
            pendingDelete = state.selection
            showDeleteConfirmation = true
        }
        .accessibilityIdentifier("examinations.table")
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<UUID>) -> some View {
        if ids.isEmpty {
            Button("Новое обследование") { openWindow(id: WindowID.editor, value: EditorRequest.new()) }
        } else if ids.count == 1, let id = ids.first, let exam = examinations.first(where: { $0.id == id }) {
            Button("Открыть") { navigation.openExamination(id) }
            Button("Открыть в новом окне") { openWindow(id: WindowID.examination, value: id) }
            Divider()
            Button("Редактировать…") { openWindow(id: WindowID.editor, value: EditorRequest.edit(id)) }
            Button("Повторить обследование…") { openWindow(id: WindowID.editor, value: EditorRequest.repeatFrom(id)) }
            Button("Дублировать") {
                if let newID = actions.duplicate(exam) { navigation.examinations.selection = [newID] }
            }
            Divider()
            Button("Экспорт в PDF…") { Task { await actions.exportPDF(exam) } }
            Button("Печать…") { actions.print(exam) }
            Divider()
            Button("Удалить…", role: .destructive) {
                pendingDelete = [id]
                showDeleteConfirmation = true
            }
        } else {
            if ids.count == 2 {
                let sorted = examinations.filter { ids.contains($0.id) }.sorted { $0.date < $1.date }
                Button("Сравнить обследования") { navigation.compare(sorted[0].id, sorted[1].id) }
                Divider()
            }
            Button("Удалить \(ids.count) обследований…", role: .destructive) {
                pendingDelete = ids
                showDeleteConfirmation = true
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(allRows: [ExaminationRow]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Статус", selection: $navigation.examinations.statusFilter) {
                    Text("Все статусы").tag(ExaminationStatus?.none)
                    ForEach(ExaminationStatus.allCases) { status in
                        Text(status.title).tag(ExaminationStatus?.some(status))
                    }
                }
                Picker("Лаборатория", selection: $navigation.examinations.laboratoryFilter) {
                    Text("Все лаборатории").tag(String?.none)
                    ForEach(Array(Set(allRows.map(\.laboratoryName).filter { !$0.isEmpty })).sorted(), id: \.self) { lab in
                        Text(lab).tag(String?.some(lab))
                    }
                }
                Picker("Год", selection: $navigation.examinations.yearFilter) {
                    Text("Все годы").tag(Int?.none)
                    ForEach(Array(Set(allRows.map(\.year))).sorted(by: >), id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
                Toggle("Только с отклонениями", isOn: $navigation.examinations.onlyDeviations)
                Divider()
                Toggle("Группировать по годам", isOn: $navigation.examinations.groupByYear)
                if state.hasActiveFilters {
                    Divider()
                    Button("Сбросить фильтры") { navigation.examinations.resetFilters() }
                }
            } label: {
                Label("Фильтр", systemImage: state.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help("Фильтры и группировка")

            Button {
                openWindow(id: WindowID.editor, value: EditorRequest.new())
            } label: {
                Label("Новое обследование", systemImage: "plus")
            }
            .help("Новое обследование (⌘N)")
            .accessibilityIdentifier("examinations.new")

            Button {
                navigation.examinations.showInspector.toggle()
            } label: {
                Label("Сведения", systemImage: "sidebar.right")
            }
            .help("Показать или скрыть панель сведений")
        }
    }
}
