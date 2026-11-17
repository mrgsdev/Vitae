import Foundation
import SwiftData

/// Версия 1 схемы данных. Новые версии добавляются как отдельные `VersionedSchema`
/// с этапами в `VitaeMigrationPlan`.
enum VitaeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, Laboratory.self, LabTest.self, Examination.self,
         TestResult.self, Expense.self, Attachment.self, Reminder.self]
    }
}

enum VitaeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VitaeSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum VitaeSchema {
    static let current = VitaeSchemaV1.self
    static var versionString: String {
        let v = current.versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }
}

/// Каталоги приложения в Application Support (внутри контейнера песочницы).
enum AppDirectories {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return ensure(base.appendingPathComponent("Vitae", isDirectory: true))
    }

    static var attachments: URL { ensure(root.appendingPathComponent("Attachments", isDirectory: true)) }
    static var backups: URL { ensure(root.appendingPathComponent("Backups", isDirectory: true)) }
    static var storeURL: URL { root.appendingPathComponent("Vitae.store") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        return url
    }
}

enum PersistenceController {
    static func makeContainer(inMemory: Bool, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VitaeSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("Vitae", schema: schema, isStoredInMemoryOnly: true,
                                               allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("Vitae", schema: schema, url: url ?? AppDirectories.storeURL,
                                               allowsSave: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: VitaeMigrationPlan.self, configurations: [configuration])
    }
}
