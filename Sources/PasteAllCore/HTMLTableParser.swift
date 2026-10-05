import Foundation
import SwiftSoup

public enum HTMLTableParser {
    private static let maximumColumns = 16_384

    public static func parse(_ html: String) -> TableData? {
        do {
            let document = try SwiftSoup.parse(html)
            guard let table = try document.select("table").first() else { return nil }

            var rows: [[String]] = []
            var headerRows: Set<Int> = []
            for rowElement in try table.select("tr") {
                let cells = try rowElement.select("th, td")
                guard !cells.isEmpty() else { continue }

                var row: [String] = []
                var containsHeader = false
                for cell in cells {
                    let value = try cell.text()
                    row.append(value)
                    containsHeader = containsHeader || cell.tagName().lowercased() == "th"

                    let requestedColspan = max(1, Int(try cell.attr("colspan")) ?? 1)
                    let availableColumns = max(1, maximumColumns - row.count + 1)
                    let colspan = min(requestedColspan, availableColumns)
                    if colspan > 1 {
                        row.append(contentsOf: repeatElement("", count: colspan - 1))
                    }
                    if row.count >= maximumColumns { break }
                }
                if containsHeader { headerRows.insert(rows.count) }
                rows.append(row)
            }

            guard rows.count >= 2, rows.map(\.count).max() ?? 0 >= 2 else { return nil }
            return TableData(rows: rows, headerRows: headerRows)
        } catch {
            return nil
        }
    }
}
