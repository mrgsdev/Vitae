import Foundation

/// Ключи пользовательских настроек (UserDefaults). Медицинские данные здесь не хранятся.
enum SettingsKey {
    static let defaultCurrency = "settings.defaultCurrency"
    static let lockEnabled = "settings.lockEnabled"
    static let lockTimeoutMinutes = "settings.lockTimeoutMinutes"
    static let autoBackupEnabled = "settings.autoBackupEnabled"
    static let autoBackupIntervalDays = "settings.autoBackupIntervalDays"
    static let autoBackupKeepCount = "settings.autoBackupKeepCount"
    static let lastAutoBackup = "settings.lastAutoBackup"
    static let exchangeRates = "settings.exchangeRates"
    static let groupExaminationsByYear = "examinations.groupByYear"
}

enum AppSettings {
    static var defaults: UserDefaults { .standard }

    static var defaultCurrency: String {
        get { defaults.string(forKey: SettingsKey.defaultCurrency) ?? "RUB" }
        set { defaults.set(newValue, forKey: SettingsKey.defaultCurrency) }
    }

    static var lockEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.lockEnabled) }
        set { defaults.set(newValue, forKey: SettingsKey.lockEnabled) }
    }

    static var lockTimeoutMinutes: Int {
        get {
            let value = defaults.integer(forKey: SettingsKey.lockTimeoutMinutes)
            return value == 0 ? 5 : value
        }
        set { defaults.set(newValue, forKey: SettingsKey.lockTimeoutMinutes) }
    }

    static var autoBackupEnabled: Bool {
        get { defaults.object(forKey: SettingsKey.autoBackupEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingsKey.autoBackupEnabled) }
    }

    static var autoBackupIntervalDays: Int {
        get {
            let value = defaults.integer(forKey: SettingsKey.autoBackupIntervalDays)
            return value == 0 ? 7 : value
        }
        set { defaults.set(newValue, forKey: SettingsKey.autoBackupIntervalDays) }
    }

    static var autoBackupKeepCount: Int {
        get {
            let value = defaults.integer(forKey: SettingsKey.autoBackupKeepCount)
            return value == 0 ? 10 : value
        }
        set { defaults.set(newValue, forKey: SettingsKey.autoBackupKeepCount) }
    }

    static var lastAutoBackup: Date? {
        get { defaults.object(forKey: SettingsKey.lastAutoBackup) as? Date }
        set { defaults.set(newValue, forKey: SettingsKey.lastAutoBackup) }
    }

    /// Курсы задаёт пользователь вручную: 1 единица валюты = rate единиц основной валюты.
    static var exchangeRates: [String: Decimal] {
        get {
            guard let raw = defaults.dictionary(forKey: SettingsKey.exchangeRates) as? [String: String] else { return [:] }
            return raw.compactMapValues { Decimal(string: $0, locale: AppLocale.posix) }
        }
        set {
            defaults.set(newValue.mapValues { $0.plainString }, forKey: SettingsKey.exchangeRates)
        }
    }
}
