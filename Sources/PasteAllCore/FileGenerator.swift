import Foundation
import ImageIO
import UniformTypeIdentifiers
import libxlsxwriter

public protocol FileGenerating: Sendable {
    func generate(_ candidate: ConversionCandidate, at destination: URL) throws
}

public struct FileGenerator: FileGenerating, Sendable {
    public init() {}

    public func generate(_ candidate: ConversionCandidate, at destination: URL) throws {
        switch (candidate.kind, candidate.payload) {
        case (.png, .image(let data)):
            try validateSize(data)
            try validateImage(data, expectedType: .png)
            try data.write(to: destination, options: .atomic)
        case (.jpeg, .image(let data)):
            try validateSize(data)
            try validateImage(data, expectedType: .jpeg)
            try data.write(to: destination, options: .atomic)
        case (.text, .text(let text)), (.markdown, .text(let text)):
            let data = Data(text.utf8)
            try validateSize(data)
            try data.write(to: destination, options: .atomic)
        case (.webloc, .url(let url)):
            try writeWebloc(url, to: destination)
        case (.internetShortcut, .url(let url)):
            try Data("[InternetShortcut]\r\nURL=\(url.absoluteString)\r\n".utf8)
                .write(to: destination, options: .atomic)
        case (.spreadsheet, .table(let table)):
            try SpreadsheetGenerator().generate(table, at: destination)
        default:
            throw PasteAllError.generationFailed("candidate and output format do not match")
        }
    }

    private func validateSize(_ data: Data) throws {
        guard data.count <= CacheStore.maximumPayloadBytes else {
            throw PasteAllError.generationFailed("content is larger than 100 MB")
        }
    }

    private func validateImage(_ data: Data, expectedType: UTType) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let rawType = CGImageSourceGetType(source),
              let actualType = UTType(rawType as String),
              actualType.conforms(to: expectedType)
        else {
            throw PasteAllError.generationFailed("clipboard image data is invalid")
        }
    }

    private func writeWebloc(_ url: URL, to destination: URL) throws {
        let object = ["URL": url.absoluteString]
        let data = try PropertyListSerialization.data(
            fromPropertyList: object,
            format: .xml,
            options: 0
        )
        try data.write(to: destination, options: .atomic)
    }
}

public struct SpreadsheetGenerator: Sendable {
    private static let maximumRows = 1_048_576
    private static let maximumColumns = 16_384

    public init() {}

    public func generate(_ table: TableData, at destination: URL) throws {
        guard !table.rows.isEmpty,
              table.rows.count <= Self.maximumRows,
              table.columnCount > 0,
              table.columnCount <= Self.maximumColumns
        else {
            throw PasteAllError.invalidTable
        }

        let closeResult: lxw_error = try destination.path.withCString { path in
            guard let workbook = workbook_new(path) else {
                throw PasteAllError.generationFailed("could not initialize workbook")
            }
            var workbookWasClosed = false
            defer {
                if !workbookWasClosed { _ = workbook_close(workbook) }
            }
            guard let worksheet = workbook_add_worksheet(workbook, nil) else {
                throw PasteAllError.generationFailed("could not initialize worksheet")
            }

            let headerFormat = workbook_add_format(workbook)
            format_set_bold(headerFormat)

            var maximumWidths = Array(repeating: 0, count: table.columnCount)
            for (rowIndex, row) in table.rows.enumerated() {
                for (columnIndex, value) in row.enumerated() {
                    maximumWidths[columnIndex] = min(50, max(maximumWidths[columnIndex], value.count + 2))
                    let format = table.headerRows.contains(rowIndex) ? headerFormat : nil
                    try writeCell(
                        value,
                        row: lxw_row_t(rowIndex),
                        column: lxw_col_t(columnIndex),
                        worksheet: worksheet,
                        format: format
                    )
                }
            }

            for (column, width) in maximumWidths.enumerated() {
                worksheet_set_column(
                    worksheet,
                    lxw_col_t(column),
                    lxw_col_t(column),
                    Double(max(8, width)),
                    nil
                )
            }
            let result = workbook_close(workbook)
            workbookWasClosed = true
            return result
        }

        guard closeResult == LXW_NO_ERROR else {
            throw PasteAllError.generationFailed("libxlsxwriter error \(closeResult.rawValue)")
        }
    }

    private func writeCell(
        _ value: String,
        row: lxw_row_t,
        column: lxw_col_t,
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        format: UnsafeMutablePointer<lxw_format>?
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: lxw_error

        if value == trimmed, isSafeBoolean(trimmed) {
            result = worksheet_write_boolean(
                worksheet,
                row,
                column,
                trimmed.lowercased() == "true" ? 1 : 0,
                format
            )
        } else if value == trimmed, let number = safeNumber(trimmed) {
            result = worksheet_write_number(worksheet, row, column, number, format)
        } else {
            result = value.withCString {
                worksheet_write_string(worksheet, row, column, $0, format)
            }
        }

        guard result == LXW_NO_ERROR else {
            throw PasteAllError.generationFailed("could not write spreadsheet cell")
        }
    }

    private func isSafeBoolean(_ value: String) -> Bool {
        value.lowercased() == "true" || value.lowercased() == "false"
    }

    private func safeNumber(_ value: String) -> Double? {
        guard !value.isEmpty,
              !value.hasPrefix("+"),
              !value.hasPrefix("="),
              !value.hasPrefix("@"),
              value.range(of: #"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              value.filter(\.isNumber).count <= 15,
              let number = Double(value),
              number.isFinite
        else { return nil }
        return number
    }
}
