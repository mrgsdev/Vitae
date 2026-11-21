import Foundation
import Testing
@testable import Vitae

/// Цифры в названии показателя не из справочника: «Т3 свободный», «CA 125», «Витамин B6», «ИФР-1».
/// Значение начинается не с первой цифры строки, а с числа после названия.
@MainActor
@Suite("Цифры в названии показателя")
struct DigitInNameTests {
    private func parse(_ lines: [String]) throws -> [ParsedLabItem] {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex()).parse(lines: lines).items
    }

    @Test(arguments: [
        ("Т3 свободный 4.9 пмоль/л 2.6 - 5.7", "Т3 свободный", "4.9"),
        ("Витамин B6 12.5 нг/мл 8.7 - 27.2", "Витамин B6", "12.5"),
        ("ИФР-1 210 нг/мл 115 - 307", "ИФР-1", "210"),
        ("CA 125 12 Ед/мл < 35", "CA 125", "12"),
        ("CA-125 12 Ед/мл < 35", "CA-125", "12"),
        ("СА 15-3 20 Ед/мл < 25", "СА 15-3", "20"),
        ("CA 19-9 15 Ед/мл 0 - 37", "CA 19-9", "15"),
        ("Cyfra 21-1 2.1 нг/мл < 3.3", "Cyfra 21-1", "2.1"),
        ("Интерлейкин 6 (ИЛ-6) 3.2 пг/мл < 7", "Интерлейкин 6 (ИЛ-6)", "3.2"),
        ("17-ОН прогестерон 2.5 нмоль/л 1.2 - 3.8", "17-ОН прогестерон", "2.5"),
        ("Т3 4.9 пмоль/л 2.6 - 5.7", "Т3", "4.9")
    ])
    func digitStaysInName(_ line: String, name: String, value: String) throws {
        let items = try parse([line])
        #expect(items.count == 1, "строка не пропадает")
        #expect(items.first?.testCode == nil, "показателя нет в справочнике")
        #expect(items.first?.name == name)
        #expect(items.first?.rawValue == value)
    }

    @Test func unitAndReferenceComeFromTheValue() throws {
        let t3 = try #require(try parse(["Т3 свободный 4.9 пмоль/л 2.6 - 5.7"]).first)
        #expect(t3.unit == "пмоль/л")
        #expect(t3.reference == ReferenceRange(lower: 2.6, upper: 5.7))

        let ca125 = try #require(try parse(["CA 125 12 Ед/мл < 35"]).first)
        #expect(ca125.reference == ReferenceRange(upper: 35))
    }

    /// «Ca» — краткое название кальция, но «CA 125» — онкомаркер: число после него — часть названия.
    @Test(arguments: [
        ("Ca 2.35 ммоль/л 2.15 - 2.5", "2.35"),
        ("Ca 2 2.15 - 2.5 ммоль/л", "2"),
        ("Ca 2 ммоль/л 2.15 - 2.5", "2")
    ])
    func calciumKeepsItsShortName(_ line: String, value: String) throws {
        let items = try parse([line])
        #expect(items.map(\.testCode) == ["calcium"])
        #expect(items.first?.rawValue == value)
    }

    /// Строки комментариев и шапки по-прежнему не принимаются за результаты.
    @Test(arguments: [
        "Желательный уровень <5,0 ммоль/л",
        "Рекомендуемый уровень 30 - 100 нг/мл",
        "Норма: 3.5 - 5.5 ммоль/л",
        "Целевой уровень для ЛПНП 1.8 - 2.6 ммоль/л",
        "< 20 - дефицит;",
        "30-100 - адекватный уровень (целевые",
        "Дата взятия 12.03.2025 Заказ 125 12 шт < 35"
    ])
    func commentLineIsNotResult(_ line: String) throws {
        #expect(try parse([line]).isEmpty)
    }

    @Test func namePartSkipsDigitsGluedToName() {
        #expect(LabReportParser.namePart(of: "Т3 свободный 4.9 пмоль/л 2.6 - 5.7") == "Т3 свободный")
        #expect(LabReportParser.namePart(of: "ИФР-1 210 нг/мл 115 - 307") == "ИФР-1")
    }
}
