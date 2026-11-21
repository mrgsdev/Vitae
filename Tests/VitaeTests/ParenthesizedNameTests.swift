import Foundation
import Testing
@testable import Vitae

/// Уточнение в скобке после названия может содержать цифры: «Тромбоциты (PLT, 10^9/л)».
/// Название не должно обрываться на первой цифре внутри скобки, а следующая строка бланка —
/// приклеиваться к нему только ради того, чтобы «закрыть» скобку.
@MainActor
@Suite("Скобка с цифрами в названии показателя")
struct ParenthesizedNameTests {
    private func parse(_ lines: [String]) throws -> [ParsedLabItem] {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex()).parse(lines: lines).items
    }

    @Test func qualifierWithDigitsStaysInName() throws {
        let items = try parse(["Тромбоциты (PLT, 10^9/л) 250 150 - 400", "Примечание (см. ниже)"])
        #expect(items.count == 1, "строка примечания не результат")
        let plt = try #require(items.first)
        #expect(plt.testCode == "cbc.plt")
        #expect(plt.name == "Тромбоциты (PLT, 10^9/л)")
        #expect(plt.rawValue == "250")
        #expect(plt.reference.lower == 150)
        #expect(plt.reference.upper == 400)
    }

    @Test func aliasInsideParenthesisKeepsWholeQualifier() throws {
        // Синоним «PLT» найден внутри скобки: название всё равно идёт до закрывающей скобки.
        let items = try parse(["Кровяные пластинки (PLT, 10^9/л) 250 150 - 400", "Примечание (см. ниже)"])
        let plt = try #require(items.first)
        #expect(plt.testCode == "cbc.plt")
        #expect(plt.name == "Кровяные пластинки (PLT, 10^9/л)")
        #expect(plt.rawValue == "250")
    }

    @Test func foreignLineDoesNotCloseOpenParenthesis() throws {
        // В строке результата скобка действительно не закрыта, но «Примечание (см. ниже)»
        // закрывает свою скобку, а не скобку названия.
        let items = try parse(["Холестерин-ЛПНП (по 2.41 ммоль/л 0 - 3.0", "Примечание (см. ниже)"])
        let ldl = try #require(items.first)
        #expect(ldl.testCode == "lipid.ldl")
        #expect(ldl.name == "Холестерин-ЛПНП (по")
        #expect(ldl.rawValue == "2.41")
    }

    @Test func nameContinuationStillClosesParenthesis() throws {
        let items = try parse(["Холестерин-ЛПНП (по 2.41 ммоль/л 0 - 3.0", "Фридвальду)"])
        let ldl = try #require(items.first)
        #expect(ldl.name == "Холестерин-ЛПНП (по Фридвальду)")
        #expect(ldl.rawValue == "2.41")
        #expect(ldl.reference.upper == 3.0)
    }
}
