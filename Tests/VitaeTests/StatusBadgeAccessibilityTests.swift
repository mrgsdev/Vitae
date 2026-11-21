import Foundation
import Testing
@testable import Vitae

/// Подпись значка статуса для VoiceOver: статус звучит один раз и полностью,
/// слова лаборатории — только когда они что-то добавляют, подробности — в подсказке.
@Suite("Подпись значка статуса для VoiceOver")
@MainActor
struct StatusBadgeAccessibilityTests {
    /// Комментарий Инвитро к витамину D.
    private let invitro = "< 10 нг/мл - выраженный дефицит; 10-20 нг/мл - дефицит; 20-30 нг/мл - недостаточность; "
        + "30-100 нг/мл - адекватный уровень; > 100 нг/мл - избыток."

    private func occurrences(of part: String, in text: String) -> Int {
        text.components(separatedBy: part).count - 1
    }

    @Test(arguments: ResultStatus.allCases)
    func withoutCommentLabelIsFullStatusOnce(status: ResultStatus) {
        for compact in [false, true] {
            let badge = StatusBadge(status: status, compact: compact)
            #expect(badge.accessibilityText == status.title, "компактный значок тоже читается полностью")
            #expect(badge.accessibilityDetails.isEmpty, "без комментария подсказка не повторяет статус")
        }
    }

    @Test func labWordsComeBeforeStatusAndCommentIsMarked() {
        #expect(StatusBadge.accessibilityLabel(status: .below, labLabel: "Дефицит", hasComment: true)
                == "Дефицит, Ниже референса, есть комментарий лаборатории")
        #expect(StatusBadge.accessibilityLabel(status: .inRange, labLabel: nil, hasComment: true)
                == "В пределах референса, есть комментарий лаборатории")
    }

    @Test func labWordsEqualToStatusAreNotRepeated() {
        #expect(StatusBadge.accessibilityLabel(status: .inRange, labLabel: "в пределах референса", hasComment: false)
                == "В пределах референса")
        #expect(StatusBadge.accessibilityLabel(status: .above, labLabel: "  ", hasComment: false) == "Выше референса")
    }

    @Test func zoneFromLabCommentGoesToLabelAndDetailsWithoutStatus() {
        let badge = StatusBadge(status: .below, compact: true, comment: invitro, value: ParsedValue.parse("15"))
        #expect(badge.accessibilityText == "Дефицит, Ниже референса, есть комментарий лаборатории")
        #expect(occurrences(of: "Ниже референса", in: badge.accessibilityText) == 1)
        #expect(badge.accessibilityDetails.hasPrefix("Зона по комментарию лаборатории: 10-20 нг/мл - дефицит"))
        #expect(badge.accessibilityDetails.contains(invitro.trimmed), "текст комментария — в подсказке, не в подписи")
        #expect(!badge.accessibilityDetails.contains("Ниже референса"), "подсказка не повторяет подпись")
        #expect(!badge.accessibilityText.contains(invitro.trimmed))
    }

    @Test func snapshotInitBuildsTheSameLabel() {
        var snapshot = ResultSnapshot(date: .now, testCode: "vitd", testName: "Витамин D", rawValue: "47", unit: "нг/мл",
                                      reference: ReferenceRange(lower: 30, upper: 100))
        snapshot.note = invitro
        let badge = StatusBadge(snapshot: snapshot, compact: true)
        #expect(badge.accessibilityText == "Адекватный уровень, В пределах референса, есть комментарий лаборатории")
    }
}
