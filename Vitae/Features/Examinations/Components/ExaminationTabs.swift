import SwiftData
import SwiftUI

/// История значений по коду показателя — для расчёта «предыдущего значения».
struct ResultHistoryIndex {
    private let byCode: [String: [ResultSnapshot]]

    init(results: [TestResult]) {
        let snapshots = results.map(ResultSnapshot.init).filter(\.isAnalyzable)
        byCode = Dictionary(grouping: snapshots, by: \.testCode).mapValues { DynamicsCalculator.sorted($0) }
    }

    func history(for code: String) -> [ResultSnapshot] { byCode[code] ?? [] }

    /// Предыдущее сопоставимое значение до даты, пересчитанное в единицу текущего результата.
    func previous(before result: ResultSnapshot) -> (value: Double, date: Date)? {
        for item in history(for: result.testCode).reversed()
        where item.date < result.date && item.examinationID != result.examinationID && item.value.isExactNumber {
            guard let raw = item.value.numeric,
                  let converted = UnitConverter.convert(raw, from: item.unit, to: result.unit, testCode: result.testCode) else { continue }
            return (converted, item.date)
        }
        return nil
    }
}

// MARK: - Результаты

struct ExaminationResultsTab: View {
    let examination: Examination
    @Binding var selection: UUID?
    @Query private var allResults: [TestResult]

    var body: some View {
        let index = ResultHistoryIndex(results: allResults)
        let rows = examination.sortedResults.map(ResultSnapshot.init)
        if rows.isEmpty {
            EmptyStateView(title: "Нет результатов", systemImage: "tablecells",
                           message: "Откройте редактор, чтобы добавить анализы и результаты.")
        } else {
            Table(rows, selection: $selection) {
                TableColumn("Показатель") { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.testName).lineLimit(1)
                        if let panel = row.panelName {
                            Text(panel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .width(min: 180, ideal: 280)
                TableColumn("Результат") { row in
                    Text(row.displayValue)
                        .monospacedDigit()
                        .fontWeight(row.status.isDeviation ? .semibold : .regular)
                        .foregroundStyle(row.status == .pending ? .secondary : .primary)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Ед. изм.") { row in Text(row.unit).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 80)
                TableColumn("Референс") { row in Text(row.reference.displayText).monospacedDigit() }
                    .width(min: 80, ideal: 110)
                TableColumn("Статус") { row in StatusBadge(snapshot: row, compact: true) }
                    .width(min: 100, ideal: 170)
                TableColumn("Предыдущее") { row in
                    if let previous = index.previous(before: row), let current = row.value.numeric, row.value.isExactNumber {
                        HStack(spacing: 6) {
                            Text(Fmt.number(previous.value)).monospacedDigit().foregroundStyle(.secondary)
                            ChangeLabel(absolute: current - previous.value,
                                        percent: previous.value == 0 ? nil : (current - previous.value) / abs(previous.value) * 100)
                        }
                        .help("Предыдущее значение от \(Fmt.date(previous.date))")
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(min: 140, ideal: 190)
            }
            .accessibilityIdentifier("examination.results")
        }
    }
}

/// Панель сведений о выбранном результате.
struct ResultInspector: View {
    let result: TestResult?
    @Environment(\.navigationModel) private var navigation
    @Query private var allResults: [TestResult]
    @Query private var tests: [LabTest]

    var body: some View {
        if let result {
            let snapshot = ResultSnapshot(result)
            let history = ResultHistoryIndex(results: allResults).history(for: result.testCode)
            let series = DynamicsCalculator.series(from: history, unit: result.unit)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.testName).font(.title3.weight(.semibold))
                        if let panel = result.panelName { Text(panel).foregroundStyle(.secondary) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot.displayValue).font(Theme.bigNumber(36)).monospacedDigit()
                        Text(result.unit).font(.title3).foregroundStyle(.secondary)
                    }
                    StatusBadge(snapshot: snapshot)
                    ReferenceRangeBar(value: snapshot.value.numeric, reference: snapshot.reference)
                    InfoRow(title: "Референс лаборатории", value: snapshot.reference.displayText)
                    if !snapshot.note.isEmpty {
                        if let zone = snapshot.commentZone {
                            InfoRow(title: "Зона по комментарию", value: zone.text)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Комментарий лаборатории").font(.callout).foregroundStyle(.secondary)
                            Text(snapshot.note).font(.callout).textSelection(.enabled)
                        }
                    }

                    if let details = tests.first(where: { $0.code == result.testCode })?.details, !details.isEmpty {
                        Divider()
                        CardHeader(title: "О показателе", systemImage: "text.alignleft")
                        Text(details).font(.callout)
                    }

                    if series.points.count >= 2 {
                        Divider()
                        CardHeader(title: "История", systemImage: "chart.xyaxis.line", trailing: "\(series.points.count) изм.")
                        SparklineView(points: series.points.map { .init(date: $0.date, value: $0.value) })
                            .frame(height: 70)
                    }
                    if let navigation {
                        Button("Открыть динамику показателя") { navigation.openDynamics(code: result.testCode) }
                    }
                    Text("Статус рассчитан по референсу из бланка и не является медицинским заключением.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("Показатель не выбран", systemImage: "cursorarrow.click",
                                   description: Text("Выберите строку таблицы, чтобы увидеть референс, описание и историю."))
        }
    }
}

// MARK: - Динамика

struct ExaminationDynamicsTab: View {
    let examination: Examination
    @Environment(\.navigationModel) private var navigation
    @Query private var allResults: [TestResult]

    var body: some View {
        let index = ResultHistoryIndex(results: allResults)
        let items = examination.sortedResults.map(ResultSnapshot.init).filter { $0.value.isNumeric }
        let withHistory = items.filter { index.history(for: $0.testCode).count >= 2 }
        if withHistory.isEmpty {
            EmptyStateView(title: "Недостаточно данных", systemImage: "chart.xyaxis.line",
                           message: "Динамика появится, когда показатели этого обследования будут измерены хотя бы дважды.")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(withHistory) { item in
                        let series = DynamicsCalculator.series(from: index.history(for: item.testCode), unit: item.unit)
                        let previous = index.previous(before: item)
                        Button {
                            navigation?.openDynamics(code: item.testCode)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.testName).font(.headline).lineLimit(1)
                                    Spacer()
                                    StatusBadge(snapshot: item, compact: true)
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(item.displayValue).font(Theme.bigNumber(24)).monospacedDigit()
                                    Text(item.unit).foregroundStyle(.secondary)
                                }
                                SparklineView(points: series.points.map { .init(date: $0.date, value: $0.value) })
                                    .frame(height: 56)
                                if let previous, let current = item.value.numeric {
                                    ChangeLabel(absolute: current - previous.value,
                                                percent: previous.value == 0 ? nil : (current - previous.value) / abs(previous.value) * 100)
                                    Text("по сравнению с \(Fmt.date(previous.date))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(navigation == nil)
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Расходы

struct ExaminationExpensesTab: View {
    let examination: Examination
    @Environment(\.openWindow) private var openWindow
    @Query private var allExpenses: [Expense]

    var body: some View {
        let snapshots = allExpenses.map(ExpenseSnapshot.init)
        let items = examination.expenses.sorted { $0.createdAt < $1.createdAt }
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                EmptyStateView(title: "Расходы не указаны", systemImage: "creditcard",
                               message: "Стоимость анализов можно указать в редакторе обследования.",
                               actionTitle: "Указать стоимость") {
                    openWindow(id: WindowID.editor, value: EditorRequest.edit(examination.id))
                }
            } else {
                Table(items) {
                    TableColumn("Позиция") { expense in Text(expense.title) }
                        .width(min: 200, ideal: 300)
                    TableColumn("Категория") { expense in Text(expense.category.title).foregroundStyle(.secondary) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Сумма") { expense in
                        Text(Fmt.money(expense.amount, currency: expense.currencyCode)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("Прошлая цена") { expense in
                        previousPrice(for: ExpenseSnapshot(expense), in: snapshots)
                    }
                    .width(min: 160, ideal: 220)
                }
                Divider()
                HStack {
                    Text("Итого").font(.headline)
                    Spacer()
                    Text(Fmt.moneyTotals(examination.costTotals)).font(.headline).monospacedDigit()
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func previousPrice(for expense: ExpenseSnapshot, in all: [ExpenseSnapshot]) -> some View {
        let history = ExpenseAnalytics.priceHistory(all, key: expense.priceKey, currency: expense.currencyCode)
        if let previous = history.last(where: { $0.date < expense.date && $0.id != expense.id }) {
            let change = expense.amount - previous.amount
            let percent = previous.amount == 0 ? nil : change.doubleValue / previous.amount.doubleValue * 100
            HStack(spacing: 6) {
                Text(Fmt.money(previous.amount, currency: expense.currencyCode)).foregroundStyle(.secondary)
                Text(Fmt.percent(percent)).font(.caption.monospacedDigit())
            }
            .help("Цена от \(Fmt.date(previous.date))")
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}
