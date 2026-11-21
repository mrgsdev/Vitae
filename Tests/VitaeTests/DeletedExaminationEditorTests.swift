import Foundation
import SwiftData
import Testing
@testable import Vitae

/// Обследование удалили, пока оно было открыто в редакторе: сохранение не должно молча создавать его заново.
@MainActor
@Suite("Удалённое обследование в редакторе")
struct DeletedExaminationEditorTests {
    private func examinationCount(_ env: TestEnvironment) throws -> Int {
        try env.context.fetchCount(FetchDescriptor<Examination>())
    }

    /// Сохранённое обследование, открытое в редакторе с несохранёнными правками, и затем удалённое.
    private func editorForDeletedExamination(_ env: TestEnvironment) throws -> (ExaminationEditorModel, UUID) {
        var draft = env.draft(title: "Чек-ап", codes: ["ferritin"])
        draft.set("ferritin", value: "40")
        let exam = try env.store.save(draft, finalize: true)
        let id = exam.id

        let model = ExaminationEditorModel(request: .edit(id), context: env.context)
        model.draft.comment = "натощак"
        #expect(model.isDirty)

        try env.store.delete([exam], fileStorage: env.fileStorage)
        #expect(try examinationCount(env) == 0)
        return (model, id)
    }

    @Test func storeRefusesToSaveDraftOfDeletedExamination() throws {
        let env = try TestEnvironment()
        var draft = env.draft(codes: ["ferritin"])
        draft.set("ferritin", value: "40")
        let exam = try env.store.save(draft, finalize: true)
        let loaded = env.store.draft(from: exam)
        try env.store.delete([exam], fileStorage: env.fileStorage)

        #expect(throws: StoreError.self) { try env.store.save(loaded, finalize: true) }
        #expect(try examinationCount(env) == 0)
    }

    @Test func saveDoesNotResurrectDeletedExamination() throws {
        let env = try TestEnvironment()
        let (model, id) = try editorForDeletedExamination(env)

        #expect(model.save() == false)
        #expect(model.didFinish == false, "окно не закрывается, пока пользователь не выбрал действие")
        #expect(model.deletedExaminationSave == .init(finalize: true, closesWindow: true))
        #expect(model.errorMessage == nil, "вместо общей ошибки — выбор «Сохранить как новое» / «Закрыть»")
        #expect(env.store.examination(id: id) == nil)
        #expect(try examinationCount(env) == 0)
    }

    @Test func saveDraftDoesNotResurrectDeletedExamination() throws {
        let env = try TestEnvironment()
        let (model, id) = try editorForDeletedExamination(env)

        #expect(model.saveDraft() == false)
        #expect(model.deletedExaminationSave == .init(finalize: true, closesWindow: false),
                "завершённое обследование и по ⌘S сохраняется со своим статусом")
        #expect(env.store.examination(id: id) == nil)
        #expect(try examinationCount(env) == 0)
    }

    @Test func autosaveOnCloseDoesNotResurrectDeletedExamination() throws {
        let env = try TestEnvironment()
        let (model, id) = try editorForDeletedExamination(env)

        model.autosaveIfNeeded()
        #expect(env.store.examination(id: id) == nil)
        #expect(try examinationCount(env) == 0)
    }

    @Test func saveAsNewCreatesSeparateExaminationAndClosesWindow() throws {
        let env = try TestEnvironment()
        let (model, id) = try editorForDeletedExamination(env)
        model.save()

        #expect(model.saveDeletedAsNew())
        #expect(model.didFinish)
        #expect(model.deletedExaminationSave == nil)
        let newID = try #require(model.draft.examinationID)
        #expect(newID != id, "это новая запись, а не восстановленная удалённая")
        #expect(env.store.examination(id: id) == nil)
        let exam = try #require(env.store.examination(id: newID))
        #expect(exam.title == "Чек-ап")
        #expect(exam.comment == "натощак")
        #expect(exam.status == .completed)
        #expect(exam.results.map(\.testCode) == ["ferritin"])
        #expect(try examinationCount(env) == 1)
    }

    @Test func saveAsNewAfterSaveDraftKeepsEditingNewExamination() throws {
        let env = try TestEnvironment()
        let (model, _) = try editorForDeletedExamination(env)
        model.saveDraft()

        #expect(model.saveDeletedAsNew())
        #expect(model.didFinish == false, "⌘S окно не закрывает")
        let newID = try #require(model.draft.examinationID)

        // Дальше редактор работает с новой записью и не плодит копии.
        model.draft.comment = "повторный ⌘S"
        #expect(model.saveDraft())
        #expect(model.draft.examinationID == newID)
        #expect(env.store.examination(id: newID)?.comment == "повторный ⌘S")
        #expect(try examinationCount(env) == 1)
    }

    @Test func closeAfterDeletionDiscardsChanges() throws {
        let env = try TestEnvironment()
        let (model, _) = try editorForDeletedExamination(env)
        model.save()

        model.discard()
        #expect(model.didFinish)
        #expect(model.deletedExaminationSave == nil)
        model.autosaveIfNeeded()
        #expect(try examinationCount(env) == 0)
    }

    @Test func autosaveDoesNotResurrectDraftDeletedAfterFirstSave() throws {
        let env = try TestEnvironment()
        let model = ExaminationEditorModel(request: .new(), context: env.context)
        model.add(env.entry("ferritin"))
        #expect(model.saveDraft())
        let id = try #require(model.draft.examinationID)
        model.draft.comment = "после первого ⌘S"

        let exam = try #require(env.store.examination(id: id))
        try env.store.delete([exam], fileStorage: env.fileStorage)

        model.autosaveIfNeeded()
        #expect(try examinationCount(env) == 0)
    }
}
