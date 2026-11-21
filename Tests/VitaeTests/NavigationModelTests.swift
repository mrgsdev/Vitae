import Foundation
import Testing
@testable import Vitae

/// `SectionContainerView` пересоздаёт `NavigationStack` при смене раздела, и уходящий стек
/// записывает `[]` в привязку своего пути уже после того, как выбран новый раздел.
/// Такая запись не должна стирать открытую страницу раздела.
@MainActor
@Suite("Навигация между разделами")
struct NavigationModelTests {
    @Test func switchingSectionsKeepsOpenPage() {
        let navigation = NavigationModel()
        let examID = UUID()
        navigation.selection = .examinations
        let examinationsPath = navigation.path(for: .examinations)
        examinationsPath.wrappedValue = [.examination(examID)]

        navigation.show(.dashboard)
        examinationsPath.wrappedValue = []

        #expect(navigation.paths[.examinations] == [.examination(examID)])
        navigation.show(.examinations)
        #expect(navigation.path(for: .examinations).wrappedValue == [.examination(examID)])
    }

    @Test func routeFromNestedPageKeepsBothPaths() {
        let navigation = NavigationModel()
        let examID = UUID()
        navigation.selection = .examinations
        navigation.paths[.examinations] = [.examination(examID)]
        let examinationsPath = navigation.path(for: .examinations)

        navigation.openDynamics(code: "ferritin")
        examinationsPath.wrappedValue = []

        #expect(navigation.selection == .dynamics)
        #expect(navigation.paths[.dynamics] == [.indicator("ferritin")])
        #expect(navigation.paths[.examinations] == [.examination(examID)])
    }

    @Test func currentSectionStackStillPushesAndPops() {
        let navigation = NavigationModel()
        navigation.selection = .dynamics
        let dynamicsPath = navigation.path(for: .dynamics)

        dynamicsPath.wrappedValue = [.indicator("cbc.hgb")]
        #expect(navigation.paths[.dynamics] == [.indicator("cbc.hgb")])

        dynamicsPath.wrappedValue = []
        #expect(navigation.paths[.dynamics] == [])
    }

    @Test func noSelectionMeansDashboardStack() {
        let navigation = NavigationModel()
        let examID = UUID()
        navigation.selection = nil

        navigation.path(for: .dashboard).wrappedValue = [.examination(examID)]

        #expect(navigation.paths[.dashboard] == [.examination(examID)])
    }
}
