import SwiftUI

/// Точечная шкала референса: точки внутри интервала лаборатории окрашены,
/// вне — серые; маркер показывает положение значения.
struct ReferenceRangeBar: View {
    let value: Double?
    let reference: ReferenceRange
    var dotCount = 44

    private var bounds: (min: Double, max: Double, low: Double, high: Double)? {
        guard reference.hasNumericBounds else { return nil }
        let low = reference.lower ?? 0
        let high = reference.upper ?? max((reference.lower ?? 0) * 2, (value ?? 0) * 1.2, 1)
        let span = max(high - low, abs(high) * 0.1, 0.0001)
        var minValue = low - span * 0.45
        var maxValue = high + span * 0.45
        if let value {
            minValue = min(minValue, value - span * 0.1)
            maxValue = max(maxValue, value + span * 0.1)
        }
        if reference.lower == nil { minValue = min(0, minValue) }
        return (minValue, maxValue, low, high)
    }

    var body: some View {
        if let bounds {
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    let spacing = proxy.size.width / CGFloat(dotCount)
                    let markerIndex = value.map { index(for: $0, bounds) }
                    HStack(spacing: 0) {
                        ForEach(0..<dotCount, id: \.self) { i in
                            let v = bounds.min + (bounds.max - bounds.min) * (Double(i) + 0.5) / Double(dotCount)
                            let inside = v >= bounds.low && v <= bounds.high
                            VStack(spacing: 3) {
                                Circle().fill(color(inside: inside, position: v, bounds: bounds))
                                Circle().fill(color(inside: inside, position: v, bounds: bounds))
                            }
                            .frame(width: spacing * 0.62)
                            .overlay {
                                if markerIndex == i {
                                    Capsule()
                                        .strokeBorder(Color.primary, lineWidth: 1.5)
                                        .frame(width: spacing * 0.95)
                                        .padding(.vertical, -3)
                                }
                            }
                            .frame(width: spacing)
                        }
                    }
                }
                .frame(height: 20)

                HStack {
                    Text(reference.lower.map { Fmt.number($0) } ?? "")
                    Spacer()
                    Text(reference.upper.map { Fmt.number($0) } ?? "")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Референс \(reference.displayText)" + (value.map { ", значение \(Fmt.number($0))" } ?? ""))
        } else {
            Text("Нет данных для оценки — референс лаборатории не указан")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func index(for value: Double, _ bounds: (min: Double, max: Double, low: Double, high: Double)) -> Int {
        let ratio = (value - bounds.min) / max(bounds.max - bounds.min, 0.0001)
        return min(dotCount - 1, max(0, Int(ratio * Double(dotCount))))
    }

    private func color(inside: Bool, position: Double, bounds: (min: Double, max: Double, low: Double, high: Double)) -> Color {
        guard inside else { return Color.primary.opacity(0.1) }
        let center = (bounds.low + bounds.high) / 2
        let half = max((bounds.high - bounds.low) / 2, 0.0001)
        let distance = abs(position - center) / half
        return Color.accentColor.opacity(0.35 + 0.65 * (1 - distance))
    }
}
