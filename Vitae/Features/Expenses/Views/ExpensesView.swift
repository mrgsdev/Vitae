import Charts
import SwiftData
import SwiftUI

struct ExpensesView: View {
    @Bindable var navigation: NavigationModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showNewExpense = false
    @State private var editingExpense: Expense?
    @State private var pendingDelete: Expense?

    private var state: ExpensesState { navigation.expenses }

    var body: some View {
        let snapshots = expenses.map(ExpenseSnapshot.init)
        let currencies = ExpenseAnalytics.currencies(in: snapshots)
        let currency = state.currency.flatMap { currencies.contains($0) ? $0 : nil } ?? currencies.first ?? AppSettings.defaultCurrency
        Group {
            if expenses.isEmpty {
                EmptyStateView(title: "Расходов пока нет", systemImage: "creditcard",
                               message: "Стоимость анализов указывается в редакторе обследования. Можно также добавить отдельный расход.",
                               actionTitle: "Добавить расход") { showNewExpense = true }
            } else {
                content(snapshots: snapshots, currencies: currencies, currency: currency)
            }
        }
        .pageBackground()
        .navigationTitle("Расходы")
        .navigationSubtitle(Fmt.moneyTotals(ExpenseAnalytics.totals(snapshots), emptyText: "Нет расходов"))
        .searchable(text: $navigation.expenses.searchText, placement: .toolbar, prompt: "Позиция, обследование, лаборатория")
        .toolbar { toolbar(snapshots: snapshots) }
        .sheet(isPresented: $showNewExpense) { ExpenseEditorSheet(expense: nil) }
        .sheet(item: $editingExpense) { ExpenseEditorSheet(expense: $0) }
        .confirmationDialog("Удалить расход?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { expense in
            Button("Удалить", role: .destructive) {
                context.delete(expense)
                try? context.save()
                pendingDelete = nil
            }
        } message: { expense in
            Text("«\(expense.title)» на сумму \(Fmt.money(expense.amount, currency: expense.currencyCode)) будет удалён.")
        }
    }

    private func content(snapshots: [ExpenseSnapshot], currencies: [String], currency: String) -> some View {
        let years = Array(Set(snapshots.map { $0.date.year() } + [Date.now.year()])).sorted(by: >)
        let inCurrency = snapshots.filter { $0.currencyCode == currency }
        let yearInterval = ExpenseAnalytics.yearInterval(state.year)
        let monthInterval = ExpenseAnalytics.monthInterval(containing: .now)
        let yearItems = inCurrency.filter { yearInterval?.contains($0.date) ?? false }
        let examCount = Set(yearItems.compactMap(\.examinationID)).count
        let yearTotal = ExpenseAnalytics.total(inCurrency, currency: currency, in: yearInterval)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    if currencies.count > 1 {
                        Picker("Валюта", selection: Binding(get: { currency }, set: { navigation.expenses.currency = $0 })) {
                            ForEach(currencies, id: \.self) { Text(CurrencyCatalog.title($0)).tag($0) }
                        }
                        .fixedSize()
                    }
                    Picker("Год", selection: $navigation.expenses.year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    .fixedSize()
                    Spacer()
                    if currencies.count > 1 {
                        convertedTotalLabel(snapshots)
                    }
                }

                Grid(horizontalSpacing: 12) {
                    GridRow {
                    StatTile(title: "Всего", value: Fmt.money(ExpenseAnalytics.total(inCurrency, currency: currency), currency: currency),
                             systemImage: "sum", caption: "за всё время")
                    StatTile(title: "За \(state.year) год", value: Fmt.money(yearTotal, currency: currency), systemImage: "calendar",
                             caption: Fmt.count(yearItems.count, one: "позиция", few: "позиции", many: "позиций"))
                    StatTile(title: "За текущий месяц", value: Fmt.money(ExpenseAnalytics.total(inCurrency, currency: currency, in: monthInterval), currency: currency),
                             systemImage: "calendar.day.timeline.left", caption: Fmt.monthYear(.now))
                    StatTile(title: "Среднее за обследование",
                             value: examCount == 0 ? "—" : Fmt.money((yearTotal / Decimal(examCount)).rounded(), currency: currency),
                             systemImage: "list.clipboard", caption: "\(state.year): \(Fmt.count(examCount, one: "обследование", few: "обследования", many: "обследований"))")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)], spacing: 16) {
                    Card(title: "По месяцам · \(state.year)", systemImage: "chart.bar") {
                        Chart(ExpenseAnalytics.monthlyTotals(inCurrency, currency: currency, year: state.year)) { item in
                            BarMark(x: .value("Месяц", item.month, unit: .month), y: .value("Сумма", item.amount.doubleValue))
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.narrow).locale(AppLocale.locale))
                            }
                        }
                        .frame(height: 200)
                    }
                    Card(title: "По лабораториям", systemImage: "building.2") {
                        let labs = ExpenseAnalytics.byLaboratory(inCurrency, currency: currency)
                        Chart(labs.prefix(8)) { item in
                            BarMark(x: .value("Сумма", item.amount.doubleValue), y: .value("Лаборатория", item.name))
                                .foregroundStyle(by: .value("Лаборатория", item.name))
                                .annotation(position: .trailing) {
                                    Text(Fmt.money(item.amount, currency: currency)).font(.caption).foregroundStyle(.secondary)
                                }
                        }
                        .chartLegend(.hidden)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks { _ in AxisValueLabel() }
                        }
                        .frame(height: max(120, CGFloat(min(labs.count, 8)) * 34))
                    }
                    let yearly = ExpenseAnalytics.yearlyTotals(inCurrency, currency: currency)
                    if yearly.count > 1 {
                        Card(title: "По годам", systemImage: "chart.bar.xaxis") {
                            Chart(yearly) { item in
                                BarMark(x: .value("Год", String(item.year)), y: .value("Сумма", item.amount.doubleValue))
                                    .foregroundStyle(Color.accentColor.opacity(0.8))
                            }
                            .frame(height: 180)
                        }
                    }
                }

                PriceHistoryCard(snapshots: inCurrency, currency: currency, selectedKey: $navigation.expenses.selectedPriceKey)

                Card(title: "Все расходы", systemImage: "tablecells") {
                    expensesTable(currency: currency)
                        .frame(height: 380)
                }
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func convertedTotalLabel(_ snapshots: [ExpenseSnapshot]) -> some View {
        let base = AppSettings.defaultCurrency
        if let total = ExpenseAnalytics.convertedTotal(ExpenseAnalytics.totals(snapshots), to: base, rates: AppSettings.exchangeRates) {
            Text("≈ \(Fmt.money(total, currency: base)) по курсам из настроек")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Text("Суммы в разных валютах не складываются. Курсы можно задать в настройках.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func expensesTable(currency: String) -> some View {
        let rows = state.filter(expenses.map(ExpenseRow.init), currency: currency)
        return Table(of: ExpenseRow.self, selection: $navigation.expenses.selection, sortOrder: $navigation.expenses.sortOrder) {
            TableColumn("Дата", value: \.date) { row in Text(Fmt.shortDate(row.date)).monospacedDigit() }
                .width(min: 80, ideal: 92)
            TableColumn("Позиция", value: \.title) { row in Text(row.title).lineLimit(1) }
                .width(min: 150, ideal: 240)
            TableColumn("Категория", value: \.categoryTitle) { row in Text(row.categoryTitle).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
            TableColumn("Обследование", value: \.examinationTitle) { row in Text(row.examinationTitle).lineLimit(1) }
                .width(min: 120, ideal: 200)
            TableColumn("Лаборатория", value: \.laboratoryName) { row in Text(row.laboratoryName.isEmpty ? "—" : row.laboratoryName) }
                .width(min: 90, ideal: 140)
            TableColumn("Сумма", value: \.amount) { row in
                Text(Fmt.money(row.amount, currency: row.currencyCode)).monospacedDigit()
            }
            .width(min: 80, ideal: 110)
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let expense = expenses.first(where: { $0.id == id }) {
                if let examID = expense.examination?.id {
                    Button("Открыть обследование") { navigation.openExamination(examID) }
                    Button("Изменить в редакторе обследования…") { openWindow(id: WindowID.editor, value: EditorRequest.edit(examID)) }
                } else {
                    Button("Редактировать…") { editingExpense = expense }
                    Button("Удалить…", role: .destructive) { pendingDelete = expense }
                }
            }
        } primaryAction: { ids in
            guard let id = ids.first, let expense = expenses.first(where: { $0.id == id }) else { return }
            if let examID = expense.examination?.id { navigation.openExamination(examID) } else { editingExpense = expense }
        }
        .onDeleteCommand {
            if let id = state.selection.first, let expense = expenses.first(where: { $0.id == id }), expense.examination == nil {
                pendingDelete = expense
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(snapshots: [ExpenseSnapshot]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Категория", selection: $navigation.expenses.categoryFilter) {
                    Text("Все категории").tag(ExpenseCategory?.none)
                    ForEach(ExpenseCategory.allCases) { Text($0.title).tag(ExpenseCategory?.some($0)) }
                }
                Picker("Лаборатория", selection: $navigation.expenses.laboratoryFilter) {
                    Text("Все лаборатории").tag(String?.none)
                    ForEach(Array(Set(snapshots.compactMap(\.laboratoryName))).sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                }
            } label: {
                Label("Фильтр", systemImage: "line.3.horizontal.decrease.circle")
            }
            Menu {
                Button("Финансовый отчёт за \(state.year) (PDF)…") { Task { await exportReport(snapshots, year: state.year) } }
                Button("Финансовый отчёт за всё время (PDF)…") { Task { await exportReport(snapshots, year: nil) } }
                Button("Расходы (CSV)…") { Task { await ExportActions.exportExpensesCSV(environment: environment) } }
                Divider()
                Button("Печать отчёта за \(state.year)…") { PrintService.printPDF(report(snapshots, year: state.year), jobTitle: "Финансовый отчёт") }
            } label: {
                Label("Отчёты", systemImage: "square.and.arrow.up")
            }
            Button {
                showNewExpense = true
            } label: {
                Label("Добавить расход", systemImage: "plus")
            }
            .help("Добавить расход, не связанный с обследованием")
        }
    }

    private func report(_ snapshots: [ExpenseSnapshot], year: Int?) -> Data {
        guard let year, let interval = ExpenseAnalytics.yearInterval(year) else {
            return PDFReportService.financialReport(expenses: snapshots, periodTitle: "За всё время")
        }
        return PDFReportService.financialReport(expenses: snapshots.filter { interval.contains($0.date) }, periodTitle: "\(year) год")
    }

    @MainActor
    private func exportReport(_ snapshots: [ExpenseSnapshot], year: Int?) async {
        do {
            let name = year.map { "Расходы на анализы \($0).pdf" } ?? "Расходы на анализы.pdf"
            try await FilePanels.export(report(snapshots, year: year), title: "Финансовый отчёт", suggestedName: name, contentType: .pdf)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить отчёт")
        }
    }
}

/// История цен на отдельные исследования: «ферритин стоил 650 ₽, через год — 850 ₽».
struct PriceHistoryCard: View {
    let snapshots: [ExpenseSnapshot]
    let currency: String
    @Binding var selectedKey: String?

    var body: some View {
        let tracked = ExpenseAnalytics.trackedPrices(snapshots, currency: currency)
        Card(title: "История цен", systemImage: "chart.line.uptrend.xyaxis") {
            if tracked.isEmpty {
                Text("Нет данных о ценах.").foregroundStyle(.secondary)
            } else {
                let key = selectedKey.flatMap { k in tracked.contains { $0.key == k } ? k : nil } ?? tracked.first?.key
                HStack(alignment: .top, spacing: 16) {
                    List(tracked, selection: Binding(get: { key }, set: { selectedKey = $0 })) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1)
                                Text(Fmt.count(item.purchases, one: "покупка", few: "покупки", many: "покупок"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Fmt.money(item.lastAmount, currency: currency)).monospacedDigit()
                                if item.purchases > 1 {
                                    Text(Fmt.percent(item.percentChange)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(item.key)
                    }
                    .listStyle(.bordered)
                    .frame(width: 320, height: 260)

                    if let key {
                        let points = ExpenseAnalytics.priceHistory(snapshots, key: key, currency: currency)
                        VStack(alignment: .leading, spacing: 8) {
                            if let first = points.first, let last = points.last, points.count > 1 {
                                Text("\(Fmt.money(first.amount, currency: currency)) (\(Fmt.shortDate(first.date))) → \(Fmt.money(last.amount, currency: currency)) (\(Fmt.shortDate(last.date)))")
                                    .font(.callout)
                            }
                            Chart(points) { point in
                                LineMark(x: .value("Дата", point.date), y: .value("Цена", point.amount.doubleValue))
                                    .interpolationMethod(.stepEnd)
                                    .foregroundStyle(Color.accentColor)
                                PointMark(x: .value("Дата", point.date), y: .value("Цена", point.amount.doubleValue))
                                    .foregroundStyle(Color.accentColor)
                                    .annotation(position: .top) {
                                        Text(Fmt.money(point.amount, currency: currency)).font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits).locale(AppLocale.locale))
                                }
                            }
                            .frame(height: 220)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// Отдельный расход, не связанный с обследованием.
struct ExpenseEditorSheet: View {
    let expense: Expense?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Laboratory.name) private var laboratories: [Laboratory]

    @State private var title = ""
    @State private var amountText = ""
    @State private var currency = AppSettings.defaultCurrency
    @State private var date = Date.now
    @State private var category: ExpenseCategory = .other
    @State private var laboratoryName = ""
    @State private var note = ""
    @State private var loaded = false

    private var amount: Decimal? { NumberParsing.decimal(amountText) }
    private var isValid: Bool { !title.trimmed.isEmpty && (amount ?? -1) >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(expense == nil ? "Новый расход" : "Редактирование расхода")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Название", text: $title, prompt: Text("Например, «Консультация по результатам»"))
                HStack {
                    TextField("Сумма", text: $amountText, prompt: Text("0"))
                    Picker("Валюта", selection: $currency) {
                        ForEach(CurrencyCatalog.codes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                Picker("Категория", selection: $category) {
                    ForEach(ExpenseCategory.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Лаборатория") {
                    LaboratoryField(text: $laboratoryName, laboratories: laboratories.map(\.name))
                }
                TextField("Заметка", text: $note, axis: .vertical).lineLimit(1...3)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save).keyboardShortcut(.defaultAction).disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 480, height: 460)
        .onAppear {
            guard !loaded, let expense else { return }
            loaded = true
            title = expense.title
            amountText = expense.amount.editingString
            currency = expense.currencyCode
            date = expense.date
            category = expense.category
            laboratoryName = expense.laboratory?.name ?? ""
            note = expense.note
        }
    }

    private func save() {
        guard let amount else { return }
        let target = expense ?? Expense(title: title, amount: amount, currencyCode: currency, date: date, category: category)
        if expense == nil { context.insert(target) }
        target.title = title.trimmed
        target.amount = amount
        target.currencyCode = currency
        target.date = date
        target.category = category
        target.note = note
        target.laboratory = ExaminationStore(context: context).laboratory(named: laboratoryName)
        try? context.save()
        dismiss()
    }
}
