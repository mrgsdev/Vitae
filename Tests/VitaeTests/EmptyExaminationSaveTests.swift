import Foundation
import SwiftData
import Testing
@testable import Vitae

/// «Сохранить» и ⌘↩ в пустом редакторе не должны создавать обследование без строк.
@MainActor
@Suite("Сохранение пустого обследования")
struct EmptyExaminationSaveTests {
    private func examinationCount(_ env: TestEnvironment) throws -> Int {
        try env.context.fetchCount(FetchDescriptor<Examination>())
    }

    @Test("Без строк завершить обследование нельзя — с понятным сообщением")
    func emptyEditorCannotSave() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)

        #expect(!model.canSave)
        #expect(!model.save())
        #expect(!model.didFinish)
        #expect(model.draft.examinationID == nil)
        #expect(model.errorMessage == ExaminationEditorModel.emptySaveMessage)
        #expect(try examinationCount(env) == 0)
    }

    @Test("Название и комментарий без строк не делают обследование сохраняемым")
    func headerOnlyCannotSave() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)
        model.draft.title = "Чек-ап"
        model.draft.comment = "Натощак"

        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try examinationCount(env) == 0)
    }

    @Test("Черновик пустого редактора сохраняется по-прежнему")
    func emptyDraftStillSaves() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)
        model.draft.title = "Чек-ап"

        #expect(model.saveDraft())
        let id = try #require(model.draft.examinationID)
        #expect(env.store.examination(id: id)?.status == .draft)
    }

    @Test("Одной услуги достаточно для сохранения")
    func serviceRowIsEnough() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)
        model.addService()

        #expect(model.canSave)
        #expect(model.save())
        #expect(model.didFinish)
        #expect(try examinationCount(env) == 1)
    }

    @Test("Строка показателя из каталога разрешает сохранение")
    func catalogRowAllowsSave() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)
        model.add(env.entry("ferritin"))

        #expect(model.canSave)
        #expect(model.save())
        let id = try #require(model.draft.examinationID)
        #expect(env.store.examination(id: id)?.status == .awaitingResults)
    }

    @Test("Если удалить все строки сохранённого обследования, «Сохранить» его не опустошает")
    func editingToEmptyKeepsExamination() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "50")
        let exam = try env.store.save(draft, finalize: true)

        let model = ExaminationEditorModel(request: .edit(exam.id), context: env.context)
        model.removeRows(Set(model.draft.rows.map(\.id)))

        #expect(!model.canSave)
        #expect(!model.save())
        #expect(model.errorMessage == ExaminationEditorModel.emptySaveMessage)
        #expect(exam.results.count == 1)
        #expect(exam.status == .completed)
    }
}
