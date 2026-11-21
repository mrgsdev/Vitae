import Foundation
import Testing
@testable import Vitae

/// Unit-тесты и запуск с `-uiTesting` не должны касаться настоящих данных, копий и настроек:
/// каталоги — временные, настройки — в отдельном наборе.
///
/// Каждая проверка сначала убеждается, что папка временная, и только потом создаёт или удаляет файлы:
/// без изоляции тест падает, ничего не записав в настоящую папку.
@MainActor
@Suite("Изоляция тестового режима", .serialized)
struct TestModeIsolationTests {
    /// Настоящая папка данных. Путь только вычисляется — содержимое не читается.
    private static let realRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vitae", isDirectory: true)

    private static let temporary = FileManager.default.temporaryDirectory

    private static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = directory.standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    private static func isIsolated(_ url: URL) -> Bool {
        isInside(url, temporary) && !isInside(url, realRoot)
    }

    @Test func runsInUnitTestingMode() {
        #expect(RunMode.current == .unitTesting)
    }

    @Test func directoriesAreTemporary() throws {
        // Без изоляции дальше не идём: обращение к `backups` и `attachments` создало бы их в настоящей папке.
        try #require(Self.isIsolated(AppDirectories.root), "данные в настоящей папке: \(AppDirectories.root.path)")
        for url in [AppDirectories.root, AppDirectories.backups, AppDirectories.attachments, AppDirectories.storeURL] {
            #expect(!Self.isInside(url, Self.realRoot), "\(url.path) — настоящая папка Vitae")
            #expect(Self.isInside(url, Self.temporary), "\(url.path) — не во временной папке")
        }
    }

    /// `-uiTesting` из unit-тестов не запустить, поэтому проверяется выбор путей и набора настроек по режиму.
    @Test func uiTestingModeIsIsolatedToo() {
        let uiRoot = AppDirectories.rootURL(for: .uiTesting)
        #expect(Self.isIsolated(uiRoot), "\(uiRoot.path)")
        #expect(AppDirectories.rootURL(for: .unitTesting) != uiRoot, "у каждого запуска своя папка")
        #expect(AppDirectories.rootURL(for: .normal).standardizedFileURL == Self.realRoot.standardizedFileURL)

        #expect(AppSettings.suiteName(for: .normal) == nil, "в обычном режиме — стандартные настройки")
        let suites = [RunMode.uiTesting, .unitTesting].map { AppSettings.suiteName(for: $0) }
        #expect(suites.allSatisfy { $0 != nil && $0 != Bundle.main.bundleIdentifier })
        #expect(suites[0] != suites[1])
    }

    @Test func settingsAreSeparateFromApp() throws {
        try #require(AppSettings.defaults !== UserDefaults.standard, "настройки общие с рабочим приложением")
        let key = "test.isolationProbe.\(UUID().uuidString)"
        AppSettings.defaults.set("значение", forKey: key)
        defer { AppSettings.defaults.removeObject(forKey: key) }
        #expect(AppSettings.defaults.string(forKey: key) == "значение")
    }

    @Test func autoBackupWritesAndPrunesOnlyInTemporaryFolder() throws {
        try #require(Self.isIsolated(AppDirectories.root), "данные в настоящей папке: \(AppDirectories.root.path)")
        let backups = AppDirectories.backups
        try #require(Self.isIsolated(backups), "копии пишутся в настоящую папку: \(backups.path)")

        let fileManager = FileManager.default
        for url in AutoBackupService.backupFiles() { try fileManager.removeItem(at: url) }
        let old = ["Vitae-2000-01-01_00-00-00.json", "Vitae-2000-01-02_00-00-00.json", "Vitae-2000-01-03_00-00-00.json"]
            .map { backups.appendingPathComponent($0) }
        for url in old { try Data("{}".utf8).write(to: url) }

        let env = try TestEnvironment()
        let created = try AutoBackupService.createBackup(context: env.context, fileStorage: env.fileStorage)
        #expect(Self.isIsolated(created), "копия создана вне временной папки: \(created.path)")
        #expect(created.deletingLastPathComponent().standardizedFileURL == backups.standardizedFileURL)
        #expect(AppSettings.lastAutoBackup != nil)

        let listed = AutoBackupService.backupFiles()
        #expect(listed.count == 4)
        #expect(listed.allSatisfy(Self.isIsolated), "в списке копий есть файлы вне временной папки")

        AutoBackupService.prune(keep: 2)
        let kept = AutoBackupService.backupFiles().map(\.lastPathComponent)
        #expect(kept == [created.lastPathComponent, "Vitae-2000-01-03_00-00-00.json"])
        #expect(!fileManager.fileExists(atPath: old[0].path))
        #expect(!fileManager.fileExists(atPath: old[1].path))

        for url in AutoBackupService.backupFiles() { try fileManager.removeItem(at: url) }
    }
}
