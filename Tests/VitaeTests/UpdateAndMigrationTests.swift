import Foundation
import Testing
@testable import Vitae

@MainActor
@Suite("Обновление приложения")
struct UpdateTests {
    @Test func versionComparison() {
        #expect(UpdatePackage.isVersion("1.1", newerThan: "1.0"))
        #expect(UpdatePackage.isVersion("1.10", newerThan: "1.9"))
        #expect(UpdatePackage.isVersion("2", newerThan: "1.9.9"))
        #expect(UpdatePackage.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!UpdatePackage.isVersion("1.0", newerThan: "1.0"))
        #expect(!UpdatePackage.isVersion("1.0", newerThan: "1.0.0"))
        #expect(!UpdatePackage.isVersion("0.9", newerThan: "1.0"))
    }

    @Test func releasesAreDecodedFilteredAndSorted() throws {
        let json = """
        [
          {"tag_name": "v1.2", "name": "Vitae 1.2", "body": "- новое", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v1.2",
           "published_at": "2026-12-01T10:00:00Z", "draft": false, "prerelease": true,
           "assets": [{"name": "Vitae-1.2.zip", "browser_download_url": "https://example.com/Vitae-1.2.zip"}]},
          {"tag_name": "v1.0", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v1.0", "published_at": "2026-11-17T10:00:00Z",
           "assets": [{"name": "Vitae-1.0.dmg", "browser_download_url": "https://example.com/Vitae-1.0.dmg"},
                      {"name": "Vitae-1.0.zip", "browser_download_url": "https://example.com/Vitae-1.0.zip"}]},
          {"tag_name": "v1.10", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v1.10",
           "assets": [{"name": "Vitae-1.10.zip", "browser_download_url": "https://example.com/Vitae-1.10.zip"}]},
          {"tag_name": "v1.1", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v1.1", "draft": true,
           "assets": [{"name": "Vitae-1.1.zip", "browser_download_url": "https://example.com/Vitae-1.1.zip"}]},
          {"tag_name": "v0.9", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v0.9",
           "assets": [{"name": "Vitae-0.9.dmg", "browser_download_url": "https://example.com/Vitae-0.9.dmg"}]}
        ]
        """
        let releases = try JSONDecoder().decode([AppRelease].self, from: Data(json.utf8))
        let installable = Updater.installable(releases)
        #expect(installable.map(\.version) == ["1.10", "1.0"], "без черновиков, pre-release и релизов без zip")
        let first = try #require(releases.first { $0.version == "1.0" })
        #expect(first.archive?.name == "Vitae-1.0.zip")
        #expect(first.publishedDate != nil)
    }

    @Test func packageIsUnpackedAndValidated() async throws {
        let host = Bundle.main.bundleURL
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VitaeUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("Vitae.zip")
        try await UpdatePackage.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", host.path, zip.path])

        let app = try await UpdatePackage.unpack(zip, into: folder.appendingPathComponent("unpacked", isDirectory: true))
        #expect(app.lastPathComponent == host.lastPathComponent)

        let identifier = Bundle.main.bundleIdentifier
        let version = try UpdatePackage.validate(app, bundleIdentifier: identifier, currentVersion: "0.1", allowingOlder: false)
        #expect(version == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect(throws: UpdateError.notNewer(version)) {
            try UpdatePackage.validate(app, bundleIdentifier: identifier, currentVersion: "99.0", allowingOlder: false)
        }
        #expect(throws: UpdateError.sameVersion(version)) {
            try UpdatePackage.validate(app, bundleIdentifier: identifier, currentVersion: version, allowingOlder: true)
        }
        #expect(throws: UpdateError.wrongApp) {
            try UpdatePackage.validate(app, bundleIdentifier: "com.example.other", currentVersion: "0.1", allowingOlder: false)
        }
        let empty = folder.appendingPathComponent("empty.zip")
        try Data().write(to: empty)
        await #expect(throws: UpdateError.unpack) {
            _ = try await UpdatePackage.unpack(empty, into: folder.appendingPathComponent("broken", isDirectory: true))
        }
    }

    /// Копия Vitae с той же подписью проходит; приложение другого разработчика и изменённый пакет — нет.
    @Test func signatureMustMatchDeveloper() async throws {
        let host = Bundle.main.bundleURL
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VitaeSign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(host.lastPathComponent)
        try await UpdatePackage.run("/usr/bin/ditto", [host.path, copy.path])

        try UpdatePackage.checkSignature(of: copy, against: host)

        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try #require(FileManager.default.fileExists(atPath: calculator.path))
        #expect(throws: UpdateError.badSignature, "требование подписи Apple не выполняется для Vitae") {
            try UpdatePackage.checkSignature(of: copy, against: calculator)
        }

        try Data("подмена".utf8).write(to: copy.appendingPathComponent("Contents/Resources/injected.txt"))
        #expect(throws: UpdateError.badSignature, "изменённый пакет не проходит проверку") {
            try UpdatePackage.checkSignature(of: copy, against: host)
        }
    }

    @Test func notesForRollbackWarnAboutNewerData() throws {
        let json = """
        [{"tag_name": "v0.5", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v0.5",
          "assets": [{"name": "Vitae-0.5.zip", "browser_download_url": "https://example.com/Vitae-0.5.zip"}]},
         {"tag_name": "v99.0", "html_url": "https://github.com/mrgsdev/Vitae/releases/tag/v99.0",
          "assets": [{"name": "Vitae-99.0.zip", "browser_download_url": "https://example.com/Vitae-99.0.zip"}]}]
        """
        let releases = try JSONDecoder().decode([AppRelease].self, from: Data(json.utf8))
        let older = try #require(releases.first { $0.version == "0.5" })
        let newer = try #require(releases.first { $0.version == "99.0" })
        let rollback = UpdateNote.forVersion(older, newest: newer)
        #expect(rollback.contains { $0.isWarning })
        #expect(rollback.contains { $0.text.contains("резервную копию") })
        #expect(rollback.contains { $0.text.contains("99.0 будет пропущена") })
        #expect(!UpdateNote.forVersion(newer, newest: newer).contains { $0.isWarning })
    }
}

@Suite("Перенос данных из песочницы")
struct LegacyMigrationTests {
    private func makeFolders() throws -> (legacy: URL, root: URL, cleanup: () -> Void) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("VitaeMigration-\(UUID().uuidString)", isDirectory: true)
        let legacy = base.appendingPathComponent("Library/Containers/app/Data/Library/Application Support/Vitae", isDirectory: true)
        let root = base.appendingPathComponent("Library/Application Support/Vitae", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        return (legacy, root, { try? FileManager.default.removeItem(at: base) })
    }

    @Test func copiesStoreAndFilesOnce() throws {
        let (legacy, root, cleanup) = try makeFolders()
        defer { cleanup() }
        try Data("store".utf8).write(to: legacy.appendingPathComponent("Vitae.store"))
        try Data("wal".utf8).write(to: legacy.appendingPathComponent("Vitae.store-wal"))
        try Data("pdf".utf8).write(to: legacy.appendingPathComponent("Attachments/blank.pdf"))

        let outcome = LegacyDataMigration.migrateIfNeeded(from: legacy, to: root)
        #expect(outcome == .migrated(files: 3))
        #expect(try Data(contentsOf: root.appendingPathComponent("Vitae.store")) == Data("store".utf8))
        #expect(try Data(contentsOf: root.appendingPathComponent("Vitae.store-wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: root.appendingPathComponent("Attachments/blank.pdf")) == Data("pdf".utf8))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("Vitae.store").path), "оригинал остаётся")

        #expect(LegacyDataMigration.migrateIfNeeded(from: legacy, to: root) == .notNeeded, "повторно не переносится")
    }

    @Test func skipsWhenNothingToMoveOrSandboxed() throws {
        let (legacy, root, cleanup) = try makeFolders()
        defer { cleanup() }
        #expect(LegacyDataMigration.migrateIfNeeded(from: legacy, to: root) == .notNeeded)
        try Data("store".utf8).write(to: legacy.appendingPathComponent("Vitae.store"))
        #expect(LegacyDataMigration.migrateIfNeeded(from: legacy, to: legacy) == .notNeeded)
    }

    final class MemoryPreferences: PreferenceStore {
        var values: [String: Any] = [:]
        func object(forKey defaultName: String) -> Any? { values[defaultName] }
        func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
        func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    }

    @Test func preferencesAreCopiedWithoutOverwriting() throws {
        let suite = "VitaeMigrationTests-\(UUID().uuidString)"
        let defaults = MemoryPreferences()
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).plist")
        defer { try? FileManager.default.removeItem(at: plist) }
        let legacy: NSDictionary = ["settings.defaultCurrency": "USD", "settings.lockEnabled": true, "NSWindow Frame main": "x"]
        legacy.write(to: plist, atomically: true)
        defaults.set(false, forKey: "settings.lockEnabled")

        LegacyDataMigration.migratePreferencesIfNeeded(from: plist, defaults: defaults)
        #expect(defaults.string(forKey: "settings.defaultCurrency") == "USD")
        #expect(defaults.bool(forKey: "settings.lockEnabled") == false, "уже заданное значение не перезаписывается")
        #expect(defaults.object(forKey: "NSWindow Frame main") == nil, "служебные ключи не переносятся")
        #expect(defaults.bool(forKey: LegacyDataMigration.preferencesMarker))
    }
}
