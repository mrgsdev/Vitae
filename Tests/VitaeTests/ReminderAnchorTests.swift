import Foundation
import SwiftData
import Testing
@testable import Vitae

/// Повтор напоминания по месяцам от 29–31 числа: короткий месяц обрезает дату (31.01 → 28.02),
/// но следующий повтор возвращается к исходному дню, а не остаётся на 28-м навсегда.
@Suite("Исходный день повтора напоминаний") @MainActor
struct ReminderAnchorTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        AppLocale.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func chain(_ schedule: ReminderSchedule, from start: Date, steps: Int) -> [String] {
        var due = start
        var result: [String] = []
        for _ in 0..<steps {
            guard let next = schedule.nextDate(after: due, now: due) else { break }
            result.append(Fmt.shortDate(next))
            due = next
        }
        return result
    }

    @Test func monthlyReturnsToOriginalDay() {
        let start = date(2026, 1, 31)
        let schedule = ReminderSchedule(rule: .monthly, anchoredTo: start)
        #expect(chain(schedule, from: start, steps: 4) == ["28.02.2026", "31.03.2026", "30.04.2026", "31.05.2026"])
    }

    @Test func yearlyFromLeapDayReturnsInLeapYear() {
        let start = date(2028, 2, 29)
        let schedule = ReminderSchedule(rule: .yearly, anchoredTo: start)
        #expect(chain(schedule, from: start, steps: 4) == ["28.02.2029", "28.02.2030", "28.02.2031", "29.02.2032"])
    }

    @Test func halfYearFromAugust31() {
        let start = date(2025, 8, 31)
        let schedule = ReminderSchedule(rule: .halfYear, anchoredTo: start)
        #expect(chain(schedule, from: start, steps: 2) == ["28.02.2026", "31.08.2026"])
    }

    @Test func rawFormatKeepsOldValuesForOrdinaryDays() {
        #expect(ReminderSchedule(rule: .monthly, anchoredTo: date(2026, 1, 15)).raw == "monthly", "как в прежних версиях")
        #expect(ReminderSchedule(rule: .none, anchoredTo: date(2026, 1, 31)).raw == "none")
        #expect(ReminderSchedule(rule: .monthly, anchoredTo: date(2026, 1, 31)).raw == "monthly:31")
        #expect(ReminderSchedule(raw: "monthly:31") == ReminderSchedule(rule: .monthly, anchorDay: 31))
        #expect(ReminderSchedule(raw: "halfYear") == ReminderSchedule(rule: .halfYear, anchorDay: nil))
        #expect(ReminderSchedule(raw: "monthly:15").anchorDay == nil, "день до 28 не обрезается и не хранится")
        #expect(ReminderSchedule(raw: "none:31") == ReminderSchedule(rule: .none, anchorDay: nil))
        #expect(ReminderSchedule(raw: "что-то").rule == .none)
    }

    @Test func reminderModelStoresAnchor() {
        let reminder = Reminder(title: "Ферритин", dueDate: date(2026, 1, 31), repeatRule: .monthly)
        #expect(reminder.repeatRaw == "monthly:31")
        #expect(reminder.repeatRule == .monthly)
    }

    @Test func editingKeepsAnchorWhenDateIsUnchanged() {
        let anchored = ReminderSchedule(rule: .monthly, anchorDay: 31)
        let feb28 = date(2026, 2, 28)
        // Пользователь переименовал напоминание: дата 28.02 та же — исходный день 31 сохраняется.
        #expect(ReminderSchedule.edited(anchored, oldDueDate: feb28, rule: .monthly, dueDate: feb28).anchorDay == 31)
        #expect(ReminderSchedule.edited(anchored, oldDueDate: feb28, rule: .quarterly, dueDate: feb28)
                == ReminderSchedule(rule: .quarterly, anchorDay: 31))
        // Выбрана новая дата — исходным становится её день.
        #expect(ReminderSchedule.edited(anchored, oldDueDate: feb28, rule: .monthly, dueDate: date(2026, 3, 15)).anchorDay == nil)
        #expect(ReminderSchedule.edited(nil, oldDueDate: nil, rule: .monthly, dueDate: date(2026, 3, 30)).anchorDay == 30)
    }

    @Test func backupKeepsAnchor() throws {
        let env = try TestEnvironment()
        let reminder = Reminder(title: "Витамин D", dueDate: date(2026, 1, 31), repeatRule: .monthly)
        env.context.insert(reminder)
        reminder.dueDate = try #require(reminder.schedule.nextDate(after: reminder.dueDate, now: reminder.dueDate))
        try env.context.save()

        let data = try BackupService(context: env.context, fileStorage: env.fileStorage).exportData(includeAttachments: false)
        let restoredEnv = try TestEnvironment()
        _ = try BackupService(context: restoredEnv.context, fileStorage: restoredEnv.fileStorage)
            .restore(try BackupService.read(data), mode: .replace)
        let restored = try #require(try restoredEnv.context.fetch(FetchDescriptor<Reminder>()).first)

        #expect(Fmt.shortDate(restored.dueDate) == "28.02.2026")
        #expect(restored.repeatRaw == "monthly:31")
        let next = try #require(restored.schedule.nextDate(after: restored.dueDate, now: restored.dueDate))
        #expect(Fmt.shortDate(next) == "31.03.2026")
    }
}
