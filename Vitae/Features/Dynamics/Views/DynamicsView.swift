import SwiftData
import SwiftUI

struct DynamicsView: View {
    @Bindable var navigation: NavigationModel
    @Query private var results: [TestResult]

    var body: some View {
        Group {
            switch navigation.dynamics.mode {
            case .indicator:
                indicatorMode
            case .comparison:
                ComparisonView(navigation: navigation)
            }
        }
        .navigationTitle("Динамика")
        .searchable(text: $navigation.dynamics.searchText, placement: .toolbar, prompt: "Поиск показателя")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Режим", selection: $navigation.dynamics.mode) {
                    ForEach(DynamicsMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("dynamics.mode")
            }
        }
    }

    @ViewBuilder
    private var indicatorMode: some View {
        let snapshots = results.map(ResultSnapshot.init)
        let indicators = IndicatorSummary.build(from: snapshots)
        if indicators.isEmpty {
            EmptyStateView(title: "Нет данных для динамики", systemImage: "chart.xyaxis.line",
                           message: "Динамика строится по завершённым обследованиям. Добавьте результаты анализов.")
        } else {
            let query = navigation.dynamics.searchText
            let filtered = indicators.filter { $0.name.matchesSearch(query) }
            HStack(spacing: 0) {
                IndicatorListView(indicators: filtered, selection: $navigation.dynamics.selectedCode)
                    .frame(width: 300)
                Divider()
                if let code = navigation.dynamics.selectedCode, let summary = indicators.first(where: { $0.code == code }) {
                    IndicatorDetailView(summary: summary,
                                        history: snapshots.filter { $0.testCode == code && $0.isAnalyzable },
                                        state: $navigation.dynamics)
                        .id(code)
                } else {
                    ContentUnavailableView("Выберите показатель", systemImage: "chart.xyaxis.line",
                                           description: Text("Слева — все показатели, по которым есть результаты."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                if navigation.dynamics.selectedCode == nil { navigation.dynamics.selectedCode = indicators.first?.code }
            }
        }
    }
}

struct IndicatorListView: View {
    let indicators: [IndicatorSummary]
    @Binding var selection: String?

    var body: some View {
        let grouped = Dictionary(grouping: indicators, by: \.category)
        List(selection: $selection) {
            ForEach(TestCategory.allCases.filter { grouped[$0] != nil }) { category in
                Section(category.title) {
                    ForEach(grouped[category] ?? []) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.latest.status.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).lineLimit(1)
                                Text("\(Fmt.shortDate(item.latest.date)) · \(Fmt.count(item.count, one: "измерение", few: "измерения", many: "измерений"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("\(item.latest.displayValue) \(item.latest.unit)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(item.code)
                        .accessibilityIdentifier("dynamics.indicator.\(item.code)")
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if indicators.isEmpty { ContentUnavailableView.search }
        }
    }
}

struct IndicatorDetailView: View {
    let summary: IndicatorSummary
    let history: [ResultSnapshot]
    @Binding var state: DynamicsState
    @Environment(\.navigationModel) private var navigation

    private var baseUnit: String {
        DynamicsCalculator.preferredUnit(for: history) ?? summary.latest.unit
    }

    private var units: [String] {
        UnitConverter.availableUnits(testCode: summary.code, observedUnits: history.map(\.unit), baseUnit: baseUnit)
    }

    private var unit: String {
        let chosen = state.units[summary.code] ?? baseUnit
        return units.contains(chosen) ? chosen : baseUnit
    }

    private var series: DynamicsSeries {
        DynamicsCalculator.series(from: history, unit: unit, period: state.period)
    }

    var body: some View {
        let series = self.series
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controls
                if series.points.isEmpty && series.qualitative.isEmpty {
                    Card {
                        Text("За выбранный период измерений нет.").foregroundStyle(.secondary)
                    }
                }
                if !series.points.isEmpty {
                    Card(title: "График", systemImage: "chart.xyaxis.line", trailing: unit) {
                        DynamicsChart(series: series)
                            .frame(height: 320)
                        legend
                        if !series.incompatible.isEmpty {
                            Label("Не показаны \(series.incompatible.count) измерений в единицах, которые нельзя корректно пересчитать в «\(unit)»: \(Set(series.incompatible.map(\.unit)).sorted().joined(separator: ", ")).",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let statistics = series.statistics {
                    Card(title: "Статистика", systemImage: "sum", trailing: state.period.title) {
                        StatisticsGrid(statistics: statistics, unit: unit)
                        if series.points.contains(where: \.isApproximate) {
                            Text("Значения со знаком сравнения («<», «>») показаны на графике ромбом и не участвуют в расчётах.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                historyCard(series)
                Text("Динамика показана без оценки: рост или снижение показателя сами по себе не означают улучшения или ухудшения. Статусы рассчитаны по референсам лабораторий из бланков.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await exportPDF(series) }
                } label: {
                    Label("Экспорт в PDF", systemImage: "square.and.arrow.up")
                }
                .help("Сохранить историю показателя в PDF")
                Button {
                    PrintService.printPDF(reportData(series), jobTitle: summary.name)
                } label: {
                    Label("Печать", systemImage: "printer")
                }
                .help("Напечатать историю показателя")
            }
        }
        .focusedSceneValue(\.printAction, PrintAction(title: summary.name) {
            PrintService.printPDF(reportData(series), jobTitle: summary.name)
        })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(summary.category.title, systemImage: summary.category.symbolName)
                .font(.callout).foregroundStyle(.secondary)
            Text(summary.name).font(.largeTitle.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.latest.displayValue).font(Theme.bigNumber(44)).monospacedDigit()
                Text(summary.latest.unit).font(.title2).foregroundStyle(.secondary)
                StatusBadge(status: summary.latest.status)
                    .padding(.leading, 6)
            }
            Text([Fmt.date(summary.latest.date), summary.latest.laboratoryName, summary.latest.reference.isEmpty ? nil : "референс \(summary.latest.reference.displayText)"]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Период", selection: $state.period) {
                ForEach(DynamicsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("dynamics.period")
            if units.count > 1 {
                Picker("Единица", selection: Binding(get: { unit }, set: { state.units[summary.code] = $0 })) {
                    ForEach(units, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
                .help("Значения в других единицах пересчитываются только по корректным формулам")
            }
            Spacer()
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([ResultStatus.inRange, .below, .above, .noReference], id: \.self) { status in
                HStack(spacing: 4) {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                    Text(status.shortTitle)
                }
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.2)).frame(width: 14, height: 8)
                Text("референс лаборатории")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func historyCard(_ series: DynamicsSeries) -> some View {
        let rows = (series.points.map(\.source) + series.incompatible + series.qualitative).sorted { $0.date > $1.date }
        let converted = Dictionary(series.points.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Card(title: "История измерений", systemImage: "list.bullet.rectangle", trailing: "\(rows.count)") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Дата"); Text("Значение"); Text("Референс"); Text("Статус"); Text("Лаборатория"); Text("Обследование")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows) { item in
                    GridRow {
                        Text(Fmt.shortDate(item.date)).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.displayValue) \(item.unit)").monospacedDigit()
                            if let point = converted[item.id], point.wasConverted {
                                Text("= \(Fmt.number(point.value)) \(series.unit)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(item.reference.displayText).monospacedDigit().foregroundStyle(.secondary)
                        StatusBadge(status: item.status, compact: true)
                        Text(item.laboratoryName ?? "—").lineLimit(1).foregroundStyle(.secondary)
                        Button(item.examinationTitle.isEmpty ? "Открыть" : item.examinationTitle) {
                            if let id = item.examinationID { navigation?.openExamination(id) }
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .disabled(item.examinationID == nil || navigation == nil)
                    }
                    .font(.callout)
                }
            }
        }
    }

    @MainActor
    private func reportData(_ series: DynamicsSeries) -> Data {
        let renderer = ImageRenderer(content: DynamicsChart(series: series, interactive: false)
            .frame(width: 900, height: 340)
            .padding(10)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        return PDFReportService.historyReport(testName: summary.name, series: series, chart: renderer.cgImage)
    }

    @MainActor
    private func exportPDF(_ series: DynamicsSeries) async {
        do {
            try await FilePanels.export(reportData(series), title: "Экспорт истории показателя",
                                        suggestedName: FilePanels.safeFileName("История — \(summary.name).pdf"), contentType: .pdf)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить отчёт")
        }
    }
}
