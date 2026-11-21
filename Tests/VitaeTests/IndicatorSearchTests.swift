import Foundation
import Testing
@testable import Vitae

/// Результат хранит название как в бланке, поэтому у одного показателя их бывает несколько:
/// «Холестерин ЛПВП» в одной лаборатории и «Холестерин-ЛПВП» в Инвитро, «25-OH витамин D»
/// и «Витамин 25(ОН) D». Карточка в «Динамике» не должна менять заголовок после каждого
/// импорта, а поиск — терять показатель, если запрос совпадает со справочником, а не с последним бланком.
@Suite("Название и поиск показателя в «Динамике»")
struct IndicatorSearchTests {
    private let catalog = CatalogIndex(entries: CatalogSeedData.entries)

    private func snapshot(_ code: String, _ name: String, month: Int) -> ResultSnapshot {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 1))!
        return ResultSnapshot(date: date, testCode: code, testName: name, category: .other, rawValue: "1.5", unit: "")
    }

    /// Сначала бланк другой лаборатории, затем более поздний бланк Инвитро.
    private var history: [ResultSnapshot] {
        [
            snapshot("lipid.hdl", "Холестерин ЛПВП", month: 3),
            snapshot("vitd", "25-OH витамин D", month: 3),
            snapshot("lipid.hdl", "Холестерин-ЛПВП", month: 9),
            snapshot("vitd", "Витамин 25(ОН) D", month: 9),
        ]
    }

    private func found(_ query: String) -> [String] {
        IndicatorSummary.build(from: history, catalog: catalog)
            .filter { $0.matches(query) }
            .map(\.code)
    }

    @Test func titleIsCatalogNameRegardlessOfLatestBlank() throws {
        let summaries = IndicatorSummary.build(from: history, catalog: catalog)
        let hdl = try #require(summaries.first { $0.code == "lipid.hdl" })
        let vitD = try #require(summaries.first { $0.code == "vitd" })
        #expect(hdl.name == "Холестерин ЛПВП")
        #expect(vitD.name == "Витамин D (25-OH)")
        #expect(vitD.latest.testName == "Витамин 25(ОН) D", "последний результат по-прежнему хранит название из бланка")
    }

    @Test(arguments: [
        "Витамин D",          // начало названия в справочнике
        "витамин д",          // синоним справочника
        "25(OH)D",            // краткое название
        "Витамин 25(ОН) D",   // как в бланке Инвитро, с кириллическими «ОН»
        "25-OH витамин D",    // как в более раннем бланке
    ])
    func vitaminDFoundByAnyKnownName(query: String) {
        #expect(found(query) == ["vitd"])
    }

    @Test(arguments: ["Холестерин ЛПВП", "HDL", "липопротеинов высокой плотности", "Холестерин-ЛПВП"])
    func hdlFoundByAnyKnownName(query: String) {
        #expect(found(query) == ["lipid.hdl"])
    }

    @Test func emptyQueryKeepsEverything() {
        #expect(Set(found("  ")) == ["lipid.hdl", "vitd"])
    }

    @Test func unknownCodeFallsBackToLatestBlankName() throws {
        // Запись справочника удалена: заголовок — из последнего бланка, поиск — по всем бланкам.
        let results = [snapshot("custom.gone", "Старое название", month: 1), snapshot("custom.gone", "Новое название", month: 2)]
        let summary = try #require(IndicatorSummary.build(from: results, catalog: catalog).first)
        #expect(summary.name == "Новое название")
        #expect(summary.matches("старое"))
    }
}
