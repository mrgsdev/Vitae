import Foundation
import SwiftData

// MARK: - Страховочные копии

/// Копия текущих данных перед их заменой из резервной копии. Лежит в папке автоматических копий,
/// чтобы её было видно в «Импорт и экспорт» и можно было восстановить, но ротируется отдельно:
/// иначе каждая замена вытесняла бы самую старую автоматическую копию.
extension AutoBackupService {
    static let safetySuffix = "-safety"

    static func safetyFileName(for date: Date) -> String {
        let name = (fileName(for: date) as NSString).deletingPathExtension
        return "\(name)\(safetySuffix).json"
    }

    static func isSafetyCopy(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.hasSuffix(safetySuffix)
    }

    /// Пишет страховочную копию и оставляет `keep` последних страховочных. Автоматические копии
    /// и дату последней автокопии не трогает: страховочная хранит данные, которые сейчас будут заменены.
    @discardableResult
    static func createSafetyBackup(context: ModelContext, fileStorage: FileStorageService,
                                   in directory: URL = AppDirectories.backups,
                                   keep: Int = AppSettings.autoBackupKeepCount, now: Date = .now) throws -> URL {
        let data = try BackupService(context: context, fileStorage: fileStorage).exportData(includeAttachments: true, now: now)
        let url = directory.appendingPathComponent(safetyFileName(for: now))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        for old in backupFiles(in: directory).filter(isSafetyCopy).dropFirst(max(keep, 1)) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }
}

// MARK: - Восстановление

/// Восстановление из резервной копии. В режиме «заменить» сначала сохраняет страховочную копию
/// текущих данных и без неё ничего не удаляет — интерфейс обещает, что прежние данные останутся.
@MainActor
struct BackupRestorer {
    struct Outcome {
        let report: RestoreReport
        /// Страховочная копия прежних данных; есть только при замене.
        let safetyBackup: URL?
    }

    let context: ModelContext
    let fileStorage: FileStorageService
    let backupsDirectory: URL
    let keepCount: Int

    init(context: ModelContext, fileStorage: FileStorageService,
         backupsDirectory: URL = AppDirectories.backups, keepCount: Int = AppSettings.autoBackupKeepCount) {
        self.context = context
        self.fileStorage = fileStorage
        self.backupsDirectory = backupsDirectory
        self.keepCount = keepCount
    }

    func restore(_ envelope: BackupEnvelope, mode: RestoreMode) throws -> Outcome {
        var safetyBackup: URL?
        if mode == .replace {
            do {
                safetyBackup = try AutoBackupService.createSafetyBackup(context: context, fileStorage: fileStorage,
                                                                        in: backupsDirectory, keep: keepCount)
            } catch {
                throw RestoreError.safetyBackupFailed(error.localizedDescription)
            }
        }
        let report = try BackupService(context: context, fileStorage: fileStorage).restore(envelope, mode: mode)
        return Outcome(report: report, safetyBackup: safetyBackup)
    }
}

enum RestoreError: LocalizedError, Equatable {
    case safetyBackupFailed(String)

    var errorDescription: String? {
        switch self {
        case .safetyBackupFailed(let reason):
            "Не удалось сохранить страховочную копию текущих данных, поэтому замена не выполнена — данные не изменены.\n\(reason)"
        }
    }
}
