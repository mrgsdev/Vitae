import AppKit
import Foundation

/// Отчёты в PDF: обследование, сравнение двух обследований, история показателя, финансы.
enum PDFReportService {
    static let disclaimer = "Отчёт сформирован автоматически из личного архива Vitae. Он не является медицинским заключением, " +
        "не содержит диагнозов и рекомендаций. Статусы рассчитаны по референсам лаборатории, указанным в бланке результата."

    struct ProfileInfo {
        var name: String
        var birthDate: Date?
    }

    private static func profileLines(_ profile: ProfileInfo?) -> [(String, String)] {
        guard let profile, !profile.name.trimmed.isEmpty || profile.birthDate != nil else { return [] }
        var pairs: [(String, String)] = []
        if !profile.name.trimmed.isEmpty { pairs.append(("Пациент", profile.name)) }
        if let birth = profile.birthDate { pairs.append(("Дата рождения", Fmt.shortDate(birth))) }
        return pairs
    }

    // MARK: Обследование

    static func examinationReport(title: String, date: Date, laboratory: String?, status: ExaminationStatus, comment: String,
                                  results: [ResultSnapshot], expenses: [ExpenseSnapshot], profile: ProfileInfo?) -> Data {
        let pdf = PDFBuilder(title: title)
        pdf.title(title, subtitle: [Fmt.date(date), laboratory].compactMap { $0?.nilIfEmpty }.joined(separator: " · "))
        var info = profileLines(profile)
        info.append(("Статус", status.title))
        info.append(("Показателей", "\(results.count)"))
        info.append(("Отклонений от референса", "\(results.filter { $0.status.isDeviation }.count)"))
        info.append(("Стоимость", Fmt.moneyTotals(ExpenseAnalytics.totals(expenses), emptyText: "не указана")))
        pdf.keyValues(info)

        pdf.heading("Результаты")
        let sorted = results.sorted { $0.sortIndex < $1.sortIndex }
        let rows = sorted.map { r in
            [r.panelName.map { "\($0): \(r.testName)" } ?? r.testName, r.displayValue, r.unit, r.reference.displayText, r.status.shortTitle]
        }
        let highlights = Set(sorted.enumerated().filter { $0.element.status.isDeviation }.map(\.offset))
        pdf.table(columns: [
            .init(title: "Показатель", width: 0.38),
            .init(title: "Результат", width: 0.14, alignment: .right),
            .init(title: "Ед. изм.", width: 0.13),
            .init(title: "Референс", width: 0.17),
            .init(title: "Статус", width: 0.18)
        ], rows: rows, highlights: highlights)

        if !expenses.isEmpty {
            pdf.heading("Расходы")
            pdf.table(columns: [
                .init(title: "Позиция", width: 0.6),
                .init(title: "Категория", width: 0.2),
                .init(title: "Сумма", width: 0.2, alignment: .right)
            ], rows: expenses.map { [$0.title, $0.category.title, Fmt.money($0.amount, currency: $0.currencyCode)] })
        }

        if !comment.trimmed.isEmpty {
            pdf.heading("Комментарий")
            pdf.paragraph(comment)
        }
        pdf.spacer()
        pdf.paragraph(disclaimer, size: 8, color: .gray)
        return pdf.finish()
    }

    // MARK: Сравнение

    static func comparisonReport(titleA: String, dateA: Date, titleB: String, dateB: Date, rows: [ComparisonRow]) -> Data {
        let title = "Сравнение обследований"
        let pdf = PDFBuilder(title: title)
        pdf.title(title, subtitle: "\(Fmt.shortDate(dateA)) «\(titleA)» → \(Fmt.shortDate(dateB)) «\(titleB)»")
        let common = rows.filter(\.isInBoth)
        pdf.keyValues([
            ("Общих показателей", "\(common.count)"),
            ("Несопоставимые единицы", "\(rows.filter { $0.compatibility == .incompatible }.count)"),
            ("Изменился статус", "\(rows.filter(\.statusChanged).count)")
        ])
        let tableRows = rows.map { row -> [String] in
            let a = row.a.map { row.valueA.map { Fmt.number($0) } ?? $0.displayValue } ?? "—"
            let b = row.b.map { row.valueB.map { Fmt.number($0) } ?? $0.displayValue } ?? "—"
            let change: String
            switch row.compatibility {
            case .incompatible: change = "несопоставимые единицы"
            case .missing: change = "—"
            case .qualitative: change = row.statusChanged ? "статус изменился" : "—"
            default: change = row.difference.map { "\(Fmt.signedNumber($0)) (\(Fmt.percent(row.percentChange)))" } ?? "—"
            }
            return [row.testName, a, b, row.unit, change]
        }
        let highlights = Set(rows.enumerated().filter { $0.element.statusChanged }.map(\.offset))
        pdf.table(columns: [
            .init(title: "Показатель", width: 0.34),
            .init(title: Fmt.shortDate(dateA), width: 0.14, alignment: .right),
            .init(title: Fmt.shortDate(dateB), width: 0.14, alignment: .right),
            .init(title: "Ед. изм.", width: 0.13),
            .init(title: "Изменение", width: 0.25)
        ], rows: tableRows, highlights: highlights)
        pdf.paragraph("Разница рассчитывается только для значений в одинаковых или корректно пересчитываемых единицах. " +
                      "Направление изменения само по себе не означает улучшения или ухудшения.", size: 8, color: .gray)
        pdf.paragraph(disclaimer, size: 8, color: .gray)
        return pdf.finish()
    }

    // MARK: История показателя

    static func historyReport(testName: String, series: DynamicsSeries, chart: CGImage?) -> Data {
        let title = "История: \(testName)"
        let pdf = PDFBuilder(title: title)
        pdf.title(title, subtitle: "Единица отображения: \(series.unit.isEmpty ? "—" : series.unit)")
        if let chart { pdf.image(chart) }
        if let stats = series.statistics {
            pdf.keyValues([
                ("Первое значение", "\(Fmt.number(stats.first)) · \(Fmt.shortDate(stats.firstDate))"),
                ("Последнее значение", "\(Fmt.number(stats.last)) · \(Fmt.shortDate(stats.lastDate))"),
                ("Минимум / максимум", "\(Fmt.number(stats.minimum)) / \(Fmt.number(stats.maximum))"),
                ("Среднее", Fmt.number(stats.mean, maxFraction: 2)),
                ("Изменение", "\(Fmt.signedNumber(stats.absoluteChange)) (\(Fmt.percent(stats.percentChange)))"),
                ("Измерений", "\(stats.count)")
            ])
        }
        let points = series.points.sorted { $0.date > $1.date }
        pdf.heading("Измерения")
        pdf.table(columns: [
            .init(title: "Дата", width: 0.16),
            .init(title: "Значение", width: 0.16, alignment: .right),
            .init(title: "Референс", width: 0.18),
            .init(title: "Статус", width: 0.2),
            .init(title: "Лаборатория", width: 0.3)
        ], rows: points.map {
            [Fmt.shortDate($0.date), ($0.isApproximate ? $0.source.displayValue : Fmt.number($0.value)) + ($0.wasConverted ? "*" : ""),
             $0.reference.displayText, $0.status.shortTitle, $0.source.laboratoryName ?? ""]
        }, highlights: Set(points.enumerated().filter { $0.element.status.isDeviation }.map(\.offset)))
        if points.contains(where: \.wasConverted) {
            pdf.paragraph("* значение пересчитано из другой единицы измерения.", size: 8, color: .gray)
        }
        if !series.incompatible.isEmpty {
            pdf.paragraph("Не показаны \(series.incompatible.count) измерений в несопоставимых единицах.", size: 8, color: .gray)
        }
        pdf.paragraph(disclaimer, size: 8, color: .gray)
        return pdf.finish()
    }

    // MARK: Финансы

    static func financialReport(expenses: [ExpenseSnapshot], periodTitle: String) -> Data {
        let title = "Финансовый отчёт"
        let pdf = PDFBuilder(title: title)
        pdf.title(title, subtitle: periodTitle)
        let totals = ExpenseAnalytics.totals(expenses)
        pdf.keyValues([("Итого", Fmt.moneyTotals(totals, emptyText: "нет расходов")), ("Записей", "\(expenses.count)")])

        for currency in ExpenseAnalytics.currencies(in: expenses) {
            let labs = ExpenseAnalytics.byLaboratory(expenses, currency: currency)
            pdf.heading("По лабораториям (\(currency))")
            pdf.table(columns: [
                .init(title: "Лаборатория", width: 0.6),
                .init(title: "Позиций", width: 0.15, alignment: .right),
                .init(title: "Сумма", width: 0.25, alignment: .right)
            ], rows: labs.map { [$0.name, "\($0.count)", Fmt.money($0.amount, currency: currency)] })
        }

        pdf.heading("Все расходы")
        pdf.table(columns: [
            .init(title: "Дата", width: 0.14),
            .init(title: "Позиция", width: 0.36),
            .init(title: "Обследование", width: 0.3),
            .init(title: "Сумма", width: 0.2, alignment: .right)
        ], rows: expenses.sorted { $0.date < $1.date }.map {
            [Fmt.shortDate($0.date), $0.title, $0.examinationTitle ?? "—", Fmt.money($0.amount, currency: $0.currencyCode)]
        })
        pdf.paragraph("Суммы в разных валютах не складываются.", size: 8, color: .gray)
        return pdf.finish()
    }
}
