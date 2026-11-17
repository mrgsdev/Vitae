import Foundation

/// Перенос данных из контейнера песочницы. Версии до появления автообновления работали в App Sandbox
/// и хранили базу в `~/Library/Containers/<bundle id>/…`. Без песочницы приложение читает
/// `~/Library/Application Support/Vitae`, поэтому при первом запуске данные копируются туда.
/// Исходные файлы не удаляются и не изменяются.
enum LegacyDataMigration {
    enum Outcome: Equatable {
        case notNeeded
        case migrated(files: Int)
        case failed(String)
    }

    static let preferencesMarker = "settings.legacyPreferencesMigrated"

    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.mrgsdev.Vitae" }

    static var legacyContainer: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library", isDirectory: true)
    }

    static var legacyRoot: URL {
        legacyContainer.appendingPathComponent("Application Support/Vitae", isDirectory: true)
    }

    static var legacyPreferences: URL {
        legacyContainer.appendingPathComponent("Preferences/\(bundleIdentifier).plist")
    }

    /// Копирует базу, документы и резервные копии, если в новом месте базы ещё нет.
    static func migrateIfNeeded(from legacy: URL = legacyRoot, to root: URL = AppDirectories.root,
                                storeName: String = "Vitae.store",
                                fileManager: FileManager = .default) -> Outcome {
        // Внутри песочницы «новое» место и есть контейнер — переносить нечего.
        guard !root.path.contains("/Library/Containers/") else { return .notNeeded }
        let legacyStore = legacy.appendingPathComponent(storeName)
        let newStore = root.appendingPathComponent(storeName)
        guard fileManager.fileExists(atPath: legacyStore.path), !fileManager.fileExists(atPath: newStore.path) else {
            return .notNeeded
        }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var copied = 0
            for item in try fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
                let target = root.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) {
                    // Пустые служебные папки, созданные при запуске, заменяем данными из контейнера.
                    let contents = (try? fileManager.contentsOfDirectory(atPath: target.path)) ?? []
                    guard contents.isEmpty else { continue }
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: item, to: target)
                copied += 1
            }
            AppLog.persistence.info("Данные перенесены из контейнера песочницы")
            return .migrated(files: copied)
        } catch {
            // Наполовину скопированная база опаснее отсутствующей: убираем её, оригинал остаётся.
            try? fileManager.removeItem(at: newStore)
            AppLog.persistence.error("Перенос данных из контейнера не выполнен")
            return .failed(error.localizedDescription)
        }
    }

    /// Переносит пользовательские настройки (валюта, блокировка, резервные копии, курсы) один раз.
    static func migratePreferencesIfNeeded(from plist: URL = legacyPreferences, defaults: PreferenceStore = UserDefaults.standard) {
        guard !defaults.bool(forKey: preferencesMarker),
              let legacy = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
        for (key, value) in legacy where key.hasPrefix("settings.") || key.hasPrefix("examinations.") {
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: preferencesMarker)
    }
}

/// Минимальный интерфейс настроек: UserDefaults в приложении, словарь в тестах.
protocol PreferenceStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func bool(forKey defaultName: String) -> Bool
}

extension UserDefaults: PreferenceStore {}
