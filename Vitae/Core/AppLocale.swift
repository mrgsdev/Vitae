import Foundation

/// Приложение полностью русскоязычное, поэтому форматирование дат, чисел и денег
/// выполняется в единой локали, независимо от региональных настроек системы.
enum AppLocale {
    static let locale = Locale(identifier: "ru_RU")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }()

    static let posix = Locale(identifier: "en_US_POSIX")
}

/// Идентификаторы окон приложения.
enum WindowID {
    static let main = "main"
    static let examination = "examination"
    static let editor = "editor"
}

/// Режим запуска: обычный, unit-тесты или UI-тесты.
enum RunMode: Equatable {
    case normal
    case unitTesting
    case uiTesting

    static let current: RunMode = {
        let info = ProcessInfo.processInfo
        if info.arguments.contains("-uiTesting") { return .uiTesting }
        if info.environment["XCTestConfigurationFilePath"] != nil || info.environment["XCTestBundlePath"] != nil {
            return .unitTesting
        }
        if NSClassFromString("XCTestCase") != nil { return .unitTesting }
        return .normal
    }()

    var usesInMemoryStore: Bool { self != .normal }
}
