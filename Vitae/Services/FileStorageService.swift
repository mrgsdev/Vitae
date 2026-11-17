import Foundation
import UniformTypeIdentifiers

struct StoredFile: Equatable {
    let storedFileName: String
    let originalFileName: String
    let contentType: UTType
    let size: Int64
}

enum FileStorageError: LocalizedError {
    case unsupportedType(String)
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): "Формат «\(ext)» не поддерживается. Можно прикрепить PDF, PNG, JPG или HEIC."
        case .copyFailed: "Не удалось сохранить файл."
        }
    }
}

/// Хранение документов в Application Support. В SwiftData записываются только метаданные.
final class FileStorageService {
    static let supportedTypes: [UTType] = [.pdf, .png, .jpeg, .heic]

    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        AppDirectories.ensure(baseURL)
    }

    static func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { return type }
        return UTType(filenameExtension: url.pathExtension.lowercased())
    }

    static func isSupported(_ url: URL) -> Bool {
        guard let type = contentType(of: url) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    static func isImage(_ type: UTType) -> Bool { type.conforms(to: .image) }

    func url(for storedFileName: String) -> URL {
        baseURL.appendingPathComponent(storedFileName, isDirectory: false)
    }

    func fileExists(_ storedFileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: storedFileName).path)
    }

    /// Копирует файл пользователя в хранилище приложения.
    func importFile(at source: URL) throws -> StoredFile {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        guard let type = Self.contentType(of: source), Self.supportedTypes.contains(where: { type.conforms(to: $0) }) else {
            throw FileStorageError.unsupportedType(source.pathExtension)
        }
        let data = try Data(contentsOf: source)
        return try store(data: data, originalFileName: source.lastPathComponent, contentType: type)
    }

    func store(data: Data, originalFileName: String, contentType: UTType) throws -> StoredFile {
        let ext = contentType.preferredFilenameExtension ?? (originalFileName as NSString).pathExtension
        let storedName = UUID().uuidString.lowercased() + (ext.isEmpty ? "" : "." + ext)
        let destination = url(for: storedName)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        } catch {
            do {
                try data.write(to: destination, options: [.atomic])
            } catch {
                AppLog.files.error("Не удалось записать вложение")
                throw FileStorageError.copyFailed
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        AppLog.files.info("Вложение сохранено, размер \(data.count, privacy: .public) байт")
        return StoredFile(storedFileName: storedName, originalFileName: originalFileName, contentType: contentType, size: Int64(data.count))
    }

    func data(for storedFileName: String) throws -> Data {
        try Data(contentsOf: url(for: storedFileName))
    }

    func deleteFile(named storedFileName: String) {
        let target = url(for: storedFileName)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            AppLog.files.error("Не удалось удалить файл вложения")
        }
    }

    func allStoredFileNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: baseURL.path)) ?? []
    }

    /// Удаляет файлы, на которые нет ссылок в базе. Возвращает количество удалённых.
    @discardableResult
    func removeOrphans(keeping referenced: Set<String>) -> Int {
        var removed = 0
        for name in allStoredFileNames() where !referenced.contains(name) && !name.hasPrefix(".") {
            deleteFile(named: name)
            removed += 1
        }
        return removed
    }

    func totalSize() -> Int64 {
        allStoredFileNames().reduce(Int64(0)) { sum, name in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(for: name).path)[.size] as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
    }
}
