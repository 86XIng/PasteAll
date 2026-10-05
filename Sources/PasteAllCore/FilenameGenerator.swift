import Foundation

public struct FilenameGenerator: Sendable {
    private let calendar: Calendar
    private let locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    public func filename(
        for kind: OutputKind,
        at date: Date = Date(),
        in directory: URL,
        localizedStem: (String) -> String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        let base = "\(localizedStem(kind.filenameStemKey)) \(formatter.string(from: date))"
        let ext = kind.fileExtension
        var candidate = "\(base).\(ext)"
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }
}
