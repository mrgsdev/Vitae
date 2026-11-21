import SwiftData
import SwiftUI

/// Действия над обследованием, общие для таблицы, карточки и отдельного окна.
@MainActor
struct ExaminationActions {
    let environment: AppEnvironment

    private var context: ModelContext { environment.context }

    func profileInfo() -> PDFReportService.ProfileInfo? {
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return nil }
        return PDFReportService.ProfileInfo(name: profile.name, birthDate: profile.birthDate)
    }

    func reportData(for exam: Examination) -> Data {
        PDFReportService.examinationReport(
            title: exam.title, date: exam.date, laboratory: exam.laboratory?.name, status: exam.status,
            comment: exam.comment, results: exam.sortedResults.map(ResultSnapshot.init),
            expenses: exam.expenses.map(ExpenseSnapshot.init), profile: profileInfo()
        )
    }

    func exportPDF(_ exam: Examination) async {
        do {
            let name = FilePanels.safeFileName("\(Fmt.shortDate(exam.date)) \(exam.title).pdf")
            try await FilePanels.export(reportData(for: exam), title: "Экспорт отчёта", suggestedName: name, contentType: .pdf)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось сохранить отчёт")
        }
    }

    func print(_ exam: Examination) {
        PrintService.printPDF(reportData(for: exam), jobTitle: exam.title)
    }

    func duplicate(_ exam: Examination) -> UUID? {
        do {
            return try environment.examinationStore.duplicate(exam).id
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось дублировать обследование")
            return nil
        }
    }

    func delete(ids: Set<UUID>) {
        let store = environment.examinationStore
        let exams = ids.compactMap { store.examination(id: $0) }
        do {
            try store.delete(exams, fileStorage: environment.fileStorage)
        } catch {
            AlertPresenter.show(error: error, title: "Не удалось удалить")
        }
    }

    /// Заголовок подтверждения: число нужно лишь для выбора формы, сам счёт — в тексте.
    static func deleteTitle(count: Int) -> String {
        count == 1 ? "Удалить обследование?" : "Удалить обследования?"
    }

    /// Пункт контекстного меню; для одной строки число не пишется — понятно, что удаляется она.
    static func deleteMenuTitle(count: Int) -> String {
        count == 1 ? "Удалить…" : "Удалить \(examinationsCount(count))…"
    }

    /// Глагол согласуется с числительным: «21 обследование будет удалено»,
    /// «2 обследования / 5 обследований будут удалены».
    static func deleteMessage(count: Int) -> String {
        let what = count == 1 ? "Обследование" : examinationsCount(count)
        let verb = Fmt.plural(count, one: "будет удалено", few: "будут удалены", many: "будут удалены")
        return "\(what) \(verb) вместе с результатами, расходами и прикреплёнными документами. Это действие нельзя отменить."
    }

    private static func examinationsCount(_ count: Int) -> String {
        Fmt.count(count, one: "обследование", few: "обследования", many: "обследований")
    }
}
