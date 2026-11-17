import OSLog

/// Технический журнал. Правило: значения анализов, названия показателей,
/// имена файлов пользователя и другие медицинские данные в журнал НЕ пишутся.
enum AppLog {
    static let persistence = Logger(subsystem: "Vitae", category: "persistence")
    static let files = Logger(subsystem: "Vitae", category: "files")
    static let backup = Logger(subsystem: "Vitae", category: "backup")
    static let ocr = Logger(subsystem: "Vitae", category: "ocr")
    static let notifications = Logger(subsystem: "Vitae", category: "notifications")
    static let security = Logger(subsystem: "Vitae", category: "security")
}
