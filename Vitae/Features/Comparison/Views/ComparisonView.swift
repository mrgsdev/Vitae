import SwiftData
import SwiftUI

/// Сравнение двух обследований в виде таблицы с проверкой совместимости единиц.
struct ComparisonView: View {
    @Bindable var navigation: NavigationModel
    @Query(sort: \Examination.date, order: .reverse) private var examinations: [Examination]

    private var state: ComparisonState { navigation.comparison }

    var body: some View {
        let examA = examinations.first { $0.id == state.examinationA }
        let examB = examinations.first { $0.id == state.examinationB }
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Выберите два обследования: таблица покажет, как изменился каждый показатель между ними.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                selector
            }
            .padding(16)
            Divider()
            if examinations.count < 2 {
                EmptyStateView(title: "Недостаточно обследований", systemImage: "rectangle.split.2x1",
                               message: "Для сравнения нужно минимум два обследования.")
            } else if let examA, let examB {
                let rows = ComparisonEngine.compare(examA.sortedResults.map(ResultSnapshot.init), examB.sortedResults.map(ResultSnapshot.init))
                let filtered = rows.filter { state.filter.includes($0) && $0.testName.matchesSearch(state.searchText) }
                ComparisonSummaryBar(rows: rows)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                ComparisonTable(rows: filtered, dateA: examA.date, dateB: examB.date)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                Task { await export(rows: filtered, a: examA, b: examB) }
                            } label: {
                                Label("Экспорт в PDF", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                PrintService.printPDF(report(rows: filtered, a: examA, b: examB), jobTitle: "Сравнение обследований")
                            } label: {
                                Label("Печать", systemImage: "printer")
                            }
                        }
                    }
                    .focusedSceneValue(\.printAction, PrintAction(title: "сравнение") {
                        PrintService.printPDF(report(rows: filtered, a: examA, b: examB), jobTitle: "Сравнение обследований")
                    })
            } else {
                EmptyStateView(title: "Выберите два обследования", systemImage: "rectangle.split.2x1",
                               message: "Сравнение покажет изменения каждого общего показателя.")
            }
        }
        .onAppear(perform: selectDefaults)
        .navigationTitle("Сравнение")
        .searchable(text: $navigation.comparison.searchText, placement: .toolbar, prompt: "Поиск показателя")
    }

    private var selector: some View {
        HStack(spacing: 12) {
            examPicker("Обследование A", selection: $navigation.comparison.examinationA)
            Button {
                swap(&navigation.comparison.examinationA, &navigation.comparison.examinationB)
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Поменять местами")
            examPicker("Обследование B", selection: $navigation.comparison.examinationB)
            Spacer()
            Picker("Показать", selection: $navigation.comparison.filter) {
                ForEach(ComparisonFilter.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
        }
    }

    private func examPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Не выбрано").tag(UUID?.none)
            ForEach(examinations) { exam in
                Text("\(Fmt.shortDate(exam.date)) — \(exam.title)").tag(UUID?.some(exam.id))
            }
        }
        .frame(maxWidth: 340)
    }

    private func selectDefaults() {
        guard state.examinationA == nil || state.examinationB == nil else { return }
        let completed = examinations.filter { $0.status != .draft }
        guard completed.count >= 2 else { return }
        navigation.comparison.examinationB = completed[0].id
        navigation.comparison.examinationA = completed[1].id
    }

    private func report(rows: [ComparisonRow], a: Examination, b: Examination) -> Data {
        PDFReportService.comparisonReport(titleA: a.title, dateA: a.date, titleB: b.title, dateB: b.date, rows: rows)
    }

    @MainActor
    private func export(rows: [ComparisonRow], a: Examination, b: Examination) async {
        do {
            try await FilePanels.export(report(rows: rows, a: a, b: b), title: "Экспорт сравнения",
                                        suggestedName: "Сравнение \(Fmt.shortDate(a.date)) — \(Fmt.shortDate(b.date)).pdf", contentType: .pdf)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить отчёт")
        }
    }
}

struct ComparisonSummaryBar: View {
    let rows: [ComparisonRow]

    var body: some View {
        HStack(spacing: 20) {
            item("Общих показателей", rows.filter(\.isInBoth).count, .primary)
            item("Только в одном", rows.filter { !$0.isInBoth }.count, .secondary)
            item("Пересчитано единиц", rows.filter { if case .converted = $0.compatibility { true } else { false } }.count, .blue)
            item("Несопоставимые единицы", rows.filter { $0.compatibility == .incompatible }.count, .orange)
            item("Изменился статус", rows.filter(\.statusChanged).count, .purple)
            Spacer()
        }
    }

    private func item(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(value)").font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ComparisonTable: View {
    let rows: [ComparisonRow]
    let dateA: Date
    let dateB: Date

    var body: some View {
        Table(rows) {
            TableColumn("Показатель") { row in Text(row.testName).lineLimit(1) }
                .width(min: 180, ideal: 260)
            TableColumn(Fmt.shortDate(dateA)) { row in valueCell(row.a, converted: nil, unit: row.unit) }
                .width(min: 80, ideal: 100)
            TableColumn(Fmt.shortDate(dateB)) { row in
                if case .converted(let fromUnit) = row.compatibility, let value = row.valueB, let b = row.b {
                    Text(Fmt.number(value)).monospacedDigit()
                        .help("Пересчитано из \(b.displayValue) \(fromUnit)")
                } else if row.compatibility == .incompatible, let b = row.b {
                    Text("\(b.displayValue) \(b.unit)").monospacedDigit().foregroundStyle(.orange)
                } else {
                    valueCell(row.b, converted: nil, unit: row.unit)
                }
            }
            .width(min: 80, ideal: 110)
            TableColumn("Ед. изм.") { row in Text(row.unit).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 80)
            TableColumn("Изменение") { row in changeCell(row) }
                .width(min: 150, ideal: 200)
            TableColumn("Статус A") { row in
                if let a = row.a { StatusBadge(status: a.status, compact: true) } else { Text("—").foregroundStyle(.tertiary) }
            }
            .width(min: 100, ideal: 120)
            TableColumn("Статус B") { row in
                if let b = row.b { StatusBadge(status: b.status, compact: true) } else { Text("—").foregroundStyle(.tertiary) }
            }
            .width(min: 100, ideal: 120)
        }
        .accessibilityIdentifier("comparison.table")
    }

    @ViewBuilder
    private func valueCell(_ snapshot: ResultSnapshot?, converted: Double?, unit: String) -> some View {
        if let snapshot {
            Text(snapshot.displayValue).monospacedDigit()
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func changeCell(_ row: ComparisonRow) -> some View {
        switch row.compatibility {
        case .incompatible:
            Label("Несопоставимые единицы", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .help("Единицы \(row.a?.unit ?? "") и \(row.b?.unit ?? "") нельзя корректно пересчитать для этого показателя")
        case .missing:
            Text(row.a == nil ? "нет в A" : "нет в B").font(.caption).foregroundStyle(.tertiary)
        case .qualitative:
            Text(row.statusChanged ? "статус изменился" : "без изменения статуса").font(.caption).foregroundStyle(.secondary)
        default:
            if let difference = row.difference {
                ChangeLabel(absolute: difference, percent: row.percentChange)
            } else {
                Text("значение с «<»/«>»").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
