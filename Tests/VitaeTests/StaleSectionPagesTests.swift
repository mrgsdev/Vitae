import Foundation
import Testing
@testable import Vitae

/// Страницы разделов сохраняются при переключении разделов. Из-за этого нельзя оставлять в путях
/// страницы удалённых обследований, а экран импорта не должен распознавать файл заново при возврате.
@Suite("Устаревшие страницы разделов") @MainActor
struct StaleSectionPagesTests {
    private final class Session {}

    @Test func deletedExaminationPagesAreRemovedFromAllSections() {
        let navigation = NavigationModel()
        let kept = UUID(), deleted = UUID()
        let importIntoDeleted = DocumentImportRequest(url: nil, targetExaminationID: deleted)
        navigation.paths[.dashboard] = [.examination(deleted)]
        navigation.paths[.dynamics] = [.indicator("ferritin"), .examination(deleted)]
        navigation.paths[.comparison] = [.examination(kept)]
        navigation.paths[.importExport] = [.documentImport(importIntoDeleted)]
        navigation.comparison.examinationA = deleted
        navigation.comparison.examinationB = kept
        navigation.examinations.selection = [kept, deleted]

        navigation.removeRoutes(keepingExaminations: [kept])

        #expect(navigation.paths[.dashboard] == [])
        #expect(navigation.paths[.dynamics] == [.indicator("ferritin")], "страница под удалённой остаётся")
        #expect(navigation.paths[.comparison] == [.examination(kept)])
        #expect(navigation.paths[.importExport] == [], "импорт в удалённое обследование закрывается")
        #expect(navigation.comparison.examinationA == nil)
        #expect(navigation.comparison.examinationB == kept)
        #expect(navigation.examinations.selection == [kept])
    }

    @Test func importOfNewExaminationSurvivesDeletions() {
        let navigation = NavigationModel()
        let request = DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/blank.pdf"))
        navigation.paths[.importExport] = [.documentImport(request)]

        navigation.removeRoutes(keepingExaminations: [])

        #expect(navigation.paths[.importExport] == [.documentImport(request)],
                "удаление обследований не закрывает импорт нового документа")
    }

    @Test func importSessionIsReusedWhileItsPageIsOpen() {
        let navigation = NavigationModel()
        let request = DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/blank.pdf"))
        navigation.paths[.importExport] = [.documentImport(request)]

        let first = navigation.importSession(for: request) { Session() }
        // Пользователь ушёл в другой раздел и вернулся: экран пересоздан, модель — та же.
        navigation.selection = .examinations
        navigation.selection = .importExport
        let second = navigation.importSession(for: request) { Session() }

        #expect(first.isNew)
        #expect(!second.isNew, "файл не распознаётся заново")
        #expect(first.model === second.model, "правки проверки и состояние «сохранено» сохраняются")
    }

    @Test func importSessionIsDroppedWhenItsPageIsClosed() {
        let navigation = NavigationModel()
        let request = DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/blank.pdf"))
        navigation.selection = .importExport
        navigation.paths[.importExport] = [.documentImport(request)]
        let first = navigation.importSession(for: request) { Session() }

        // «Назад» из импорта: стек выбранного раздела пишет пустой путь.
        navigation.path(for: .importExport).wrappedValue = []
        navigation.paths[.importExport] = [.documentImport(request)]
        let reopened = navigation.importSession(for: request) { Session() }

        #expect(reopened.isNew)
        #expect(first.model !== reopened.model)
    }

    @Test func newImportRequestStartsFreshSession() {
        let navigation = NavigationModel()
        navigation.importDocument(URL(fileURLWithPath: "/tmp/a.pdf"))
        guard case .documentImport(let first)? = navigation.paths[.importExport]?.first else {
            Issue.record("нет страницы импорта"); return
        }
        let firstSession = navigation.importSession(for: first) { Session() }

        navigation.importDocument(URL(fileURLWithPath: "/tmp/b.pdf"))
        guard case .documentImport(let second)? = navigation.paths[.importExport]?.first else {
            Issue.record("нет страницы импорта"); return
        }
        let secondSession = navigation.importSession(for: second) { Session() }

        #expect(secondSession.isNew)
        #expect(firstSession.model !== secondSession.model)
    }
}
