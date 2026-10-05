import Foundation

public enum DetectionMode: String, CaseIterable, Codable, Sendable {
    case strict
    case aggressive
    case askEveryTime
}

public enum URLShortcutFormat: String, CaseIterable, Codable, Sendable {
    case webloc
    case internetShortcut
}

public enum OutputKind: String, CaseIterable, Codable, Sendable {
    case png
    case jpeg
    case text
    case markdown
    case spreadsheet
    case webloc
    case internetShortcut

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .text: "txt"
        case .markdown: "md"
        case .spreadsheet: "xlsx"
        case .webloc: "webloc"
        case .internetShortcut: "url"
        }
    }

    public var filenameStemKey: String {
        switch self {
        case .png, .jpeg: "filename.image"
        case .spreadsheet: "filename.table"
        case .webloc, .internetShortcut: "filename.webpage"
        case .text, .markdown: "filename.clipboard"
        }
    }
}

public struct TableData: Equatable, Sendable {
    public let rows: [[String]]
    public let headerRows: Set<Int>

    public init(rows: [[String]], headerRows: Set<Int> = []) {
        self.rows = rows
        self.headerRows = headerRows
    }

    public var columnCount: Int {
        rows.map(\.count).max() ?? 0
    }
}

public enum CandidatePayload: Equatable, Sendable {
    case image(Data)
    case text(String)
    case url(URL)
    case table(TableData)
}

public struct ConversionCandidate: Equatable, Sendable, Identifiable {
    public let kind: OutputKind
    public let payload: CandidatePayload
    public let confidence: Int

    public var id: OutputKind { kind }

    public init(kind: OutputKind, payload: CandidatePayload, confidence: Int) {
        self.kind = kind
        self.payload = payload
        self.confidence = confidence
    }
}

public enum PasteAllError: LocalizedError, Equatable {
    case clipboardChanged
    case unsupportedContent
    case invalidTable
    case cannotDecodeImage
    case cannotCreateCache
    case cannotWritePasteboard
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .clipboardChanged: "The clipboard changed before it could be pasted."
        case .unsupportedContent: "The clipboard does not contain supported content."
        case .invalidTable: "The clipboard table could not be parsed."
        case .cannotDecodeImage: "The clipboard image could not be decoded."
        case .cannotCreateCache: "PasteAll could not create its private cache."
        case .cannotWritePasteboard: "PasteAll could not prepare Finder paste."
        case .generationFailed(let detail): "Could not create the file: \(detail)"
        }
    }
}
