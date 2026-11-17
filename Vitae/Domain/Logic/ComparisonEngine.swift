import Foundation

/// Строка сравнения двух обследований.
struct ComparisonRow: Identifiable, Hashable, Sendable {
    enum Compatibility: Hashable, Sendable {
        /// Единицы совпадают.
        case same
        /// Значение B пересчитано из другой единицы.
        case converted(fromUnit: String)
        /// Единицы несопоставимы — разница не вычисляется.
        case incompatible
        /// Качественные значения: сравнивается только текст и статус.
        case qualitative
        /// Показатель есть только в одном из обследований.
        case missing
    }

    var id: String { testCode }
    let testCode: String
    let testName: String
    let category: TestCategory
    let sortKey: Int
    let a: ResultSnapshot?
    let b: ResultSnapshot?
    /// Единица, в которой показаны оба значения (единица обследования A, если оно есть).
    let unit: String
    let valueA: Double?
    let valueB: Double?
    let compatibility: Compatibility

    var difference: Double? {
        guard compatibility != .incompatible, let valueA, let valueB,
              a?.value.isExactNumber == true, b?.value.isExactNumber == true else { return nil }
        return valueB - valueA
    }

    var percentChange: Double? {
        guard let difference, let valueA, valueA != 0 else { return nil }
        return difference / abs(valueA) * 100
    }

    var statusChanged: Bool {
        guard let a, let b else { return false }
        return a.status != b.status
    }

    var isInBoth: Bool { a != nil && b != nil }
}

enum ComparisonEngine {
    /// Сопоставляет показатели по коду. Разница считается только для точных числовых значений
    /// в одинаковых или корректно пересчитываемых единицах.
    static func compare(_ first: [ResultSnapshot], _ second: [ResultSnapshot]) -> [ComparisonRow] {
        // Строки без внесённого значения («ожидается») в сравнении не участвуют.
        let mapA = Dictionary(first.filter { !$0.value.isEmpty }.map { ($0.testCode, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let mapB = Dictionary(second.filter { !$0.value.isEmpty }.map { ($0.testCode, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let codes = Set(mapA.keys).union(mapB.keys)

        return codes.map { code -> ComparisonRow in
            let a = mapA[code]
            let b = mapB[code]
            let reference = a ?? b!
            let unit = a?.unit ?? b?.unit ?? ""
            let sortKey = a?.sortIndex ?? b?.sortIndex ?? 0

            guard let a, let b else {
                return ComparisonRow(testCode: code, testName: reference.testName, category: reference.category,
                                     sortKey: sortKey, a: a, b: b, unit: unit,
                                     valueA: a?.value.numeric, valueB: b?.value.numeric, compatibility: .missing)
            }

            guard let numberA = a.value.numeric, let numberB = b.value.numeric else {
                return ComparisonRow(testCode: code, testName: a.testName, category: a.category, sortKey: sortKey,
                                     a: a, b: b, unit: unit, valueA: a.value.numeric, valueB: b.value.numeric,
                                     compatibility: .qualitative)
            }

            if UnitConverter.canonical(a.unit).id == UnitConverter.canonical(b.unit).id {
                return ComparisonRow(testCode: code, testName: a.testName, category: a.category, sortKey: sortKey,
                                     a: a, b: b, unit: unit, valueA: numberA, valueB: numberB, compatibility: .same)
            }
            if let converted = UnitConverter.convert(numberB, from: b.unit, to: a.unit, testCode: code) {
                return ComparisonRow(testCode: code, testName: a.testName, category: a.category, sortKey: sortKey,
                                     a: a, b: b, unit: unit, valueA: numberA, valueB: converted,
                                     compatibility: .converted(fromUnit: b.unit))
            }
            return ComparisonRow(testCode: code, testName: a.testName, category: a.category, sortKey: sortKey,
                                 a: a, b: b, unit: unit, valueA: numberA, valueB: numberB, compatibility: .incompatible)
        }
        .sorted { ($0.category.sortIndex, $0.sortKey, $0.testName) < ($1.category.sortIndex, $1.sortKey, $1.testName) }
    }
}
