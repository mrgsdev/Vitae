import AppKit
import Foundation
import LocalAuthentication
import PDFKit
import QuickLookThumbnailing
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Панели открытия и сохранения

/// Нативные NSOpenPanel/NSSavePanel. Открываются как sheet активного окна.
@MainActor
enum FilePanels {
    static func save(title: String, suggestedName: String, contentType: UTType) async -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func open(title: String, contentTypes: [UTType], allowsMultiple: Bool = false) async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await panel.beginSheetModal(for: window) == .OK ? panel.urls : []
        }
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Сохранение данных в выбранный пользователем файл.
    @discardableResult
    static func export(_ data: Data, title: String, suggestedName: String, contentType: UTType) async throws -> URL? {
        guard let url = await save(title: title, suggestedName: suggestedName, contentType: contentType) else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalid).joined(separator: "-").trimmed
    }
}

// MARK: - Печать

@MainActor
enum PrintService {
    static func printPDF(_ data: Data, jobTitle: String) {
        guard let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .spool
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}

// MARK: - Миниатюры Quick Look

enum ThumbnailService {
    static func thumbnail(for url: URL, size: CGSize, scale: CGFloat = 2) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - Уведомления

/// Локальные уведомления о напоминаниях. В текст уведомлений не попадают результаты анализов.
@MainActor
final class NotificationService {
    private var center: UNUserNotificationCenter? {
        RunMode.current == .normal ? UNUserNotificationCenter.current() : nil
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard let center else { return .notDetermined }
        return await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("Запрос разрешения на уведомления не выполнен")
            return false
        }
    }

    func schedule(id: UUID, title: String, date: Date, enabled: Bool) async {
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        guard enabled, date > .now else { return }
        let status = await authorizationStatus()
        if status == .notDetermined { await requestAuthorization() }

        let content = UNMutableNotificationContent()
        content.title = "Напоминание Vitae"
        content.body = title
        content.sound = .default
        let components = AppLocale.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        do {
            try await center.add(request)
        } catch {
            AppLog.notifications.error("Не удалось запланировать уведомление")
        }
    }

    func cancel(id: UUID) {
        center?.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func reschedule(_ reminders: [Reminder]) async {
        for reminder in reminders {
            await schedule(id: reminder.id, title: reminder.title, date: reminder.dueDate,
                           enabled: reminder.notificationsEnabled && !reminder.isCompleted)
        }
    }
}

// MARK: - Блокировка приложения

/// Блокировка содержимого окон с разблокировкой через Touch ID или пароль учётной записи macOS.
@MainActor
@Observable
final class AppLockManager {
    private(set) var isLocked = false
    var lastError: String?
    private var resignedAt: Date?

    var isEnabled: Bool { AppSettings.lockEnabled && RunMode.current == .normal }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockOnLaunchIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func lockNow() {
        guard isEnabled else { return }
        isLocked = true
    }

    func applicationDidResignActive() {
        resignedAt = .now
    }

    func applicationDidBecomeActive() {
        guard isEnabled, !isLocked, let resignedAt else { return }
        if Date.now.timeIntervalSince(resignedAt) >= Double(AppSettings.lockTimeoutMinutes * 60) {
            isLocked = true
        }
        self.resignedAt = nil
    }

    func unlock() async {
        let context = LAContext()
        context.localizedCancelTitle = "Отмена"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Без средств аутентификации блокировка невозможна — не запираем пользователя.
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: "разблокировать медицинские данные в Vitae")
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = "Разблокировка не выполнена"
            AppLog.security.info("Разблокировка отменена или не удалась")
        }
    }
}

// MARK: - Автоматическое резервное копирование

@MainActor
enum AutoBackupService {
    static func backupFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: AppDirectories.backups, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.posix
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Vitae-\(formatter.string(from: date)).json"
    }

    @discardableResult
    static func createBackup(context: ModelContext, fileStorage: FileStorageService, includeAttachments: Bool = true) throws -> URL {
        let data = try BackupService(context: context, fileStorage: fileStorage).exportData(includeAttachments: includeAttachments)
        let url = AppDirectories.backups.appendingPathComponent(fileName(for: .now))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        AppSettings.lastAutoBackup = .now
        prune(keep: AppSettings.autoBackupKeepCount)
        return url
    }

    static func runIfNeeded(context: ModelContext, fileStorage: FileStorageService) {
        guard RunMode.current == .normal, AppSettings.autoBackupEnabled else { return }
        let hasData = ((try? context.fetchCount(FetchDescriptor<Examination>())) ?? 0) > 0
        guard hasData else { return }
        if let last = AppSettings.lastAutoBackup,
           Date.now.timeIntervalSince(last) < Double(AppSettings.autoBackupIntervalDays) * 86_400 { return }
        do {
            try createBackup(context: context, fileStorage: fileStorage)
            AppLog.backup.info("Автоматическая резервная копия создана")
        } catch {
            AppLog.backup.error("Автоматическая резервная копия не создана")
        }
    }

    static func prune(keep: Int) {
        for url in backupFiles().dropFirst(max(keep, 1)) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
