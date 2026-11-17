#if DEBUG
import Foundation
import SwiftData

/// Набор данных для UI-тестов. Загружается только при запуске с аргументами
/// `-uiTesting -uiTestingFixture` (хранилище в памяти) через обычный путь сохранения.
@MainActor
enum UITestFixture {
    static var isRequested: Bool {
        RunMode.current == .uiTesting && ProcessInfo.processInfo.arguments.contains("-uiTestingFixture")
    }

    static func loadIfRequested(into context: ModelContext) {
        guard isRequested else { return }
        let store = ExaminationStore(context: context)
        let factory = store.rowFactory()
        let calendar = AppLocale.calendar

        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
        }

        struct Value { let code: String; let value: String; let lower: String; let upper: String; var unit: String? = nil }

        func makeDraft(title: String, date: Date, lab: String, codes: [String], values: [Value], prices: [String: String]) -> ExaminationDraft {
            var draft = ExaminationDraft(title: title, date: date, laboratoryName: lab, currencyCode: "RUB")
            for code in codes {
                guard let entry = factory.catalog.entry(code) else { continue }
                draft.rows += factory.rows(for: entry, laboratory: "", currency: "RUB")
            }
            for value in values {
                guard let index = draft.rows.firstIndex(where: { $0.testCode == value.code }) else { continue }
                draft.rows[index].value = value.value
                draft.rows[index].lower = value.lower
                draft.rows[index].upper = value.upper
                if let unit = value.unit { draft.rows[index].unit = unit }
            }
            for (code, price) in prices {
                if let index = draft.rows.firstIndex(where: { $0.testCode == code && $0.kind.hasPrice }) { draft.rows[index].price = price }
            }
            return draft
        }

        let labA = "Инвитро", labB = "Гемотест"
        let drafts: [ExaminationDraft] = [
            makeDraft(title: "Чек-ап весна", date: date(2023, 4, 12), lab: labA, codes: ["cbc", "ferritin", "vitd", "glucose"],
                      values: [Value(code: "cbc.hgb", value: "128", lower: "130", upper: "160"),
                               Value(code: "cbc.wbc", value: "5,8", lower: "4", upper: "9"),
                               Value(code: "cbc.plt", value: "240", lower: "150", upper: "400"),
                               Value(code: "ferritin", value: "18", lower: "30", upper: "400"),
                               Value(code: "vitd", value: "19", lower: "30", upper: "100"),
                               Value(code: "glucose", value: "5,1", lower: "4,1", upper: "5,9")],
                      prices: ["cbc": "590", "ferritin": "650", "vitd": "2150", "glucose": "310"]),
            makeDraft(title: "Контроль железа", date: date(2023, 10, 3), lab: labA, codes: ["cbc", "ferritin", "vitd"],
                      values: [Value(code: "cbc.hgb", value: "136", lower: "130", upper: "160"),
                               Value(code: "cbc.wbc", value: "6,1", lower: "4", upper: "9"),
                               Value(code: "ferritin", value: "42", lower: "30", upper: "400"),
                               Value(code: "vitd", value: "34", lower: "30", upper: "100")],
                      prices: ["cbc": "620", "ferritin": "720", "vitd": "2250"]),
            makeDraft(title: "Ежегодный чек-ап", date: date(2024, 6, 18), lab: labB, codes: ["cbc", "lipid", "glucose", "hba1c", "tsh", "lpa"],
                      values: [Value(code: "cbc.hgb", value: "14,6", lower: "13,2", upper: "17,3", unit: "г/дл"),
                               Value(code: "cbc.wbc", value: "5,2", lower: "4,5", upper: "11"),
                               Value(code: "lipid.chol", value: "5,9", lower: "", upper: "5,2"),
                               Value(code: "lipid.ldl", value: "3,8", lower: "", upper: "3,0"),
                               Value(code: "lipid.hdl", value: "1,4", lower: "1,0", upper: ""),
                               Value(code: "lipid.tg", value: "1,1", lower: "", upper: "1,7"),
                               Value(code: "glucose", value: "97", lower: "74", upper: "106", unit: "мг/дл"),
                               Value(code: "hba1c", value: "5,4", lower: "4", upper: "6"),
                               Value(code: "tsh", value: "1,9", lower: "0,4", upper: "4"),
                               Value(code: "lpa", value: "38", lower: "", upper: "30")],
                      prices: ["cbc": "650", "lipid": "1200", "glucose": "320", "hba1c": "690", "tsh": "580", "lpa": "1100"]),
            makeDraft(title: "Ежегодный чек-ап", date: date(2025, 6, 25), lab: labA, codes: ["cbc", "lipid", "ferritin", "vitd", "glucose", "lpa"],
                      values: [Value(code: "cbc.hgb", value: "160", lower: "130", upper: "180"),
                               Value(code: "cbc.wbc", value: "6,4", lower: "4", upper: "9"),
                               Value(code: "cbc.plt", value: "255", lower: "150", upper: "400"),
                               Value(code: "lipid.chol", value: "5,1", lower: "", upper: "5,2"),
                               Value(code: "lipid.ldl", value: "3,1", lower: "", upper: "3,0"),
                               Value(code: "lipid.hdl", value: "1,5", lower: "1,0", upper: ""),
                               Value(code: "lipid.tg", value: "0,9", lower: "", upper: "1,7"),
                               Value(code: "ferritin", value: "88", lower: "30", upper: "400"),
                               Value(code: "vitd", value: "41", lower: "30", upper: "100"),
                               Value(code: "glucose", value: "5,3", lower: "4,1", upper: "5,9"),
                               Value(code: "lpa", value: "82", lower: "", upper: "75", unit: "нмоль/л")],
                      prices: ["cbc": "690", "lipid": "1350", "ferritin": "850", "vitd": "2400", "glucose": "350", "lpa": "1250"]),
            makeDraft(title: "Контроль витамина D", date: date(2026, 2, 10), lab: labA, codes: ["vitd", "ferritin", "crp"],
                      values: [Value(code: "vitd", value: "47", lower: "30", upper: "100"),
                               Value(code: "ferritin", value: "95", lower: "30", upper: "400"),
                               Value(code: "crp", value: "<0,6", lower: "0", upper: "5")],
                      prices: ["vitd": "2450", "ferritin": "870", "crp": "540"])
        ]
        for draft in drafts {
            _ = try? store.save(draft, finalize: true)
        }
        var pending = makeDraft(title: "Плановый осмотр", date: date(2026, 11, 10), lab: labB, codes: ["cbc", "b12"], values: [], prices: [:])
        pending.comment = "Черновик для UI-теста"
        _ = try? store.save(pending, finalize: false)

        if let ferritin = try? context.fetch(FetchDescriptor<LabTest>(predicate: #Predicate { $0.code == "ferritin" })).first {
            ferritin.isFavorite = true
        }
        context.insert(Reminder(title: "Сдать ферритин и витамин D", dueDate: date(2026, 12, 15), repeatRule: .halfYear))
        try? context.save()
    }
}
#endif
