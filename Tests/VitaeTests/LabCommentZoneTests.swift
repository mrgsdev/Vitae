import Foundation
import Testing
@testable import Vitae

/// Зоны комментария лаборатории: «< X» и «> X» — строгие границы,
/// а подпись зоны не спорит со статусом по референсу.
@Suite("Зоны комментария лаборатории")
struct LabCommentZoneTests {
    /// Комментарий Инвитро к витамину D.
    private let invitro = "< 10 нг/мл - выраженный дефицит; 10-20 нг/мл - дефицит; 20-30 нг/мл - недостаточность; "
        + "30-100 нг/мл - адекватный уровень; > 100 нг/мл - избыток."

    private func label(_ value: String, _ comment: String) -> String? {
        LabCommentInterpreter.label(for: ParsedValue.parse(value), comment: comment)
    }

    private func snapshot(_ value: String, note: String, reference: ReferenceRange) -> ResultSnapshot {
        var snapshot = ResultSnapshot(date: .now, testCode: "vitd", testName: "Витамин D", rawValue: value, unit: "нг/мл",
                                      reference: reference)
        snapshot.note = note
        return snapshot
    }

    @Test func strictUpperBoundDoesNotIncludeItsValue() {
        #expect(LabCommentInterpreter.zone(for: 100, in: invitro)?.text == "30-100 нг/мл - адекватный уровень")
        #expect(label("100", invitro) == "Адекватный уровень", "«> 100» — строго больше")
        #expect(label("100,5", invitro) == "Избыток")
        #expect(label("10", invitro) == "Дефицит", "«< 10» — строго меньше")
        #expect(label("9,9", invitro) == "Выраженный дефицит")

        let result = snapshot("100", note: invitro, reference: ReferenceRange(lower: 30, upper: 100))
        #expect(result.status == .inRange)
        #expect(result.statusLabel == "Адекватный уровень")
        #expect(result.statusShortTitle == "Адекватный уровень")
        #expect(result.commentZone?.text == "30-100 нг/мл - адекватный уровень", "«Зона по комментарию» в инспекторе")
    }

    @Test func valueInGapAfterStrictZoneHasNoLabel() {
        let comment = "< 10 - выраженный дефицит; 20-30 - недостаточность; 30-100 - адекватный уровень"
        #expect(LabCommentInterpreter.zone(for: 10, in: comment) == nil)
        #expect(label("10", comment) == nil, "10 не входит в «< 10» и не дотягивает до «20-30»")
        #expect(label("9", comment) == "Выраженный дефицит")
        #expect(label("15", comment) == nil)
    }

    @Test func wordComparatorsKeepTheirMeaning() {
        let tail = "; 20-30 - недостаточность; 30-100 - адекватный уровень"
        #expect(label("10", "менее 10 - дефицит" + tail) == nil, "«менее» — строго")
        #expect(label("10", "≤ 10 - дефицит" + tail) == "Дефицит")
        #expect(label("10", "<= 10 - дефицит" + tail) == "Дефицит")
        #expect(label("10", "не более 10 - дефицит" + tail) == "Дефицит")
        #expect(label("10", "до 10 - дефицит" + tail) == "Дефицит")

        let head = "20-30 - недостаточность; 30-100 - адекватный уровень; "
        #expect(label("100", head + "более 100 - избыток") == "Адекватный уровень", "«более» — строго")
        #expect(label("100,1", head + "более 100 - избыток") == "Избыток")
    }

    /// На стыке двух отрезков значение относится к целевой зоне: у референса границы нестрогие,
    /// и 100 при «30-100 - адекватный уровень» — «В пределах».
    @Test func junctionWithTargetZoneFollowsReference() {
        let comment = "20-30 - недостаточность; 30-100 - адекватный уровень; 100-150 - избыток"
        #expect(label("100", comment) == "Адекватный уровень")
        #expect(label("30", comment) == "Адекватный уровень")
        #expect(label("120", comment) == "Избыток")
        #expect(label("100", "30-100 - адекватный уровень; ≥ 100 - избыток") == "Адекватный уровень")
        // Стык двух нецелевых зон — по-прежнему следующая зона.
        #expect(label("20", "10-20 - дефицит; 20-30 - недостаточность; 30-100 - адекватный уровень") == "Недостаточность")
    }

    /// Подпись по комментарию сверяется с референсом, который из него выведен: для любого значения
    /// целевая зона подписывается только «В пределах», остальные — только вне референса.
    @Test func labelAgreesWithReferenceAcrossValues() throws {
        let comments = [
            invitro,
            "< 10 - выраженный дефицит; 20-30 - недостаточность; 30-100 - адекватный уровень",
            "20-30 - недостаточность; 30-100 - адекватный уровень; 100-150 - избыток",
            "≤ 30 - недостаточность; 30-100 - адекватный уровень; ≥ 100 - избыток",
        ]
        for comment in comments {
            let reference = try #require(LabCommentInterpreter.targetReference(in: comment))
            for step in 0...400 {
                let value = ParsedValue.parse(String(Double(step) / 2))
                guard let text = LabCommentInterpreter.label(for: value, comment: comment) else { continue }
                let inRange = ReferenceEvaluator.status(for: value, reference: reference) == .inRange
                #expect((text == "Адекватный уровень") == inRange, "\(value.numeric ?? -1) → «\(text)» в «\(comment)»")
            }
        }
    }

    /// Референс на бланке может не совпадать с целевой зоной комментария (или его поправили вручную).
    /// Подпись, которая спорит со статусом, не показывается — остаётся обычный статус.
    @Test func labelDoesNotContradictResultReference() {
        let above = snapshot("90", note: invitro, reference: ReferenceRange(lower: 30, upper: 80))
        #expect(above.status == .above)
        #expect(above.statusLabel == nil, "«Адекватный уровень» при «Выше» противоречит референсу")
        #expect(above.statusShortTitle == ResultStatus.above.shortTitle)
        #expect(above.commentZone == nil)
        #expect(LabCommentInterpreter.label(for: above.value, comment: invitro, status: .above) == nil, "значок StatusBadge")

        let inRange = snapshot("25", note: invitro, reference: ReferenceRange(lower: 20, upper: 100))
        #expect(inRange.status == .inRange)
        #expect(inRange.statusLabel == nil, "«Недостаточность» при «В пределах» противоречит референсу")

        let below = snapshot("25", note: invitro, reference: ReferenceRange(lower: 30, upper: 100))
        #expect(below.statusLabel == "Недостаточность")

        let chol = "Рекомендации по интерпретации: желательный уровень <5,0 ммоль/л."
        let cholAbove = snapshot("4,8", note: chol, reference: ReferenceRange(upper: 4.5))
        #expect(cholAbove.status == .above)
        #expect(cholAbove.statusLabel == nil, "«Желательный уровень» при «Выше» противоречит референсу")

        // Без референса спорить не с чем: остаются слова лаборатории.
        let noTarget = snapshot("15", note: "< 20 - дефицит; 20-30 - недостаточность", reference: ReferenceRange())
        #expect(noTarget.status == .noReference)
        #expect(noTarget.statusLabel == "Дефицит")
    }
}
