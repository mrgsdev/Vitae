import Foundation

enum DynamicsPeriod: String, CaseIterable, Identifiable, Sendable {
    case threeMonths, sixMonths, year, threeYears, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMonths: "3 мес"
        case .sixMonths: "6 мес"
        case .year: "1 год"
        case .threeYears: "3 года"
        case .all: "Всё время"
        }
    }

    func startDate(relativeTo now: Date, calendar: Calendar = AppLocale.calendar) -> Date? {
        switch self {
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .threeYears: calendar.date(byAdding: .year, value: -3, to: now)
        case .all: nil
        }
    }
}

struct DynamicsPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
    /// Значение со знаком сравнения («<0,5») — показывается на графике, но не участвует в статистике.
    let isApproximate: Bool
    let reference: ReferenceRange
    let status: ResultStatus
    let wasConverted: Bool
    let source: ResultSnapshot
}

struct DynamicsStatistics: Equatable, Sendable {
    let first: Double
    let last: Double
    let minimum: Double
    let maximum: Double
    let mean: Double
    let count: Int
    let firstDate: Date
    let lastDate: Date

    var absoluteChange: Double { last - first }
    var percentChange: Double? { first == 0 ? nil : (last - first) / abs(first) * 100 }
}

struct DynamicsSeries: Sendable {
    let unit: String
    let points: [DynamicsPoint]
    /// Числовые значения в единицах, которые нельзя корректно пересчитать.
    let incompatible: [ResultSnapshot]
    /// Качественные значения (текст).
    let qualitative: [ResultSnapshot]

    var statistics: DynamicsStatistics? { DynamicsCalculator.statistics(for: points) }
    var isEmpty: Bool { points.isEmpty && qualitative.isEmpty && incompatible.isEmpty }
}

/// Изменение показателя между двумя последними сопоставимыми измерениями.
struct ChangeSummary: Identifiable, Hashable, Sendable {
    var id: String { testCode }
    let testCode: String
    let testName: String
    let unit: String
    let previousValue: Double
    let previousDate: Date
    let currentValue: Double
    let currentDate: Date
    let currentStatus: ResultStatus

    var absoluteChange: Double { currentValue - previousValue }
    var percentChange: Double? { previousValue == 0 ? nil : (currentValue - previousValue) / abs(previousValue) * 100 }
}

enum DynamicsCalculator {
    static func sorted(_ results: [ResultSnapshot]) -> [ResultSnapshot] {
        results.sorted { ($0.date, $0.sortIndex) < ($1.date, $1.sortIndex) }
    }

    /// Единица отображения по умолчанию: та, в которую корректно пересчитывается больше всего
    /// измерений; при равенстве — единица самого свежего из них.
    static func preferredUnit(for results: [ResultSnapshot]) -> String? {
        let numeric = sorted(results.filter { $0.isAnalyzable && $0.value.isNumeric })
        var best: (unit: String, count: Int, recency: Int)?
        for (index, candidate) in numeric.enumerated().reversed() {
            if let current = best, UnitConverter.canonical(current.unit).id == UnitConverter.canonical(candidate.unit).id { continue }
            let count = numeric.filter { UnitConverter.canConvert(from: $0.unit, to: candidate.unit, testCode: $0.testCode) }.count
            if best == nil || count > best!.count {
                best = (candidate.unit, count, index)
            }
        }
        return best?.unit
    }

    /// Строит ряд значений в целевой единице. Значения в несопоставимых единицах
    /// не пересчитываются «на глаз», а выносятся в отдельный список.
    static func series(from results: [ResultSnapshot], unit targetUnit: String? = nil,
                       period: DynamicsPeriod = .all, now: Date = .now) -> DynamicsSeries {
        let start = period.startDate(relativeTo: now)
        let relevant = sorted(results.filter { $0.isAnalyzable && (start == nil || $0.date >= start!) })
        let numeric = relevant.filter { $0.value.isNumeric }
        let qualitative = relevant.filter { !$0.value.isNumeric }
        let target = targetUnit ?? preferredUnit(for: results) ?? numeric.last?.unit ?? ""

        var points: [DynamicsPoint] = []
        var incompatible: [ResultSnapshot] = []
        for result in numeric {
            guard let number = result.value.numeric,
                  let converted = UnitConverter.convert(number, from: result.unit, to: target, testCode: result.testCode) else {
                incompatible.append(result)
                continue
            }
            let reference = UnitConverter.convert(result.reference, from: result.unit, to: target, testCode: result.testCode) ?? ReferenceRange()
            points.append(DynamicsPoint(
                id: result.id,
                date: result.date,
                value: converted,
                isApproximate: result.value.comparator != nil,
                reference: reference,
                status: result.status,
                wasConverted: UnitConverter.canonical(result.unit).id != UnitConverter.canonical(target).id,
                source: result
            ))
        }
        return DynamicsSeries(unit: target, points: points, incompatible: incompatible, qualitative: qualitative)
    }

    static func statistics(for points: [DynamicsPoint]) -> DynamicsStatistics? {
        let exact = points.filter { !$0.isApproximate }.sorted { $0.date < $1.date }
        guard let first = exact.first, let last = exact.last else { return nil }
        let values = exact.map(\.value)
        return DynamicsStatistics(
            first: first.value,
            last: last.value,
            minimum: values.min() ?? first.value,
            maximum: values.max() ?? first.value,
            mean: values.reduce(0, +) / Double(values.count),
            count: values.count,
            firstDate: first.date,
            lastDate: last.date
        )
    }

    /// Последнее изменение по показателю: последнее значение и предыдущее сопоставимое.
    static func latestChange(for results: [ResultSnapshot]) -> ChangeSummary? {
        let exact = sorted(results.filter { $0.isAnalyzable && $0.value.isExactNumber })
        guard let current = exact.last, let currentValue = current.value.numeric else { return nil }
        for previous in exact.dropLast().reversed() where previous.date < current.date || previous.examinationID != current.examinationID {
            guard let raw = previous.value.numeric,
                  let converted = UnitConverter.convert(raw, from: previous.unit, to: current.unit, testCode: current.testCode) else { continue }
            return ChangeSummary(testCode: current.testCode, testName: current.testName, unit: current.unit,
                                 previousValue: converted, previousDate: previous.date,
                                 currentValue: currentValue, currentDate: current.date, currentStatus: current.status)
        }
        return nil
    }
}

/// Сводка для главного экрана.
struct DashboardSummary: Sendable {
    let latestByTest: [ResultSnapshot]
    let statusCounts: [ResultStatus: Int]
    let changes: [ChangeSummary]
    let deviations: [ResultSnapshot]

    func count(_ status: ResultStatus) -> Int { statusCounts[status] ?? 0 }
    var total: Int { latestByTest.count }
}

enum DashboardAnalytics {
    static func summarize(_ results: [ResultSnapshot], changeLimit: Int = 8) -> DashboardSummary {
        let usable = results.filter(\.isAnalyzable)
        let grouped = Dictionary(grouping: usable, by: \.testCode)
        let latest = grouped.values.compactMap { group in
            group.max { ($0.date, $0.sortIndex) < ($1.date, $1.sortIndex) }
        }
        .sorted { ($0.category.sortIndex, $0.testName) < ($1.category.sortIndex, $1.testName) }

        var counts: [ResultStatus: Int] = [:]
        for item in latest { counts[item.status, default: 0] += 1 }

        let changes = grouped.values.compactMap { DynamicsCalculator.latestChange(for: $0) }
            .sorted { ($0.currentDate, abs($0.percentChange ?? 0)) > ($1.currentDate, abs($1.percentChange ?? 0)) }
            .prefix(changeLimit)

        let deviations = latest.filter { $0.status.isDeviation }
            .sorted { ($0.status.sortRank, $0.testName) < ($1.status.sortRank, $1.testName) }

        return DashboardSummary(latestByTest: latest, statusCounts: counts, changes: Array(changes), deviations: deviations)
    }
}
