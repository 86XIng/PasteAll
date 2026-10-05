import Darwin
import Foundation

public final class CacheStore: @unchecked Sendable {
    public static let minimumRetention: TimeInterval = 10 * 60
    public static let expirationAge: TimeInterval = 24 * 60 * 60
    public static let maximumPayloadBytes = 100 * 1024 * 1024

    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw PasteAllError.cannotCreateCache
            }
            self.directory = caches
                .appendingPathComponent("com.local.PasteAll", isDirectory: true)
                .appendingPathComponent("PreparedFiles", isDirectory: true)
        }
        try prepareDirectory()
    }

    private func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            throw PasteAllError.cannotCreateCache
        }
    }

    public func destination(
        for kind: OutputKind,
        at date: Date = Date(),
        localizedStem: (String) -> String
    ) -> URL {
        let name = FilenameGenerator().filename(
            for: kind,
            at: date,
            in: directory,
            localizedStem: localizedStem
        )
        return directory.appendingPathComponent(name)
    }

    public func reserveDestination(
        for kind: OutputKind,
        at date: Date = Date(),
        localizedStem: (String) -> String
    ) throws -> URL {
        while true {
            let fileURL = destination(for: kind, at: date, localizedStem: localizedStem)
            let descriptor = fileURL.path.withCString {
                open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            }
            if descriptor >= 0 {
                close(descriptor)
                return fileURL
            }
            guard errno == EEXIST else {
                throw PasteAllError.cannotCreateCache
            }
        }
    }

    public func secure(_ fileURL: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func cleanup(now: Date = Date(), expirationAge: TimeInterval = CacheStore.expirationAge) {
        let effectiveExpirationAge = max(expirationAge, Self.minimumRetention)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]),
                  let date = values.contentModificationDate ?? values.creationDate,
                  now.timeIntervalSince(date) > effectiveExpirationAge
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }
}
