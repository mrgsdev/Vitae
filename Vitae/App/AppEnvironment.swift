import AppKit
import SwiftData
import SwiftUI
import UserNotifications

/// Общие зависимости приложения: контейнер SwiftData, файловое хранилище, сервисы.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let container: ModelContainer
    let fileStorage: FileStorageService
    let lock = AppLockManager()
    let notifications = NotificationService()
    let ocr = OCRService()
    /// Ошибка открытия хранилища (данные на диске не изменяются).
    var startupError: String?
    /// Сообщение о переносе данных из прежней версии (с песочницей).
    var migrationNotice: String?
    /// Действие, ожидающее открытия главного окна (например, импорт из меню без открытых окон).
    var pendingRoute: PendingRoute?

    var context: ModelContext { container.mainContext }

    private init() {
        let mode = RunMode.current
        var openError: String?
        var notice: String?
        if mode == .normal {
            switch LegacyDataMigration.migrateIfNeeded() {
            case .migrated:
                notice = "Данные перенесены в новую папку приложения. Прежняя копия осталась на месте: \(LegacyDataMigration.legacyRoot.path)"
            case .failed(let reason):
                notice = "Не удалось перенести данные из прежней версии: \(reason). Исходные файлы не изменены: \(LegacyDataMigration.legacyRoot.path)"
            case .notNeeded:
                break
            }
            LegacyDataMigration.migratePreferencesIfNeeded()
        }
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: mode.usesInMemoryStore)
        } catch {
            AppLog.persistence.error("Хранилище не открыто, используется временная память")
            openError = "Не удалось открыть базу данных. Приложение работает во временном режиме — изменения не сохранятся. " +
                "Файл базы не изменён; восстановите данные из резервной копии или обратитесь к разработчику."
            container = try! PersistenceController.makeContainer(inMemory: true)
        }
        self.container = container
        self.startupError = openError
        self.migrationNotice = notice

        let attachmentsURL = mode == .normal
            ? AppDirectories.attachments
            : FileManager.default.temporaryDirectory.appendingPathComponent("Vitae-\(UUID().uuidString)/Attachments", isDirectory: true)
        fileStorage = FileStorageService(baseURL: attachmentsURL)

        do {
            try CatalogSeeder.seedIfNeeded(context: container.mainContext)
        } catch {
            AppLog.persistence.error("Не удалось заполнить справочник")
        }
        #if DEBUG
        UITestFixture.loadIfRequested(into: container.mainContext)
        #endif
    }

    var examinationStore: ExaminationStore { ExaminationStore(context: context) }
}

enum PendingRoute: Equatable {
    case importDocument(DocumentImportRequest)
    case examination(UUID)
    case section(SidebarItem)
    case importExportAction(ImportExportAction)
}

/// Действия раздела «Импорт и экспорт», запускаемые из меню.
enum ImportExportAction: Equatable {
    case restoreBackup
    case importCSV
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        if RunMode.current == .normal {
            UNUserNotificationCenter.current().delegate = self
        }
        environment.lock.lockOnLaunchIfNeeded()
        #if DEBUG
        // Отладка обновления без интерфейса: не зависит от того, открылось ли окно.
        Task { @MainActor in await Updater.shared.runDebugAutomation() }
        #endif
        Task { @MainActor in
            AutoBackupService.runIfNeeded(context: environment.context, fileStorage: environment.fileStorage)
            let reminders = (try? environment.context.fetch(FetchDescriptor<Reminder>())) ?? []
            await environment.notifications.reschedule(reminders.filter { !$0.isCompleted })
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        AppEnvironment.shared.lock.applicationDidResignActive()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppEnvironment.shared.lock.applicationDidBecomeActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
