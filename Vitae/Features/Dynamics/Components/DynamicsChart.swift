import Charts
import SwiftUI

/// Большой график динамики: линия значений, точки по статусу, зона референса лаборатории,
/// интерактивная подсказка при наведении.
struct DynamicsChart: View {
    let series: DynamicsSeries
    var interactive = true

    @State private var selectedDate: Date?

    private struct BandPoint: Identifiable {
        let id = UUID()
        let date: Date
        let lower: Double
        let upper: Double
    }

    private var points: [DynamicsPoint] { series.points.sorted { $0.date < $1.date } }

    private var band: [BandPoint] {
        points.compactMap { point in
            guard let lower = point.reference.lower, let upper = point.reference.upper else { return nil }
            return BandPoint(date: point.date, lower: lower, upper: upper)
        }
    }

    private var bandIsConstant: Bool {
        guard let first = band.first else { return false }
        return band.allSatisfy { $0.lower == first.lower && $0.upper == first.upper }
    }

    private var dateDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else { return Date.now...Date.now }
        let span = max(last.timeIntervalSince(first), 86_400 * 30)
        return first.addingTimeInterval(-span * 0.04)...last.addingTimeInterval(span * 0.04)
    }

    /// Масштаб по значениям. Границы референса включаются, если они рядом со значениями;
    /// очень широкий референс (например, 30–400) обрезается краем графика, чтобы не сжимать данные.
    private var valueDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let dataMin = values.min(), let dataMax = values.max() else { return 0...1 }
        let dataSpan = max(dataMax - dataMin, abs(dataMax) * 0.25, 0.1)
        var minValue = dataMin, maxValue = dataMax
        for point in points {
            if let lower = point.reference.lower { minValue = min(minValue, max(lower, dataMin - dataSpan * 1.5)) }
            if let upper = point.reference.upper { maxValue = max(maxValue, min(upper, dataMax + dataSpan * 1.5)) }
        }
        let span = max(maxValue - minValue, 0.1)
        let lower = minValue - span * 0.12
        return (dataMin >= 0 ? max(0, lower) : lower)...(maxValue + span * 0.12)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, valueDomain.lowerBound), valueDomain.upperBound)
    }

    private var selectedPoint: DynamicsPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        Chart {
            if bandIsConstant, let first = band.first {
                RectangleMark(xStart: .value("Начало", dateDomain.lowerBound), xEnd: .value("Конец", dateDomain.upperBound),
                              yStart: .value("Нижняя граница", clamp(first.lower)), yEnd: .value("Верхняя граница", clamp(first.upper)))
                    .foregroundStyle(Color.green.opacity(0.1))
            } else {
                ForEach(band) { item in
                    AreaMark(x: .value("Дата", item.date),
                             yStart: .value("Нижняя граница", clamp(item.lower)),
                             yEnd: .value("Верхняя граница", clamp(item.upper)))
                        .interpolationMethod(.stepCenter)
                        .foregroundStyle(Color.green.opacity(0.1))
                }
            }

            if band.isEmpty, let upper = points.last?.reference.upper, valueDomain.contains(upper) {
                RuleMark(y: .value("Верхняя граница", upper))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.green.opacity(0.7))
            }
            if band.isEmpty, let lower = points.last?.reference.lower, valueDomain.contains(lower) {
                RuleMark(y: .value("Нижняя граница", lower))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.green.opacity(0.7))
            }

            ForEach(points) { point in
                LineMark(x: .value("Дата", point.date), y: .value("Значение", point.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }

            ForEach(points) { point in
                PointMark(x: .value("Дата", point.date), y: .value("Значение", point.value))
                    .foregroundStyle(point.status.color)
                    .symbolSize(point.isApproximate ? 40 : 80)
                    .symbol(point.isApproximate ? BasicChartSymbolShape.diamond : BasicChartSymbolShape.circle)
            }

            if interactive, let selected = selectedPoint {
                RuleMark(x: .value("Дата", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(point: selected, unit: series.unit)
                    }
            }
        }
        .chartXScale(domain: dateDomain)
        .chartYScale(domain: valueDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits).locale(AppLocale.locale))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6))
        }
        .chartXSelection(value: interactive ? $selectedDate : .constant(nil))
        .accessibilityLabel("График динамики, \(points.count) измерений")
    }
}

private struct ChartTooltip: View {
    let point: DynamicsPoint
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(point.status.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(point.isApproximate ? point.source.displayValue : Fmt.number(point.value)) \(unit)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(Fmt.date(point.date)).font(.caption)
                if !point.reference.isEmpty {
                    Text("реф. \(point.reference.displayText)").font(.caption2)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }
}

struct StatisticsGrid: View {
    let statistics: DynamicsStatistics
    let unit: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            tile("Первое", Fmt.number(statistics.first, maxFraction: 2), Fmt.shortDate(statistics.firstDate))
            tile("Последнее", Fmt.number(statistics.last, maxFraction: 2), Fmt.shortDate(statistics.lastDate))
            tile("Минимум", Fmt.number(statistics.minimum, maxFraction: 2), nil)
            tile("Максимум", Fmt.number(statistics.maximum, maxFraction: 2), nil)
            tile("Среднее", Fmt.number(statistics.mean, maxFraction: 2), nil)
            tile("Изменение", Fmt.signedNumber(statistics.absoluteChange), unit)
            tile("Изменение, %", Fmt.percent(statistics.percentChange), "от первого значения")
            tile("Измерений", "\(statistics.count)", nil)
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(Theme.bigNumber(20)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(caption ?? " ").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
