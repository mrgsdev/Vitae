import Foundation
import Testing
@testable import Vitae

/// Целевой уровень из фраз комментария. Если лаборатория назвала несколько целевых уровней —
/// в разных предложениях или в одном, — референс не выбирается и статус остаётся
/// «Нет данных для оценки».
@MainActor
@Suite("Целевой уровень в комментарии лаборатории")
struct CommentTargetLevelTests {
    /// Пример из QA: оптимальный ≤2,6 и желательный ≤3,0 с отдельным уровнем для группы риска ≤1,8.
    private let ldlComment = "Оптимальный уровень <2,6 ммоль/л. "
        + "Желательный уровень <3,0 ммоль/л; для лиц с высоким риском <1,8 ммоль/л."

    private func label(_ value: String, _ comment: String) -> String? {
        LabCommentInterpreter.label(for: ParsedValue.parse(value), comment: comment)
    }

    @Test func severalLevelsInOneTargetSentenceGiveNoReference() {
        #expect(LabCommentInterpreter.targetReference(in: ldlComment) == nil,
                "предложение с двумя уровнями не выпадает из проверки")
        #expect(LabCommentInterpreter.targetReference(
            in: "Желательный уровень <3,0 ммоль/л; для лиц с высоким риском <1,8 ммоль/л.") == nil)
        #expect(LabCommentInterpreter.targetReference(
            in: "Желательный уровень <3,0 ммоль/л. Для лиц с высоким риском желательный уровень <1,8 ммоль/л, "
                + "с очень высоким <1,4 ммоль/л.") == nil)
    }

    @Test func severalLevelsGiveNoStatusLabel() {
        #expect(label("2,0", ldlComment) == nil, "в пределах одного из уровней — подписи нет")
        #expect(label("2,8", ldlComment) == nil)
        #expect(label("3,5", ldlComment) == nil)
    }

    @Test func parserLeavesAmbiguousCommentWithoutReference() throws {
        let env = try TestEnvironment()
        let parser = LabReportParser(catalog: env.store.catalogIndex(), knownLaboratories: [])
        let report = try parser.parse(lines: [
            "Исследование Результат Единицы Референсные значения Комментарий",
            "Холестерин-ЛПНП 2.8 ммоль/л см.комм. Оптимальный уровень <2,6 ммоль/л.",
            "Желательный уровень <3,0 ммоль/л; для лиц с",
            "высоким риском <1,8 ммоль/л.",
            "Фосфатаза щелочная 96 Ед/л 40 - 150"
        ])
        let ldl = try #require(report.items.first { $0.testCode == "lipid.ldl" })
        #expect(ldl.comment == ldlComment)
        #expect(ldl.reference.text == LabReportParser.commentReferenceText)
        #expect(!ldl.reference.hasNumericBounds, "референс не выбирается из нескольких уровней")
        #expect(ReferenceEvaluator.status(for: ParsedValue.parse(ldl.rawValue), reference: ldl.reference) == .noReference)
        #expect(LabCommentInterpreter.label(for: ParsedValue.parse(ldl.rawValue), comment: ldl.comment) == nil)
    }

    @Test func singleLevelStillGivesReference() {
        // Нецелевое предложение с числом и целевое без чисел не мешают единственному уровню.
        let chol = "Желательный уровень <5,0 ммоль/л. Высокий риск: уровень >6,2 ммоль/л. "
            + "Нормальные значения для детей определяет врач."
        #expect(LabCommentInterpreter.targetReference(in: chol) == ReferenceRange(upper: 5))
        #expect(label("4,2", chol) == "Желательный уровень")
        #expect(label("5,6", chol) == nil)
        // Один и тот же уровень, повторённый дважды, однозначен.
        #expect(LabCommentInterpreter.targetReference(
            in: "Желательный уровень <3,0 ммоль/л. Для взрослых желательный уровень <3,0 ммоль/л.")
            == ReferenceRange(upper: 3))
    }
}
