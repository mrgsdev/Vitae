import Foundation

/// Категория лабораторного показателя.
enum TestCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case hematology, carbohydrate, lipids, cardio, liver, kidney, proteins
    case electrolytes, iron, vitamins, thyroid, hormones, inflammation, urine, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hematology: "Гематология"
        case .carbohydrate: "Углеводный обмен"
        case .lipids: "Липидный профиль"
        case .cardio: "Кардиометаболические маркеры"
        case .liver: "Печёночные пробы"
        case .kidney: "Почки и азотистый обмен"
        case .proteins: "Белки"
        case .electrolytes: "Электролиты и минералы"
        case .iron: "Обмен железа"
        case .vitamins: "Витамины"
        case .thyroid: "Щитовидная железа"
        case .hormones: "Гормоны"
        case .inflammation: "Маркеры воспаления"
        case .urine: "Анализ мочи"
        case .other: "Другое"
        }
    }

    var symbolName: String {
        switch self {
        case .hematology: "drop.fill"
        case .carbohydrate: "cube.fill"
        case .lipids: "chart.pie.fill"
        case .cardio: "heart.fill"
        case .liver: "cross.vial.fill"
        case .kidney: "testtube.2"
        case .proteins: "atom"
        case .electrolytes: "bolt.fill"
        case .iron: "hexagon.fill"
        case .vitamins: "sun.max.fill"
        case .thyroid: "bolt.heart.fill"
        case .hormones: "waveform.path"
        case .inflammation: "flame.fill"
        case .urine: "drop.triangle.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum ExaminationStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case draft, awaitingResults, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Черновик"
        case .awaitingResults: "Ожидает результатов"
        case .completed: "Завершено"
        }
    }

    var symbolName: String {
        switch self {
        case .draft: "pencil.circle"
        case .awaitingResults: "hourglass"
        case .completed: "checkmark.circle"
        }
    }

    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case test, panel, service, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .test: "Анализ"
        case .panel: "Комплекс"
        case .service: "Услуга"
        case .other: "Прочее"
        }
    }
}

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, monthly, quarterly, halfYear, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Не повторять"
        case .monthly: "Каждый месяц"
        case .quarterly: "Каждые 3 месяца"
        case .halfYear: "Каждые 6 месяцев"
        case .yearly: "Каждый год"
        }
    }

    var months: Int {
        switch self {
        case .none: 0
        case .monthly: 1
        case .quarterly: 3
        case .halfYear: 6
        case .yearly: 12
        }
    }

    /// Следующая дата, строго позже `now`, начиная от `date`. С `anchorDay` каждая дата ставится
    /// на исходный день месяца или на последний день короткого месяца: 31.01 → 28.02 → 31.03.
    func nextDate(after date: Date, anchorDay: Int? = nil, now: Date = .now, calendar: Calendar = AppLocale.calendar) -> Date? {
        guard months > 0 else { return nil }
        var next = date
        var guardCounter = 0
        repeat {
            guard let candidate = calendar.date(byAdding: .month, value: months, to: next) else { return nil }
            next = Self.align(candidate, toDay: anchorDay, calendar: calendar)
            guardCounter += 1
        } while next <= now && guardCounter < 1000
        return next
    }

    private static func align(_ date: Date, toDay day: Int?, calendar: Calendar) -> Date {
        guard let day, let days = calendar.range(of: .day, in: .month, for: date) else { return date }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.day = min(day, days.count)
        return calendar.date(from: components) ?? date
    }
}

/// Правило повтора напоминания вместе с исходным днём месяца. День хранится только для 29–31:
/// такие даты короткий месяц обрезает (31.01 → 28.02), и без исходного дня следующий повтор
/// навсегда остался бы на 28-м. Хранится в той же строке, что и правило («monthly:31»), чтобы не
/// менять схему базы; прежние версии Vitae прочтут такую строку как «без повтора».
struct ReminderSchedule: Equatable, Sendable {
    var rule: ReminderRepeat
    var anchorDay: Int?

    init(rule: ReminderRepeat, anchorDay: Int? = nil) {
        self.rule = rule
        self.anchorDay = rule == .none ? nil : anchorDay.flatMap { (29...31).contains($0) ? $0 : nil }
    }

    /// Правило для напоминания на `date`: исходным становится день этой даты.
    init(rule: ReminderRepeat, anchoredTo date: Date, calendar: Calendar = AppLocale.calendar) {
        self.init(rule: rule, anchorDay: calendar.component(.day, from: date))
    }

    init(raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        self.init(rule: ReminderRepeat(rawValue: parts.first ?? "") ?? .none, anchorDay: parts.count > 1 ? Int(parts[1]) : nil)
    }

    var raw: String { anchorDay.map { "\(rule.rawValue):\($0)" } ?? rule.rawValue }

    func nextDate(after date: Date, now: Date = .now, calendar: Calendar = AppLocale.calendar) -> Date? {
        rule.nextDate(after: date, anchorDay: anchorDay, now: now, calendar: calendar)
    }

    /// Правило после редактирования напоминания. Если дата не менялась, исходный день сохраняется:
    /// иначе переименование напоминания, перенесённого на 28.02, потеряло бы день 31.
    static func edited(_ existing: ReminderSchedule?, oldDueDate: Date?, rule: ReminderRepeat, dueDate: Date,
                       calendar: Calendar = AppLocale.calendar) -> ReminderSchedule {
        if let existing, let oldDueDate, oldDueDate == dueDate, existing.anchorDay != nil {
            return ReminderSchedule(rule: rule, anchorDay: existing.anchorDay)
        }
        return ReminderSchedule(rule: rule, anchoredTo: dueDate, calendar: calendar)
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case unspecified, female, male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: "Не указан"
        case .female: "Женский"
        case .male: "Мужской"
        }
    }
}

/// Поддерживаемые валюты. Суммы в разных валютах не складываются без курса.
enum CurrencyCatalog {
    static let codes: [String] = ["RUB", "USD", "EUR", "KZT", "BYN", "UAH", "GEL", "AMD", "UZS", "TRY", "GBP", "CNY", "AED", "ILS", "RSD"]

    static func order(_ code: String) -> Int {
        codes.firstIndex(of: code) ?? codes.count
    }

    static func symbol(_ code: String) -> String {
        switch code {
        case "RUB": "₽"
        case "USD": "$"
        case "EUR": "€"
        case "KZT": "₸"
        case "UAH": "₴"
        case "GEL": "₾"
        case "TRY": "₺"
        case "GBP": "£"
        case "CNY": "¥"
        case "ILS": "₪"
        default: code
        }
    }

    static func title(_ code: String) -> String {
        let name = AppLocale.locale.localizedString(forCurrencyCode: code) ?? code
        return "\(code) — \(name)"
    }
}
