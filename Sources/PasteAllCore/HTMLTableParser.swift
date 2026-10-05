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
            for group in rowGroups(in: table) {
                // Each entry is the first row no longer covered by the span in that column.
                var occupiedUntil: [Int] = []
                for (rowIndex, rowElement) in group.enumerated() {
                    var row = occupiedUntil.map { _ in "" }
                    var column = 0
                    var containsHeader = false
                    let cells = rowElement.children().array().filter {
                        ["th", "td"].contains($0.tagName().lowercased())
                    }
                    for cell in cells {
                        while column < occupiedUntil.count, occupiedUntil[column] > rowIndex {
                            column += 1
                        }
                        guard column < maximumColumns else { break }
                        let colspan = min(max(1, Int(try cell.attr("colspan")) ?? 1), maximumColumns - column)
                        let requestedRowspan = Int(try cell.attr("rowspan")) ?? 1
                        let rowspan = requestedRowspan == 0
                            ? group.count - rowIndex
                            : min(max(1, requestedRowspan), group.count - rowIndex)
                        let endColumn = column + colspan
                        if endColumn > occupiedUntil.count {
                            occupiedUntil.append(contentsOf: repeatElement(0, count: endColumn - occupiedUntil.count))
                            row.append(contentsOf: repeatElement("", count: endColumn - row.count))
                        }
                        // Overlapping spans are malformed; don't silently shift or overwrite data.
                        guard (column..<endColumn).allSatisfy({ occupiedUntil[$0] <= rowIndex }) else {
                            return nil
                        }
                        row[column] = try cell.text()
                        containsHeader = containsHeader || cell.tagName().lowercased() == "th"
                        for slot in column..<endColumn {
                            occupiedUntil[slot] = rowIndex + rowspan
                        }
                        column = endColumn
                    }
                    guard !cells.isEmpty || occupiedUntil.contains(where: { $0 > rowIndex }) else { continue }
                    if containsHeader { headerRows.insert(rows.count) }
                    rows.append(row)
                }
            }

            guard rows.count >= 2, rows.map(\.count).max() ?? 0 >= 2 else { return nil }
            return TableData(rows: rows, headerRows: headerRows)
        } catch {
            return nil
        }
    }

    private static func rowGroups(in table: Element) -> [[Element]] {
        var groups: [[Element]] = []
        var directRows: [Element] = []
        for child in table.children() {
            if child.tagName().lowercased() == "tr" {
                directRows.append(child)
            } else if ["thead", "tbody", "tfoot"].contains(child.tagName().lowercased()) {
                if !directRows.isEmpty {
                    groups.append(directRows)
                    directRows = []
                }
                groups.append(child.children().array().filter { $0.tagName().lowercased() == "tr" })
            }
        }
        if !directRows.isEmpty { groups.append(directRows) }
        return groups
    }
}
