import Foundation
import Testing
@testable import Vitae

/// Слово сразу после найденного синонима может сужать показатель: «ПСА свободный» — не общий ПСА.
/// Такая строка не должна привязываться к общему показателю справочника.
@MainActor
@Suite("Сужающие уточнения в названии показателя")
struct NarrowingModifierTests {
    private func parse(_ lines: [String]) throws -> [ParsedLabItem] {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex()).parse(lines: lines).items
    }

    @Test func freePSADoesNotTakeTotalPSA() throws {
        let items = try parse(["ПСА свободный 0.3 нг/мл 0 - 1", "ПСА общий 1.2 нг/мл < 4"])
        #expect(items.count == 2)
        #expect(items.first?.testCode == nil)
        #expect(items.first?.name == "ПСА свободный")
        #expect(items.first?.rawValue == "0.3")
        #expect(items.last?.testCode == "psa")
        #expect(items.last?.rawValue == "1.2")
    }

    @Test func totalPSAMatchesInAnyOrder() throws {
        let items = try parse(["ПСА общий 1.2 нг/мл < 4", "ПСА свободный 0.3 нг/мл 0 - 1"])
        #expect(items.map(\.testCode) == ["psa", nil])
    }

    @Test(arguments: [
        "Тестостерон свободный 12.3 пг/мл 4.5 - 42",
        "Тестостерон биодоступный 3.1 нмоль/л 2.4 - 13",
        "Билирубин неконъюгированный 9 мкмоль/л < 19",
        "Глюкоза не натощак 6.0 ммоль/л 4.1 - 7.8"
    ])
    func narrowedLineStaysUnmatched(_ line: String) throws {
        let items = try parse([line])
        #expect(items.count == 1)
        #expect(items.first?.testCode == nil)
        #expect(items.first?.name == LabReportParser.namePart(of: line))
    }

    @Test(arguments: [
        ("Холестерин не-ЛПВП 2.96 ммоль/л < 3.8", "lipid.nonhdl"),
        ("Билирубин непрямой 9 мкмоль/л < 19", "bili.indirect"),
        ("Билирубин свободный 9 мкмоль/л < 19", "bili.indirect"),
        ("Т4 свободный 15 пмоль/л 9 - 19", "ft4"),
        ("Тироксин свободный 15 пмоль/л 9 - 19", "ft4"),
        ("Тестостерон общий 18 нмоль/л 8.6 - 29", "testosterone"),
        ("Глюкоза 5.1 ммоль/л 4.1 - 5.9", "glucose")
    ])
    func ownSynonymStillMatches(_ line: String, code: String) throws {
        let items = try parse([line])
        #expect(items.map(\.testCode) == [code])
    }

    /// Качественный результат «не обнаружено» начинается с «не», но это значение, а не уточнение.
    @Test(arguments: [
        ("Белок в моче не обнаружено г/л", "urine.protein", "Не обнаружено"),
        ("Кетоновые тела не обнаружены", "urine.ketones", "Не обнаружены"),
        ("Глюкоза в моче не выявлено ммоль/л", "urine.glucose", "Не выявлено")
    ])
    func negativeQualitativeResultKeepsMatch(_ line: String, code: String, value: String) throws {
        let items = try parse([line])
        #expect(items.map(\.testCode) == [code])
        #expect(items.first?.rawValue == value)
    }
}
