import AppKit
import Foundation

public struct ClipboardRepresentation: Equatable, Sendable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct ClipboardItemSnapshot: Equatable, Sendable {
    public let representations: [ClipboardRepresentation]

    public init(representations: [ClipboardRepresentation]) {
        self.representations = representations
    }

    public func data(for rawType: String) -> Data? {
        representations.first { $0.type == rawType }?.data
    }

    public func string(for rawType: String) -> String? {
        guard let data = data(for: rawType) else { return nil }
        if rawType == "public.utf16-plain-text" {
            let hasByteOrderMark = data.starts(with: [0xFF, 0xFE])
                || data.starts(with: [0xFE, 0xFF])
            return String(
                data: data,
                encoding: hasByteOrderMark ? .utf16 : .utf16LittleEndian
            )
        }
        if rawType == "public.utf16-external-plain-text" {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public static let markdownTypes = [
        "net.daringfireball.markdown",
        "public.markdown"
    ]

    public static let fileReferenceTypes: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        "public.file-url",
        "NSFilenamesPboardType"
    ]

    public static let tabularTypes: Set<String> = [
        "public.utf8-tab-separated-values-text",
        "public.tab-separated-values-text",
        "public.comma-separated-values-text"
    ]

    public let changeCount: Int
    public let items: [ClipboardItemSnapshot]

    public init(changeCount: Int, items: [ClipboardItemSnapshot]) {
        self.changeCount = changeCount
        self.items = items
    }

    public init(pasteboard: NSPasteboard = .general) {
        changeCount = pasteboard.changeCount
        items = (pasteboard.pasteboardItems ?? []).map { item in
            ClipboardItemSnapshot(representations: item.types.compactMap { type in
                item.data(forType: type).map {
                    ClipboardRepresentation(type: type.rawValue, data: $0)
                }
            })
        }
    }

    public var containsFileReference: Bool {
        items.contains { item in
            item.representations.contains { Self.fileReferenceTypes.contains($0.type) }
        }
    }

    public var allTypes: Set<String> {
        Set(items.flatMap { $0.representations.map(\.type) })
    }

    public var totalByteCount: Int {
        items.lazy
            .flatMap(\.representations)
            .reduce(0) { count, representation in
                let (sum, overflow) = count.addingReportingOverflow(representation.data.count)
                return overflow ? Int.max : sum
            }
    }

    public func firstData(for rawTypes: [String]) -> Data? {
        for item in items {
            for rawType in rawTypes {
                if let data = item.data(for: rawType) { return data }
            }
        }
        return nil
    }

    public func firstString(for rawTypes: [String]) -> String? {
        for item in items {
            for rawType in rawTypes {
                if let value = item.string(for: rawType) { return value }
            }
        }
        return nil
    }

    public var plainText: String? {
        firstString(for: [
            NSPasteboard.PasteboardType.string.rawValue,
            "public.utf8-plain-text",
            "public.utf16-plain-text",
            "public.utf16-external-plain-text",
            "public.utf8-tab-separated-values-text",
            "public.tab-separated-values-text",
            "public.comma-separated-values-text"
        ])
    }

    public var html: String? {
        firstString(for: [NSPasteboard.PasteboardType.html.rawValue, "public.html"])
    }

    public var explicitMarkdown: String? {
        firstString(for: Self.markdownTypes)
    }

    public var explicitURL: URL? {
        guard let value = firstString(for: [NSPasteboard.PasteboardType.URL.rawValue, "public.url"]) else {
            return nil
        }
        return Self.validWebURL(value)
    }

    public func restore(to pasteboard: NSPasteboard = .general) throws {
        let restoredItems: [NSPasteboardItem] = items.map { snapshot in
            let item = NSPasteboardItem()
            for representation in snapshot.representations {
                item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.type)
                )
            }
            return item
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(restoredItems) else {
            throw PasteAllError.cannotWritePasteboard
        }
    }

    public static func validWebURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
