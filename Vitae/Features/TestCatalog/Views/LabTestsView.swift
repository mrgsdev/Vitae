import SwiftData
import SwiftUI

struct LabTestsView: View {
    @Bindable var navigation: NavigationModel
    @Environment(\.modelContext) private var context

    @Query(sort: \LabTest.sortOrder) private var tests: [LabTest]
    @Query private var results: [TestResult]

    @State private var editingTest: LabTest?
    @State private var showNewTest = false
    @State private var pendingDelete: LabTest?
    @State private var errorMessage: String?

    private var state: CatalogState { navigation.catalog }

    var body: some View {
        let counts = Dictionary(grouping: results.filter { !$0.rawValue.isEmpty }, by: \.testCode).mapValues(\.count)
        let names = Dictionary(tests.map { ($0.code, $0.name) }, uniquingKeysWith: { a, _ in a })
        let allRows = tests.map { CatalogRow(entry: CatalogEntry($0), resultCount: counts[$0.code] ?? 0,
                                             panelName: $0.panelCode.flatMap { names[$0] }) }
        let rows = state.apply(to: allRows)

        Table(of: CatalogRow.self, selection: $navigation.catalog.selection, sortOrder: $navigation.catalog.sortOrder) {
            TableColumn("★", value: \.favoriteSortKey) { row in
                Button {
                    toggleFavorite(row.code)
                } label: {
                    Image(systemName: row.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(row.isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(row.isFavorite ? "Убрать из избранного" : "Добавить в избранное")
            }
            .width(26)

            TableColumn("Название", value: \.name) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).lineLimit(1)
                    if let panel = row.panelName {
                        Text("в составе: \(panel)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn("Кратко", value: \.shortName) { row in Text(row.shortName).foregroundStyle(.secondary) }
                .width(min: 50, ideal: 70)

            TableColumn("Категория", value: \.categoryTitle) { row in
                Label(row.categoryTitle, systemImage: row.category.symbolName).lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Единица", value: \.unit) { row in Text(row.unit.isEmpty ? "—" : row.unit) }
                .width(min: 60, ideal: 80)

            TableColumn("Тип", value: \.kindTitle) { row in Text(row.kindTitle).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 84)

            TableColumn("Записей", value: \.resultCount) { row in
                Text(row.resultCount == 0 ? "—" : "\(row.resultCount)").monospacedDigit()
            }
            .width(min: 56, ideal: 64)

            TableColumn("Источник", value: \.sourceSortKey) { row in
                Text(row.isCustom ? "Мой" : "Встроенный").foregroundStyle(row.isCustom ? Color.accentColor : Color.secondary)
            }
            .width(min: 70, ideal: 90)
        } rows: {
            ForEach(rows) { row in TableRow(row) }
        }
        .contextMenu(forSelectionType: String.self) { codes in
            if let code = codes.first, let test = tests.first(where: { $0.code == code }) {
                contextMenu(test)
            } else {
                Button("Новый показатель…") { showNewTest = true }
            }
        } primaryAction: { codes in
            if let code = codes.first, let test = tests.first(where: { $0.code == code }), test.isCustom {
                editingTest = test
            }
        }
        .onDeleteCommand {
            if let code = state.selection, let test = tests.first(where: { $0.code == code }), test.isCustom {
                pendingDelete = test
            }
        }
        .overlay {
            if rows.isEmpty { ContentUnavailableView.search(text: state.searchText) }
        }
        .navigationTitle("Справочник анализов")
        .navigationSubtitle(Fmt.count(allRows.count, one: "показатель", few: "показателя", many: "показателей"))
        .searchable(text: $navigation.catalog.searchText, placement: .toolbar, prompt: "Название, сокращение, синоним")
        .toolbar { toolbar }
        .inspector(isPresented: $navigation.catalog.showInspector) {
            LabTestInspector(code: state.selection, onEdit: { editingTest = $0 })
                .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
        }
        .sheet(isPresented: $showNewTest) {
            LabTestEditorSheet(test: nil) { navigation.catalog.selection = $0.code }
        }
        .sheet(item: $editingTest) { test in
            LabTestEditorSheet(test: test) { _ in }
        }
        .confirmationDialog("Удалить показатель?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { test in
            Button("Удалить", role: .destructive) { delete(test) }
        } message: { test in
            let count = counts[test.code] ?? 0
            Text(count > 0
                 ? "Показатель «\(test.name)» будет удалён из справочника. \(count) сохранённых результатов останутся в истории обследований."
                 : "Показатель «\(test.name)» будет удалён из справочника.")
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func contextMenu(_ test: LabTest) -> some View {
        Button(test.isFavorite ? "Убрать из избранного" : "Добавить в избранное") { toggleFavorite(test.code) }
        if test.isCustom {
            Button("Редактировать…") { editingTest = test }
        }
        Button("Создать мою версию") {
            do {
                let copy = try CatalogStore(context: context).duplicateAsCustom(test)
                navigation.catalog.selection = copy.code
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if !test.isPanel {
            Button("Открыть динамику") { navigation.openDynamics(code: test.code) }
        }
        if test.isCustom {
            Divider()
            Button("Удалить…", role: .destructive) { pendingDelete = test }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Категория", selection: $navigation.catalog.category) {
                    Text("Все категории").tag(TestCategory?.none)
                    ForEach(TestCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbolName).tag(TestCategory?.some(category))
                    }
                }
                Toggle("Только избранное", isOn: $navigation.catalog.onlyFavorites)
                Toggle("Только мои показатели", isOn: $navigation.catalog.onlyCustom)
            } label: {
                Label("Фильтр", systemImage: "line.3.horizontal.decrease.circle")
            }
            Button {
                showNewTest = true
            } label: {
                Label("Новый показатель", systemImage: "plus")
            }
            .help("Создать собственный показатель или комплекс")
            Button {
                navigation.catalog.showInspector.toggle()
            } label: {
                Label("Сведения", systemImage: "sidebar.right")
            }
        }
    }

    private func toggleFavorite(_ code: String) {
        guard let test = tests.first(where: { $0.code == code }) else { return }
        test.isFavorite.toggle()
        try? context.save()
    }

    private func delete(_ test: LabTest) {
        do {
            try CatalogStore(context: context).deleteCustom(test)
            if navigation.catalog.selection == test.code { navigation.catalog.selection = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingDelete = nil
    }
}

struct LabTestInspector: View {
    let code: String?
    let onEdit: (LabTest) -> Void
    @Query private var tests: [LabTest]
    @Query private var results: [TestResult]
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        if let code, let test = tests.first(where: { $0.code == code }) {
            let components = tests.filter { $0.panelCode == code }.sorted { $0.sortOrder < $1.sortOrder }
            let history = results.filter { $0.testCode == code }.map(ResultSnapshot.init).filter(\.isAnalyzable)
            let latest = history.max { $0.date < $1.date }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(test.category.title, systemImage: test.category.symbolName)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(test.name).font(.title3.weight(.semibold))
                        if !test.shortName.isEmpty { Text(test.shortName).foregroundStyle(.secondary) }
                    }
                    if !test.details.isEmpty {
                        Text(test.details).font(.callout)
                    }
                    VStack(spacing: 6) {
                        InfoRow(title: "Тип", value: test.isPanel ? "Комплексное исследование" : test.isQualitative ? "Качественный" : "Количественный")
                        if !test.isPanel { InfoRow(title: "Единица по умолчанию", value: test.defaultUnit.isEmpty ? "—" : test.defaultUnit) }
                        InfoRow(title: "Источник", value: test.isCustom ? "Пользовательский" : "Встроенный")
                        InfoRow(title: "Сохранённых результатов", value: "\(history.count)")
                    }
                    if !test.isPanel, let alternatives = UnitConverter.suggestedUnits[test.code], alternatives.count > 1 {
                        InfoRow(title: "Пересчёт единиц", value: alternatives.joined(separator: " ↔ "))
                    }
                    if test.code == "lpa" {
                        Text("Значения в мг/дл и нмоль/л не пересчитываются: коэффициент зависит от изоформы белка.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !components.isEmpty {
                        Divider()
                        CardHeader(title: "Компоненты", systemImage: "list.bullet", trailing: "\(components.count)")
                        ForEach(components, id: \.code) { component in
                            HStack {
                                Text(component.name).lineLimit(1)
                                Spacer()
                                Text(component.defaultUnit).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                    if let latest {
                        Divider()
                        CardHeader(title: "Последний результат", systemImage: "clock")
                        HStack {
                            Text("\(latest.displayValue) \(latest.unit)").font(.title3).monospacedDigit()
                            Spacer()
                            StatusBadge(status: latest.status, compact: true)
                        }
                        Text(Fmt.date(latest.date)).font(.caption).foregroundStyle(.secondary)
                        Button("Открыть динамику") { navigation?.openDynamics(code: code) }
                    }
                    if !test.aliases.isEmpty {
                        Divider()
                        CardHeader(title: "Синонимы для распознавания", systemImage: "text.magnifyingglass")
                        Text(test.aliases.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Референсные интервалы в справочнике не задаются: используются значения из бланка конкретной лаборатории.")
                        .font(.caption).foregroundStyle(.tertiary)
                    if test.isCustom {
                        Button("Редактировать…") { onEdit(test) }
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Выберите показатель", systemImage: "books.vertical",
                                   description: Text("Здесь появится описание, компоненты и последний результат."))
        }
    }
}
