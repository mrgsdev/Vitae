import SwiftData
import SwiftUI

/// Раздел «Динамика»: обзор всех показателей карточками с мини-графиками.
/// Клик по карточке открывает подробный график, статистику и историю измерений.
struct DynamicsView: View {
    @Bindable var navigation: NavigationModel
    @Query private var results: [TestResult]
    @Query private var tests: [LabTest]

    var body: some View {
        let snapshots = results.map(ResultSnapshot.init).filter(\.isAnalyzable)
        let indicators = IndicatorSummary.build(from: snapshots, catalog: CatalogIndex(tests: tests))
        Group {
            if indicators.isEmpty {
                EmptyStateView(title: "Нет данных для динамики", systemImage: "chart.xyaxis.line",
                               message: "Графики появятся, когда в обследованиях будут результаты анализов.")
            } else {
                DynamicsOverview(indicators: indicators,
                                 history: Dictionary(grouping: snapshots, by: \.testCode),
                                 state: $navigation.dynamics)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .navigationTitle("Динамика")
        .searchable(text: $navigation.dynamics.searchText, placement: .toolbar, prompt: "Поиск показателя")
    }
}

private struct DynamicsOverview: View {
    let indicators: [IndicatorSummary]
    let history: [String: [ResultSnapshot]]
    @Binding var state: DynamicsState

    var body: some View {
        let found = indicators.filter { $0.matches(state.searchText) }
        let visible = found.filter { state.filter.includes($0.latest.status) }
        let grouped = Dictionary(grouping: visible, by: \.category)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Все показатели").font(.title.weight(.semibold))
                    Text("У каждого показателя свой график. Нажмите на карточку, чтобы открыть подробный график, статистику и историю измерений.")
                        .foregroundStyle(.secondary)
                }
                controls(found)
                if visible.isEmpty {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "magnifyingglass",
                        description: Text(state.filter == .all ? "Попробуйте изменить запрос." : "Нет показателей с отметкой «\(state.filter.title)». Выберите фильтр «Все».")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                ForEach(TestCategory.allCases.filter { grouped[$0] != nil }) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.title, systemImage: category.symbolName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                            ForEach(grouped[category] ?? []) { item in
                                NavigationLink(value: AppRoute.indicator(item.code)) {
                                    IndicatorCard(summary: item, history: history[item.code] ?? [],
                                                  unit: state.units[item.code], period: state.period)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("dynamics.indicator.\(item.code)")
                            }
                        }
                    }
                }
                Text("Динамика показана без оценки: рост или снижение показателя сами по себе не означают улучшения или ухудшения. Статусы рассчитаны по референсам лабораторий из бланков.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func controls(_ found: [IndicatorSummary]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(IndicatorFilter.allCases) { filter in
                        let count = found.filter { filter.includes($0.latest.status) }.count
                        if filter == .all || count > 0 || state.filter == filter {
                            FilterChip(title: filter.title, count: count, color: filter.color,
                                       isSelected: state.filter == filter) { state.filter = filter }
                                .accessibilityIdentifier("dynamics.filter.\(filter.rawValue)")
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Picker("Период графиков", selection: $state.period) {
                ForEach(DynamicsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("За какой период показывать мини-графики и изменения")
            .accessibilityIdentifier("dynamics.period")
        }
    }
}

/// Кнопка-фильтр в виде капсулы со счётчиком.
struct FilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(isSelected ? Color.white : color).frame(width: 7, height: 7)
                Text(title)
                Text("\(count)").monospacedDigit().opacity(0.7)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? color : Theme.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.separator))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Карточка показателя в обзоре: последнее значение, статус, мини-график и изменение.
private struct IndicatorCard: View {
    let summary: IndicatorSummary
    let history: [ResultSnapshot]
    let unit: String?
    let period: DynamicsPeriod

    @State private var isHovered = false

    var body: some View {
        let series = DynamicsCalculator.series(from: history, unit: unit, period: period)
        let change = DynamicsCalculator.latestChange(for: history)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(summary.name).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summary.latest.displayValue).font(Theme.bigNumber(24)).monospacedDigit().lineLimit(1)
                Text(summary.latest.unit).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(snapshot: summary.latest, compact: true)
            }
            Group {
                if series.points.count >= 2 {
                    MiniDynamicsChart(series: series)
                } else {
                    Text(series.points.isEmpty ? "Нет числовых измерений за период «\(period.title)»"
                                               : "Пока одно измерение — график появится после следующего")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(height: 56)
            HStack(spacing: 6) {
                if let change {
                    ChangeLabel(absolute: change.absoluteChange, percent: change.percentChange, font: .caption)
                    Text("к \(Fmt.shortDate(change.previousDate))").font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text(Fmt.shortDate(summary.latest.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(Fmt.count(summary.count, one: "измерение", few: "измерения", many: "измерений"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        // Один элемент: иначе подсказка карточки достаётся каждому ребёнку и звучит много раз.
        .accessibilityElement(children: .combine)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.6) : Theme.separator, lineWidth: isHovered ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.035), radius: isHovered ? 6 : 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("Открыть график «\(summary.name)»")
    }
}

/// Подробная страница показателя, открывается из обзора, главной, карточки обследования и справочника.
struct IndicatorDetailContainer: View {
    let code: String
    @Bindable var navigation: NavigationModel
    @Query private var results: [TestResult]
    @Query private var tests: [LabTest]

    var body: some View {
        let history = results.map(ResultSnapshot.init).filter { $0.testCode == code && $0.isAnalyzable }
        if let summary = IndicatorSummary.build(from: history, catalog: CatalogIndex(tests: tests)).first {
            IndicatorDetailView(summary: summary, history: history, state: $navigation.dynamics)
                .navigationTitle(summary.name)
        } else {
            ContentUnavailableView("Нет измерений", systemImage: "chart.xyaxis.line",
                                   description: Text("По этому показателю пока нет результатов."))
                .navigationTitle("Динамика")
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
                StatusBadge(snapshot: summary.latest)
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
                        StatusBadge(snapshot: item, compact: true)
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
