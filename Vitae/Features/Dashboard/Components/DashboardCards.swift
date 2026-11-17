import Charts
import SwiftUI

struct LastExaminationCard: View {
    let examination: Examination
    @Environment(\.navigationModel) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Card(title: "Последнее обследование", systemImage: "list.clipboard") {
            VStack(alignment: .leading, spacing: 4) {
                Text(examination.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text([Fmt.date(examination.date), examination.laboratory?.name].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                metric("\(examination.results.count)", "показателей")
                metric("\(examination.deviationCount)", "вне референса")
                metric(Fmt.moneyTotals(examination.costTotals), "стоимость")
            }
            HStack {
                ExaminationStatusBadge(status: examination.status)
                Spacer()
                Button("Повторить") {
                    openWindow(id: WindowID.editor, value: EditorRequest.repeatFrom(examination.id))
                }
                .help("Новое обследование с тем же списком анализов")
                Button("Открыть") { navigation?.openExamination(examination.id) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.bigNumber(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StatusSummaryCard: View {
    let summary: DashboardSummary

    var body: some View {
        Card(title: "Актуальные значения", systemImage: "checklist",
             trailing: Fmt.count(summary.total, one: "показатель", few: "показателя", many: "показателей")) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile(.inRange, "В пределах референса")
                    tile(.below, "Ниже референса")
                }
                GridRow {
                    tile(.above, "Выше референса")
                    tile(.noReference, "Без референса")
                }
            }
            if summary.count(.outsideReference) > 0 {
                Text("Качественных результатов, не совпадающих с референсом: \(summary.count(.outsideReference))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("По последнему значению каждого показателя.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func tile(_ status: ResultStatus, _ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(status.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(summary.count(status))").font(Theme.bigNumber(24)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(status.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct RecentChangesCard: View {
    let changes: [ChangeSummary]
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        Card(title: "Последние изменения", systemImage: "arrow.left.arrow.right") {
            if changes.isEmpty {
                Text("Изменения появятся, когда у показателя будет минимум два измерения в сопоставимых единицах.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(changes) { change in
                        Button {
                            navigation?.openDynamics(code: change.testCode)
                        } label: {
                            row(change)
                        }
                        .buttonStyle(.plain)
                        if change.id != changes.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func row(_ change: ChangeSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.testName).lineLimit(1)
                Text("\(Fmt.number(change.previousValue)) → \(Fmt.number(change.currentValue)) \(change.unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ChangeLabel(absolute: change.absoluteChange, percent: change.percentChange)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct DeviationsCard: View {
    let deviations: [ResultSnapshot]
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        Card(title: "Вне референса", systemImage: "exclamationmark.circle",
             trailing: deviations.isEmpty ? nil : "\(deviations.count)") {
            if deviations.isEmpty {
                Label("Последние значения всех показателей в пределах референсов лабораторий или без референса.",
                      systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(deviations.prefix(8)) { item in
                        Button {
                            navigation?.openDynamics(code: item.testCode)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.testName).lineLimit(1)
                                    Text("референс \(item.reference.displayText) · \(Fmt.shortDate(item.date))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.displayValue) \(item.unit)").monospacedDigit()
                                StatusBadge(status: item.status, compact: true)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(item.id == deviations.prefix(8).last?.id ? 0 : 1)
                    }
                }
                Text("Отклонение от референса не является диагнозом. Обсудите результаты с врачом.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct YearExpensesCard: View {
    let model: DashboardModel
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        Card(title: "Расходы за \(model.currentYear) год", systemImage: "creditcard") {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.moneyTotals(model.yearTotals, emptyText: "Нет расходов"))
                    .font(Theme.bigNumber(26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                Button("Подробнее") { navigation?.show(.expenses) }
                    .buttonStyle(.link)
            }
            let previous = model.previousYearTotals
            if !previous.isEmpty {
                Text("В \(model.currentYear - 1) году: \(Fmt.moneyTotals(previous))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Chart(model.monthlyTotals) { item in
                BarMark(x: .value("Месяц", item.month, unit: .month),
                        y: .value("Сумма", item.amount.doubleValue))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow).locale(AppLocale.locale))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 110)
            Text("График в валюте \(model.primaryCurrency). Суммы в разных валютах не складываются.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct UpcomingRemindersCard: View {
    let reminders: [Reminder]
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        Card(title: "Напоминания", systemImage: "bell") {
            if reminders.isEmpty {
                Text("Нет активных напоминаний. Можно запланировать повторное обследование.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(reminders) { reminder in
                    HStack {
                        Image(systemName: reminder.dueDate < .now ? "exclamationmark.circle.fill" : "calendar")
                            .foregroundStyle(reminder.dueDate < .now ? .orange : .secondary)
                        Text(reminder.title).lineLimit(1)
                        Spacer()
                        Text(Fmt.date(reminder.dueDate)).foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            Button("Все напоминания") { navigation?.show(.reminders) }
                .buttonStyle(.link)
        }
    }
}

struct DashboardEmptyState: View {
    let newExamination: () -> Void
    let importDocument: () -> Void
    let restore: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Добро пожаловать в Vitae").font(.largeTitle.weight(.semibold))
                Text("Храните результаты анализов, следите за динамикой показателей и расходами. Все данные остаются на этом Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            HStack(spacing: 12) {
                Button(action: newExamination) {
                    Label("Новое обследование", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("empty.newExamination")
                Button(action: importDocument) {
                    Label("Импорт документа", systemImage: "doc.text.viewfinder")
                }
                .controlSize(.large)
                Button(action: restore) {
                    Label("Восстановить из копии", systemImage: "clock.arrow.circlepath")
                }
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickSearchResultsView: View {
    let results: QuickSearchResults
    @Environment(\.navigationModel) private var navigation

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search
        } else {
            List {
                if !results.examinations.isEmpty {
                    Section("Обследования") {
                        ForEach(results.examinations) { exam in
                            Button {
                                navigation?.openExamination(exam.id)
                            } label: {
                                HStack {
                                    Image(systemName: "list.clipboard").foregroundStyle(.secondary)
                                    VStack(alignment: .leading) {
                                        Text(exam.title)
                                        Text([Fmt.date(exam.date), exam.laboratory?.name].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ExaminationStatusBadge(status: exam.status)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !results.indicators.isEmpty {
                    Section("Показатели") {
                        ForEach(results.indicators) { item in
                            Button {
                                navigation?.openDynamics(code: item.testCode)
                            } label: {
                                HStack {
                                    Image(systemName: "chart.xyaxis.line").foregroundStyle(.secondary)
                                    Text(item.testName)
                                    Spacer()
                                    Text("\(item.displayValue) \(item.unit)").monospacedDigit()
                                    StatusBadge(status: item.status, compact: true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
