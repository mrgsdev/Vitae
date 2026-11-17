import Foundation
import Testing
@testable import Vitae

@Suite("Статусы результатов и референсы")
struct ReferenceEvaluatorTests {
    private func status(_ raw: String, _ lower: Double?, _ upper: Double?, text: String? = nil) -> ResultStatus {
        ReferenceEvaluator.status(rawValue: raw, reference: ReferenceRange(lower: lower, upper: upper, text: text))
    }

    @Test func numericInsideRange() {
        #expect(status("145", 130, 160) == .inRange)
    }

    @Test func boundsAreInclusive() {
        #expect(status("130", 130, 160) == .inRange)
        #expect(status("160", 130, 160) == .inRange)
    }

    @Test func belowAndAbove() {
        #expect(status("128", 130, 160) == .below)
        #expect(status("161,5", 130, 160) == .above)
    }

    @Test func oneSidedReferences() {
        #expect(status("4,9", nil, 5.2) == .inRange)
        #expect(status("5,9", nil, 5.2) == .above)
        #expect(status("1,4", 1.0, nil) == .inRange)
        #expect(status("0,8", 1.0, nil) == .below)
    }

    @Test func missingReferenceGivesNoData() {
        #expect(status("5,5", nil, nil) == .noReference)
        #expect(ResultStatus.noReference.title == "Нет данных для оценки")
    }

    @Test func emptyValueIsPending() {
        #expect(status("", 1, 2) == .pending)
        #expect(status("   ", nil, nil) == .pending)
    }

    @Test func comparatorValues() {
        #expect(status("<0,5", 0, 5) == .inRange)
        #expect(status("<0,5", 1, 5) == .below)
        #expect(status(">100", 0, 50) == .above)
        #expect(status(">100", 10, nil) == .inRange)
        // «<3» при референсе 1–5: истинное значение может быть ниже 1 — оценить нельзя.
        #expect(status("<3", 1, 5) == .noReference)
        #expect(status("менее 1", 1, 5) == .below)
    }

    @Test func qualitativeMatchingWithSynonyms() {
        #expect(status("отр.", nil, nil, text: "отрицательно") == .inRange)
        #expect(status("Не обнаружено", nil, nil, text: "отрицательно") == .inRange)
        #expect(status("Положительно", nil, nil, text: "отрицательно") == .outsideReference)
        #expect(status("следы", nil, nil, text: nil) == .noReference)
    }

    @Test func deviationFlags() {
        #expect(ResultStatus.below.isDeviation)
        #expect(ResultStatus.above.isDeviation)
        #expect(ResultStatus.outsideReference.isDeviation)
        #expect(!ResultStatus.inRange.isDeviation)
        #expect(!ResultStatus.noReference.isDeviation)
    }
}

@Suite("Разбор чисел и референсов")
struct ParsingTests {
    @Test func numbersWithCommaSpacesAndMinus() {
        #expect(NumberParsing.double("5,5") == 5.5)
        #expect(NumberParsing.double(" 1 250,75 ") == 1250.75)
        #expect(NumberParsing.double("1,250.75") == 1250.75)
        #expect(NumberParsing.double("−3,2") == -3.2)
        #expect(NumberParsing.double(",5") == 0.5)
        #expect(NumberParsing.double("5,5,5") == nil)
        #expect(NumberParsing.double("abc") == nil)
        #expect(NumberParsing.double("") == nil)
    }

    @Test func decimalsKeepPrecision() {
        #expect(NumberParsing.decimal("650,10") == Decimal(string: "650.1"))
        #expect(NumberParsing.decimal("1\u{00A0}250") == Decimal(1250))
    }

    @Test func parsedValueComparators() {
        let less = ParsedValue.parse("< 0,5")
        #expect(less.numeric == 0.5)
        #expect(less.comparator == .less)
        let text = ParsedValue.parse("не обнаружено")
        #expect(text.numeric == nil)
        #expect(text.text == "не обнаружено")
        #expect(ParsedValue.parse("≥10").comparator == .greaterOrEqual)
    }

    @Test func referenceRangeParsing() {
        #expect(ReferenceRange.parse("3,5 – 5,5") == ReferenceRange(lower: 3.5, upper: 5.5))
        #expect(ReferenceRange.parse("130-160") == ReferenceRange(lower: 130, upper: 160))
        #expect(ReferenceRange.parse("< 5") == ReferenceRange(upper: 5))
        #expect(ReferenceRange.parse("до 5,2") == ReferenceRange(upper: 5.2))
        #expect(ReferenceRange.parse("> 1,0") == ReferenceRange(lower: 1))
        #expect(ReferenceRange.parse("отрицательно") == ReferenceRange(text: "отрицательно"))
        #expect(ReferenceRange.parse("").isEmpty)
    }

    @Test func referenceDisplay() {
        #expect(ReferenceRange(lower: 3.5, upper: 5.5).displayText == "3,5–5,5")
        #expect(ReferenceRange(upper: 5).displayText == "≤ 5")
        #expect(ReferenceRange().displayText == "—")
    }

    @Test func russianPlurals() {
        #expect(Fmt.count(1, one: "показатель", few: "показателя", many: "показателей") == "1 показатель")
        #expect(Fmt.count(3, one: "показатель", few: "показателя", many: "показателей") == "3 показателя")
        #expect(Fmt.count(11, one: "показатель", few: "показателя", many: "показателей") == "11 показателей")
        #expect(Fmt.count(21, one: "показатель", few: "показателя", many: "показателей") == "21 показатель")
    }
}

@Suite("Конвертация единиц")
struct UnitConverterTests {
    @Test func equivalentSpellings() {
        #expect(UnitConverter.areEquivalent("г/л", "g/L"))
        #expect(UnitConverter.areEquivalent("×10⁹/л", "10^9/L"))
        #expect(UnitConverter.areEquivalent("10*9/л", "тыс/мкл"))
        #expect(UnitConverter.areEquivalent("мкмоль/л", "umol/L"))
        #expect(UnitConverter.areEquivalent("нг/мл", "мкг/л"))
        #expect(UnitConverter.areEquivalent("мкМЕ/мл", "мМЕ/л"))
        #expect(UnitConverter.areEquivalent("Ед/л", "U/L"))
        #expect(!UnitConverter.areEquivalent("ммоль/л", "мг/дл"))
    }

    @Test func sameDimensionScaling() throws {
        let gdl = try #require(UnitConverter.convert(160, from: "г/л", to: "г/дл", testCode: "cbc.hgb"))
        #expect(abs(gdl - 16) < 1e-9)
        let mgl = try #require(UnitConverter.convert(1, from: "мг/дл", to: "мг/л", testCode: "crp"))
        #expect(abs(mgl - 10) < 1e-9)
        let ukat = try #require(UnitConverter.convert(60, from: "Ед/л", to: "мккат/л", testCode: "alt"))
        #expect(abs(ukat - 1) < 1e-9)
    }

    @Test func molarMassConversions() throws {
        let glucose = try #require(UnitConverter.convert(5.5, from: "ммоль/л", to: "мг/дл", testCode: "glucose"))
        #expect(abs(glucose - 99.088) < 0.01)
        let back = try #require(UnitConverter.convert(99.088, from: "mg/dL", to: "mmol/L", testCode: "glucose"))
        #expect(abs(back - 5.5) < 0.001)
        let vitd = try #require(UnitConverter.convert(30, from: "нг/мл", to: "нмоль/л", testCode: "vitd"))
        #expect(abs(vitd - 74.88) < 0.05)
        let chol = try #require(UnitConverter.convert(5.0, from: "ммоль/л", to: "мг/дл", testCode: "lipid.chol"))
        #expect(abs(chol - 193.3) < 0.1)
    }

    @Test func specialFormulas() throws {
        let ifcc = try #require(UnitConverter.convert(6.5, from: "%", to: "ммоль/моль", testCode: "hba1c"))
        #expect(abs(ifcc - 47.5) < 0.1)
        let insulin = try #require(UnitConverter.convert(10, from: "мкЕд/мл", to: "пмоль/л", testCode: "insulin"))
        #expect(abs(insulin - 60) < 1e-6)
    }

    @Test func incompatibleUnitsAreNotConverted() {
        // Липопротеин (а): мг/дл и нмоль/л несопоставимы.
        #expect(UnitConverter.convert(30, from: "мг/дл", to: "нмоль/л", testCode: "lpa") == nil)
        // Без кода показателя масса ↔ моль не пересчитывается.
        #expect(UnitConverter.convert(5.5, from: "ммоль/л", to: "мг/дл", testCode: nil) == nil)
        #expect(UnitConverter.convert(5, from: "%", to: "г/л", testCode: "cbc.hct") == nil)
    }

    @Test func referenceConversion() throws {
        let range = try #require(UnitConverter.convert(ReferenceRange(lower: 130, upper: 160), from: "г/л", to: "г/дл", testCode: "cbc.hgb"))
        #expect(range.lower == 13)
        #expect(range.upper == 16)
    }

    @Test func availableUnitsForGlucose() {
        let units = UnitConverter.availableUnits(testCode: "glucose", observedUnits: ["mmol/L"], baseUnit: "ммоль/л")
        #expect(units.contains("ммоль/л"))
        #expect(units.contains("мг/дл"))
        #expect(units.count == 2)
    }
}
