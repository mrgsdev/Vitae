import Foundation
import SwiftData
import Testing
@testable import Vitae

/// Страховочная копия перед «Заменить все данные». Копии пишутся только во временные папки.
@MainActor
@Suite("Страховочная копия при восстановлении")
struct SafetyBackupTests {
    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafetyBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func environment(withExamination title: String) throws -> TestEnvironment {
        let env = try TestEnvironment()
        var draft = env.draft(title: title, codes: ["glucose"])
        draft.set("glucose", value: "5")
        try env.store.save(draft, finalize: true)
        return env
    }

    private func backup(withExamination title: String) throws -> BackupEnvelope {
        let source = try environment(withExamination: title)
        let data = try BackupService(context: source.context, fileStorage: source.fileStorage).exportData(includeAttachments: false)
        return try BackupService.read(data)
    }

    private func titles(_ env: TestEnvironment) throws -> [String] {
        try env.context.fetch(FetchDescriptor<Examination>()).map(\.title).sorted()
    }

    private func fileNames(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func touch(_ names: [String], in directory: URL) throws {
        for name in names { try Data("{}".utf8).write(to: directory.appendingPathComponent(name)) }
    }

    @Test func replaceIsCancelledWhenSafetyBackupCannotBeWritten() throws {
        let target = try environment(withExamination: "Текущее")
        let envelope = try backup(withExamination: "Из копии")
        let readOnly = try makeDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            try? FileManager.default.removeItem(at: readOnly)
        }

        let restorer = BackupRestorer(context: target.context, fileStorage: target.fileStorage, backupsDirectory: readOnly)
        #expect(throws: RestoreError.self) { try restorer.restore(envelope, mode: .replace) }
        #expect(try titles(target) == ["Текущее"])
        #expect(try fileNames(in: readOnly).isEmpty)
    }

    @Test func replaceSavesCurrentDataBeforeErasing() throws {
        let target = try environment(withExamination: "Текущее")
        let envelope = try backup(withExamination: "Из копии")
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcome = try BackupRestorer(context: target.context, fileStorage: target.fileStorage, backupsDirectory: dir)
            .restore(envelope, mode: .replace)

        #expect(try titles(target) == ["Из копии"])
        let safety = try #require(outcome.safetyBackup)
        #expect(AutoBackupService.isSafetyCopy(safety))
        let saved = try BackupService.read(Data(contentsOf: safety))
        #expect(saved.payload.examinations.map(\.title) == ["Текущее"])
    }

    @Test func mergeWritesNoSafetyBackup() throws {
        let target = try environment(withExamination: "Текущее")
        let envelope = try backup(withExamination: "Из копии")
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcome = try BackupRestorer(context: target.context, fileStorage: target.fileStorage, backupsDirectory: dir)
            .restore(envelope, mode: .merge)

        #expect(outcome.safetyBackup == nil)
        #expect(try fileNames(in: dir).isEmpty)
        #expect(try titles(target) == ["Из копии", "Текущее"])
    }

    @Test func safetyBackupKeepsAutomaticBackups() throws {
        let target = try environment(withExamination: "Текущее")
        let envelope = try backup(withExamination: "Из копии")
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let automatic = ["Vitae-2024-01-01_10-00-00.json", "Vitae-2024-02-01_10-00-00.json", "Vitae-2024-03-01_10-00-00.json"]
        try touch(automatic, in: dir)

        let outcome = try BackupRestorer(context: target.context, fileStorage: target.fileStorage,
                                         backupsDirectory: dir, keepCount: automatic.count)
            .restore(envelope, mode: .replace)

        let safety = try #require(outcome.safetyBackup)
        #expect(try fileNames(in: dir) == Set(automatic + [safety.lastPathComponent]))
    }

    @Test func safetyBackupsRotateSeparatelyFromAutomatic() throws {
        let env = try environment(withExamination: "Текущее")
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let automatic = ["Vitae-2024-01-01_10-00-00.json", "Vitae-2024-02-01_10-00-00.json", "Vitae-2024-03-01_10-00-00.json"]
        let oldSafety = ["Vitae-2024-01-15_10-00-00-safety.json", "Vitae-2024-02-15_10-00-00-safety.json"]
        try touch(automatic + oldSafety, in: dir)
        let now = try #require(AppLocale.calendar.date(from: DateComponents(year: 2024, month: 4, day: 1, hour: 12)))

        let created = try AutoBackupService.createSafetyBackup(context: env.context, fileStorage: env.fileStorage,
                                                               in: dir, keep: 2, now: now)
        // Из страховочных остаются две последние, автоматические не тронуты.
        #expect(AutoBackupService.isSafetyCopy(created))
        #expect(try fileNames(in: dir) == Set(automatic + [oldSafety[1], created.lastPathComponent]))

        // Ротация автоматических копий не считает и не удаляет страховочные.
        AutoBackupService.prune(keep: 2, in: dir)
        #expect(try fileNames(in: dir) == Set(automatic.suffix(2) + [oldSafety[1], created.lastPathComponent]))
    }
}
