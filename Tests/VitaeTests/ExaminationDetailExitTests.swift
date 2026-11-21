import Foundation
import Testing
@testable import Vitae

/// Сценарий из QA: «Действия → Удалить…» в отдельном окне обследования удаляло запись,
/// но окно оставалось открытым с «Обследование не найдено».
@MainActor
@Suite("Уход с карточки удаляемого обследования")
struct ExaminationDetailExitTests {
    @Test func separateWindowIsClosed() {
        var closed = 0

        ExaminationDetailExit.leave(navigation: nil) { closed += 1 }

        #expect(closed == 1)
    }

    @Test func mainWindowReturnsToSectionRootAndStaysOpen() {
        let navigation = NavigationModel()
        let examID = UUID()
        navigation.selection = .examinations
        navigation.paths[.examinations] = [.examination(examID)]
        navigation.paths[.dynamics] = [.indicator("ferritin")]
        var closed = 0

        ExaminationDetailExit.leave(navigation: navigation) { closed += 1 }

        #expect(closed == 0)
        #expect(navigation.selection == .examinations)
        #expect(navigation.paths[.examinations] == [])
        #expect(navigation.paths[.dynamics] == [.indicator("ferritin")])
    }

    /// Без выбранного раздела рабочая область показывает «Главную», и карточка лежит в её стеке.
    @Test func noSelectionResetsDashboardStack() {
        let navigation = NavigationModel()
        let examID = UUID()
        navigation.selection = nil
        navigation.paths[.dashboard] = [.examination(examID)]
        navigation.paths[.examinations] = [.examination(examID)]

        ExaminationDetailExit.leave(navigation: navigation) {}

        #expect(navigation.paths[.dashboard] == [])
        #expect(navigation.paths[.examinations] == [.examination(examID)])
    }
}
