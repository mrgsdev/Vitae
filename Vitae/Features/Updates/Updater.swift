import AppKit
import Foundation
import Observation
import OSLog
import Security

/// Релиз на GitHub в том виде, в каком его отдают `releases/latest` и `releases`.
struct AppRelease: Decodable, Equatable, Identifiable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]
    let publishedAt: String?
    var draft = false
    var prerelease = false

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets, draft, prerelease
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }

    var id: String { tagName }

    var publishedDate: Date? {
        publishedAt.flatMap { try? Date($0, strategy: .iso8601) }
    }

    /// «v1.2» → «1.2».
    var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }

    /// Архив с приложением для обновления изнутри приложения.
    var archive: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
}

enum UpdateError: LocalizedError, Equatable {
    case server(Int)
    case translocated
    case notWritable(String)
    case noArchive
    case unpack
    case noApp
    case wrongApp
    case notNewer(String)
    case sameVersion(String)
    case badSignature

    var errorDescription: String? {
        switch self {
        case .server(let status): "GitHub ответил ошибкой \(status)."
        case .translocated: "Переместите Vitae в папку «Программы», запустите её оттуда и обновите снова."
        case .notWritable(let path): "Нет прав на запись в \(path). Скачайте новую версию со страницы релиза."
        case .noArchive: "К релизу не приложен архив с приложением."
        case .unpack: "Не удалось распаковать архив обновления."
        case .noApp: "В архиве обновления нет приложения."
        case .wrongApp: "В архиве обновления другое приложение."
        case .notNewer(let version): "В архиве версия \(version), она не новее установленной."
        case .sameVersion(let version): "Версия \(version) уже установлена."
        case .badSignature: "Подпись обновления не совпадает с подписью Vitae. Обновление не установлено."
        }
    }
}

/// Распаковка и проверка скачанного архива. Вынесено отдельно, чтобы покрыть тестами.
enum UpdatePackage {
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let parse = { (version: String) in version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }
        let lhs = parse(candidate), rhs = parse(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Распаковывает zip (ditto сохраняет подпись) и возвращает единственное приложение внутри.
    static func unpack(_ zip: URL, into folder: URL) async throws -> URL {
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let apps = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard let app = apps.first else { throw UpdateError.noApp }
        return app
    }

    /// Проверяет bundle id и версию нового приложения; возвращает его версию.
    static func validate(_ app: URL, bundleIdentifier: String?, currentVersion: String, allowingOlder: Bool) throws -> String {
        guard let bundle = Bundle(url: app) else { throw UpdateError.noApp }
        guard bundle.bundleIdentifier == bundleIdentifier else { throw UpdateError.wrongApp }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if allowingOlder {
            guard version != currentVersion else { throw UpdateError.sameVersion(version) }
        } else {
            guard isVersion(version, newerThan: currentVersion) else { throw UpdateError.notNewer(version) }
        }
        return version
    }

    /// Новое приложение должно удовлетворять обязательному требованию подписи текущего:
    /// тот же bundle id и тот же разработчик.
    static func checkSignature(of app: URL, against current: URL) throws {
        var currentCode: SecStaticCode?
        var newCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode) == errSecSuccess,
              let currentCode,
              SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess,
              let newCode
        else { throw UpdateError.badSignature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else { throw UpdateError.badSignature }
    }

    static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.unpack)
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Обновление из релизов GitHub mrgsdev/Vitae: находит новую версию, скачивает zip, проверяет,
/// что внутри то же приложение с той же подписью, ставит его на место текущего и перезапускает.
/// Сеть используется только здесь; медицинские данные никуда не отправляются.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease)
        case failed(String, release: AppRelease?)
    }

    static let shared = Updater()

    private(set) var state: State = .idle

    nonisolated static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    nonisolated static let releasesPage = URL(string: "https://github.com/mrgsdev/Vitae/releases")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/mrgsdev/Vitae/releases/latest")!
    private static let allReleases = URL(string: "https://api.github.com/repos/mrgsdev/Vitae/releases?per_page=100")!
    static let skippedKey = "settings.skippedUpdateVersion"
    static let automaticChecksKey = "settings.automaticUpdateChecks"
    private static let log = Logger(subsystem: "Vitae", category: "update")

    /// Версия, которую пользователь пропустил: сама она не предлагается, только из «Проверить обновления…».
    var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.skippedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.skippedKey) }
    }

    static var automaticChecksEnabled: Bool {
        get { UserDefaults.standard.object(forKey: automaticChecksKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticChecksKey) }
    }

    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var installTask: Task<Void, Never>?
    /// Версия, отложенная кнопкой «Позже»: до следующего запуска не предлагается.
    @ObservationIgnored private var postponed: String?

    private let session = URLSession(configuration: .ephemeral)

    private init() {}

    /// Проверка работает в обычном режиме; в отладочной сборке — также с подменённым источником релизов.
    static var isEnabled: Bool {
        if RunMode.current == .normal { return true }
        #if DEBUG
        return UserDefaults.standard.string(forKey: "updateFeedURL") != nil
        #else
        return false
        #endif
    }

    // MARK: Проверка

    /// Не чаще двух раз в сутки без вопросов; true — есть что предложить.
    func checkInBackground() async -> Bool {
        guard Self.isEnabled, Self.automaticChecksEnabled,
              Date().timeIntervalSince(lastCheck) > 12 * 3600, !isBusy else { return false }
        await check()
        if case let .available(release) = state, release.version != postponed, release.version != skippedVersion { return true }
        if case .available = state {} else { state = .idle }
        return false
    }

    /// «Проверить обновления…»: окно покажет результат, в том числе «обновлений нет» и ошибки.
    func checkNow() async {
        guard !isBusy else { return }
        await check()
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading: true
        default: false
        }
    }

    private func check() async {
        state = .checking
        lastCheck = Date()
        do {
            let (data, status) = try await fetch(Self.feedURL)
            if status == 404 {
                state = .upToDate
                return
            }
            guard (200..<300).contains(status) else { throw UpdateError.server(status) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            state = UpdatePackage.isVersion(release.version, newerThan: Self.currentVersion) && release.archive != nil
                ? .available(release) : .upToDate
        } catch {
            Self.log.error("Проверка обновлений не выполнена: \(error.localizedDescription, privacy: .public)")
            state = .failed("Не удалось проверить обновления: \(error.localizedDescription)", release: nil)
        }
    }

    /// Все опубликованные релизы с архивом, от новых к старым, для «Другие версии…».
    func releases() async throws -> [AppRelease] {
        let (data, status) = try await fetch(Self.releasesURL)
        guard (200..<300).contains(status) else { throw UpdateError.server(status) }
        return Self.installable(try JSONDecoder().decode([AppRelease].self, from: data))
    }

    static func installable(_ releases: [AppRelease]) -> [AppRelease] {
        releases.filter { !$0.draft && !$0.prerelease && $0.archive != nil }
            .sorted { UpdatePackage.isVersion($0.version, newerThan: $1.version) }
    }

    private func fetch(_ url: URL) async throws -> (Data, Int) {
        if url.isFileURL { return (try Data(contentsOf: url), 200) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// GitHub API или локальный JSON для проверки (только Debug).
    private static var feedURL: URL {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "updateFeedURL"), let url = URL(string: value) { return url }
        #endif
        return latestRelease
    }

    private static var releasesURL: URL {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "updateReleasesURL"), let url = URL(string: value) { return url }
        #endif
        return allReleases
    }

    // MARK: Выбор пользователя

    /// «Пропустить эту версию».
    func skip(_ release: AppRelease) {
        skippedVersion = release.version
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    /// «Отмена» во время загрузки из «Другие версии…» или закрытие этого окна.
    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        state = .idle
    }

    /// Окно обновления закрыто: предложенная версия считается «Позже», загрузка останавливается.
    func windowClosed() {
        switch state {
        case let .available(release):
            postponed = release.version
        case .downloading:
            installTask?.cancel()
            installTask = nil
        default:
            break
        }
        state = .idle
    }

    // MARK: Установка

    /// Ставит `release`. Более старую версию — только по запросу из «Другие версии…»: тогда `newest`,
    /// оставленная намеренно, считается пропущенной и не предлагается сама.
    func install(_ release: AppRelease, allowingOlder: Bool = false, newest: AppRelease? = nil) {
        guard installTask == nil else { return }
        state = .downloading(release)
        installTask = Task {
            do {
                try await download(release, allowingOlder: allowingOlder, newest: newest)
            } catch is CancellationError {
            } catch {
                Self.log.error("Обновление не установлено: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription, release: release)
            }
            installTask = nil
        }
    }

    private func download(_ release: AppRelease, allowingOlder: Bool, newest: AppRelease?) async throws {
        let current = Bundle.main.bundleURL
        guard !current.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }
        let folder = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw UpdateError.notWritable(folder.path) }
        guard let archive = release.archive else { throw UpdateError.noArchive }

        let downloaded: URL
        if archive.browserDownloadURL.isFileURL {
            downloaded = archive.browserDownloadURL
        } else {
            downloaded = try await session.download(from: archive.browserDownloadURL).0
        }
        try Task.checkCancellation()

        // Распаковка на том же томе, что и приложение, — замена становится переименованием.
        let workspace = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: current, create: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let zip = workspace.appendingPathComponent("update.zip")
        if archive.browserDownloadURL.isFileURL {
            try FileManager.default.copyItem(at: downloaded, to: zip)
        } else {
            try FileManager.default.moveItem(at: downloaded, to: zip)
        }
        let newApp = try await UpdatePackage.unpack(zip, into: workspace.appendingPathComponent("unpacked", isDirectory: true))
        try Task.checkCancellation()

        let newVersion = try UpdatePackage.validate(newApp, bundleIdentifier: Bundle.main.bundleIdentifier,
                                                    currentVersion: Self.currentVersion, allowingOlder: allowingOlder)
        try UpdatePackage.checkSignature(of: newApp, against: current)

        prepareDataForSwitch()
        // Отметку о пропущенной версии пишем до замены пакета: после подмены исполняемого файла
        // macOS может не принять запись настроек от этого процесса.
        let previousSkipped = skippedVersion
        let leaving = newest?.version ?? Self.currentVersion
        if allowingOlder, UpdatePackage.isVersion(leaving, newerThan: newVersion) {
            skippedVersion = leaving
        }
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
        } catch {
            skippedVersion = previousSkipped
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            throw error
        }
        Self.log.notice("Установлена версия \(newVersion, privacy: .public)")
        relaunch(current)
    }

    /// Перед сменой версии сохраняем изменения и делаем резервную копию базы.
    private func prepareDataForSwitch() {
        guard RunMode.current == .normal else { return }
        let environment = AppEnvironment.shared
        try? environment.context.save()
        do {
            try AutoBackupService.createBackup(context: environment.context, fileStorage: environment.fileStorage)
        } catch {
            Self.log.error("Резервная копия перед обновлением не создана")
        }
    }

    private func relaunch(_ app: URL) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "updateNoRelaunch") {
            NSApp.terminate(nil)
            return
        }
        #endif
        do {
            try AppRelaunch.relaunch(app)
        } catch {
            state = .failed("Обновление установлено, но перезапустить Vitae не получилось. Откройте приложение снова.", release: nil)
        }
    }

    #if DEBUG
    /// Отладка без интерфейса: `-updateAutoInstall YES` ставит найденное обновление,
    /// `-updateInstallVersion 1.0` — указанную версию из списка релизов,
    /// `-updateResetSkipped YES` — снимает отметку о пропущенной версии и закрывает приложение.
    func runDebugAutomation() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "updateResetSkipped") {
            defaults.removeObject(forKey: Self.skippedKey)
            defaults.removeObject(forKey: "settings.debugWriteProbe")
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            NSApp.terminate(nil)
            return
        }
        if let version = defaults.string(forKey: "updateInstallVersion") {
            guard let all = try? await releases(), let target = all.first(where: { $0.version == version }) else { return }
            install(target, allowingOlder: true, newest: all.first)
        } else if defaults.bool(forKey: "updateAutoInstall") {
            await checkNow()
            if case let .available(release) = state { install(release) }
        }
    }
    #endif
}

/// Закрывает приложение и открывает его снова, уже из нового пакета.
enum AppRelaunch {
    @MainActor
    static func relaunch(_ app: URL = Bundle.main.bundleURL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$0\"", app.path]
        try process.run()
        NSApp.terminate(nil)
    }
}
