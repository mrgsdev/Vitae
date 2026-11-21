import Foundation
import Testing
@testable import Vitae

/// Качественный результат показателя, которого нет в справочнике («HBsAg  не обнаружено  не обнаружено»),
/// не должен пропадать: строка идёт на проверку без привязки, референс лаборатории — текстом.
/// Строки комментариев и шапки при этом не превращаются в результаты.
@MainActor
@Suite("Качественные строки не из справочника")
struct UnmatchedQualitativeTests {
    private func parse(_ lines: [String]) throws -> [ParsedLabItem] {
        let env = try TestEnvironment()
        return LabReportParser(catalog: env.store.catalogIndex()).parse(lines: lines).items
    }

    @Test(arguments: [
        ("HBsAg не обнаружено не обнаружено", "HBsAg", "Не обнаружено", "не обнаружено", ResultStatus.inRange),
        ("Антитела к HCV отрицательно отрицательно", "Антитела к HCV", "Отрицательно", "отрицательно", .inRange),
        ("Антитела к ВИЧ 1/2  отрицательно  отрицательно", "Антитела к ВИЧ 1/2", "Отрицательно", "отрицательно", .inRange),
        ("Anti-HCV total  negative  negative", "Anti-HCV total", "Negative", "negative", .inRange),
        ("Нитриты  не обнаружено  отрицательно", "Нитриты", "Не обнаружено", "отрицательно", .inRange),
        ("HBsAg  обнаружено  не обнаружено", "HBsAg", "Обнаружено", "не обнаружено", .outsideReference),
        // «билирубин» — синоним билирубина крови: привязка к нему была бы ошибкой, строка идёт без привязки.
        ("Билирубин в моче  отрицательно  отрицательно", "Билирубин в моче", "Отрицательно", "отрицательно", .inRange)
    ])
    func qualitativeLineIsKept(_ line: String, name: String, value: String, reference: String, status: ResultStatus) throws {
        let items = try parse([line])
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.testCode == nil)
        #expect(item.isQualitative)
        #expect(item.name == name)
        #expect(item.rawValue == value)
        #expect(item.unit.isEmpty)
        #expect(item.reference == ReferenceRange(text: reference))
        #expect(ReferenceEvaluator.status(rawValue: item.rawValue, reference: item.reference) == status)
    }

    /// Без референса строку держит единица измерения или отсылка к комментарию — как у числовых строк.
    @Test func unitOrCommentMarkerIsEnough() throws {
        let items = try parse([
            "Белок Бенс-Джонса  не обнаружено  г/л",
            "HBsAg  не обнаружено  см. комм.",
            "Рекомендуется повторить исследование через месяц."
        ])
        #expect(items.map(\.name) == ["Белок Бенс-Джонса", "HBsAg"])
        #expect(items.allSatisfy { $0.isQualitative && $0.testCode == nil && $0.rawValue == "Не обнаружено" })
        #expect(items.first?.unit == "г/л")
        #expect(items.first?.reference.isEmpty == true)
        #expect(items.last?.reference.text == LabReportParser.commentReferenceText)
        #expect(items.last?.comment == "Рекомендуется повторить исследование через месяц.")
    }

    @Test(arguments: [
        "Исследование  Результат  Единицы  Референсные значения",
        "Качественный результат: обнаружено / не обнаружено",
        "Отрицательный результат не исключает инфекцию",
        "Антитела к HCV не обнаружены, что не исключает раннюю стадию инфекции",
        "Отрицательно — не обнаружено, положительно — обнаружено",
        "Антитела не обнаружены. Отрицательно.",
        "Результат отрицательный"
    ])
    func commentOrHeaderIsNotResult(_ line: String) throws {
        #expect(try parse([line]).isEmpty)
    }

    /// Фраза комментария с качественным словом остаётся в комментарии, а следующая строка таблицы — результат.
    @Test func commentTextStaysWithItsResult() throws {
        let items = try parse([
            "HBsAg  не обнаружено  см. комм.",
            "Антитела не обнаружены. Отрицательно.",
            "Антитела к HCV  отрицательно  отрицательно"
        ])
        #expect(items.map(\.name) == ["HBsAg", "Антитела к HCV"])
        #expect(items.first?.comment == "Антитела не обнаружены. Отрицательно.")
        #expect(items.last?.reference == ReferenceRange(text: "отрицательно"))
    }
}
