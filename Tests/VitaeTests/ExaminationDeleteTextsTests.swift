import Testing
@testable import Vitae

/// Тексты удаления обследований: число, падеж и глагол согласованы с количеством
/// («2 обследования будут удалены», «21 обследование будет удалено»).
@MainActor
@Suite("Тексты удаления обследований")
struct ExaminationDeleteTextsTests {
    private let tail = " вместе с результатами, расходами и прикреплёнными документами. Это действие нельзя отменить."

    @Test func singleExaminationMessageHasNoNumber() {
        #expect(ExaminationActions.deleteMessage(count: 1) == "Обследование будет удалено" + tail)
    }

    @Test(arguments: [
        (2, "2 обследования будут удалены"),
        (4, "4 обследования будут удалены"),
        (5, "5 обследований будут удалены"),
        (11, "11 обследований будут удалены"),
        (12, "12 обследований будут удалены"),
        (14, "14 обследований будут удалены"),
        (21, "21 обследование будет удалено"),
        (22, "22 обследования будут удалены"),
        (25, "25 обследований будут удалены"),
        (111, "111 обследований будут удалены"),
    ])
    func messageAgreesWithCount(count: Int, head: String) {
        #expect(ExaminationActions.deleteMessage(count: count) == head + tail)
    }

    @Test func titleIsSingularForOneExamination() {
        #expect(ExaminationActions.deleteTitle(count: 1) == "Удалить обследование?")
        #expect(ExaminationActions.deleteTitle(count: 2) == "Удалить обследования?")
        #expect(ExaminationActions.deleteTitle(count: 21) == "Удалить обследования?")
    }

    @Test(arguments: [
        (1, "Удалить…"),
        (2, "Удалить 2 обследования…"),
        (3, "Удалить 3 обследования…"),
        (5, "Удалить 5 обследований…"),
        (11, "Удалить 11 обследований…"),
        (13, "Удалить 13 обследований…"),
        (21, "Удалить 21 обследование…"),
        (22, "Удалить 22 обследования…"),
    ])
    func contextMenuTitleAgreesWithCount(count: Int, title: String) {
        #expect(ExaminationActions.deleteMenuTitle(count: count) == title)
    }
}
