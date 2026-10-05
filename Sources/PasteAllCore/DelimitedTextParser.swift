import Foundation

public enum DelimitedTextParser {
    public static func parse(_ text: String, delimiter: Character) -> [[String]]? {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == delimiter, !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        guard !inQuotes else { return nil }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        while rows.last?.allSatisfy({ $0.isEmpty }) == true {
            rows.removeLast()
        }

        guard rows.count >= 2,
              let width = rows.first?.count,
              width >= 2,
              rows.allSatisfy({ $0.count == width })
        else { return nil }

        return rows
    }
}
