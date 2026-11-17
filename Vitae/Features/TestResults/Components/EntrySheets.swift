import SwiftData
import SwiftUI

/// Каталог анализов в редакторе: поиск, категории, избранное, комплексы с компонентами.
struct CatalogPickerPane: View {
    @Bindable var model: ExaminationEditorModel
    @Query(sort: \LabTest.sortOrder) private var tests: [LabTest]
    @State private var search = ""
    @State private var expandedPanels: Set<String> = []
    @State private var showCustomTest = false

    var body: some View {
        let index = CatalogIndex(tests: tests)
        VStack(spacing: 0) {
            InlineSearchField(text: $search, prompt: "Поиск анализа")
                .padding(10)
                .accessibilityIdentifier("editor.catalogSearch")
            List {
                if search.trimmed.isEmpty {
                    let favorites = index.entries.filter(\.isFavorite)
                    if !favorites.isEmpty {
                        Section("Избранное") {
                            ForEach(favorites) { entry in entryRow(entry, index: index) }
                        }
                    }
                    ForEach(TestCategory.allCases) { category in
                        let roots = index.roots.filter { $0.category == category }
                        if !roots.isEmpty {
                            Section(category.title) {
                                ForEach(roots) { entry in rootRow(entry, index: index) }
                            }
                        }
                    }
                } else {
                    let matches = index.entries.filter { $0.matches(search) }
                    if matches.isEmpty {
                        Text("Ничего не найдено").foregroundStyle(.secondary)
                    }
                    ForEach(matches) { entry in entryRow(entry, index: index) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            Divider()
            HStack {
                Button {
                    showCustomTest = true
                } label: {
                    Label("Собственный анализ…", systemImage: "plus")
                }
                Spacer()
            }
            .padding(10)
        }
        .sheet(isPresented: $showCustomTest) {
            LabTestEditorSheet(test: nil) { test in model.add(CatalogEntry(test)) }
        }
    }

    @ViewBuilder
    private func rootRow(_ entry: CatalogEntry, index: CatalogIndex) -> some View {
        if entry.isPanel {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedPanels.contains(entry.code) },
                set: { if $0 { expandedPanels.insert(entry.code) } else { expandedPanels.remove(entry.code) } }
            )) {
                ForEach(index.components(of: entry.code)) { component in
                    entryRow(component, index: index)
                }
            } label: {
                entryRow(entry, index: index)
            }
        } else {
            entryRow(entry, index: index)
        }
    }

    private func entryRow(_ entry: CatalogEntry, index: CatalogIndex) -> some View {
        Toggle(isOn: Binding(get: { model.isSelected(entry.code) }, set: { _ in model.toggle(entry) })) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(2)
                Text(subtitle(entry, index: index))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .help(entry.details.isEmpty ? entry.name : entry.details)
        .accessibilityIdentifier("catalog.\(entry.code)")
    }

    private func subtitle(_ entry: CatalogEntry, index: CatalogIndex) -> String {
        if entry.isPanel {
            return "комплекс · " + Fmt.count(index.components(of: entry.code).count, one: "показатель", few: "показателя", many: "показателей")
        }
        return [entry.shortName, entry.unit].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Массовое заполнение колонки.
struct BulkFillSheet: View {
    let apply: (String, EntryColumn, EntryTableOperations.FillScope) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var column: EntryColumn = .unit
    @State private var value = ""
    @State private var scope: EntryTableOperations.FillScope = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Массовое заполнение").font(.title2.weight(.semibold))
            Form {
                Picker("Колонка", selection: $column) {
                    ForEach(EntryColumn.bulkFillable, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Значение", text: $value)
                Picker("Применить к", selection: $scope) {
                    ForEach(EntryTableOperations.FillScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Text("Значение запишется только в ячейки, доступные для этой колонки. Например, стоимость не записывается в компоненты комплекса.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Заполнить") {
                    apply(value, column, scope)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Вставка столбца значений (альтернатива ⌘V в ячейке).
struct PasteColumnSheet: View {
    let apply: (String, EntryColumn) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var column: EntryColumn = .value
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Вставить столбец").font(.title2.weight(.semibold))
            Text("Скопируйте столбец из Excel или Numbers и вставьте ниже. Значения заполнят таблицу сверху вниз; строки комплексов без результата пропускаются. Если скопировано несколько столбцов, они заполнят соседние колонки.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Начать с колонки", selection: $column) {
                ForEach([EntryColumn.value, .unit, .lower, .upper, .reference, .price], id: \.self) { Text($0.title).tag($0) }
            }
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.separator))
            HStack {
                Button("Вставить из буфера обмена") {
                    text = NSPasteboard.general.string(forType: .string) ?? ""
                }
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Заполнить") {
                    apply(text, column)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
