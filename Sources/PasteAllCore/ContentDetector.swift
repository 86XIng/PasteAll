import AppKit
import Foundation

public struct ContentDetector: Sendable {
    public init() {}

    public func candidates(
        for snapshot: ClipboardSnapshot,
        mode: DetectionMode,
        preferredURLFormat: URLShortcutFormat = .webloc
    ) -> [ConversionCandidate] {
        guard !snapshot.containsFileReference,
              snapshot.totalByteCount <= CacheStore.maximumPayloadBytes
        else { return [] }

        if let image = imageCandidate(in: snapshot) {
            return [image]
        }

        if let markdown = snapshot.explicitMarkdown, !markdown.isEmpty {
            return textCandidates(primary: .markdown, text: markdown, confidence: 100)
        }

        if let html = snapshot.html, let table = HTMLTableParser.parse(html) {
            let text = snapshot.plainText ?? table.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            return [
                ConversionCandidate(kind: .spreadsheet, payload: .table(table), confidence: 100),
                ConversionCandidate(kind: .text, payload: .text(text), confidence: 20)
            ]
        }

        if let url = snapshot.explicitURL ?? snapshot.plainText.flatMap(ClipboardSnapshot.validWebURL) {
            return urlCandidates(url: url, preferred: preferredURLFormat, originalText: snapshot.plainText)
        }

        guard let text = snapshot.plainText, !text.isEmpty else { return [] }

        if Self.isMarkdownTable(text) {
            return textCandidates(primary: .markdown, text: text, confidence: 95)
        }

        let hasExplicitTabularType = !snapshot.allTypes.isDisjoint(with: ClipboardSnapshot.tabularTypes)
        if hasExplicitTabularType || mode == .aggressive || mode == .askEveryTime {
            if let table = tableFromDelimitedText(text, allowCSV: hasExplicitTabularType || mode != .strict) {
                return [
                    ConversionCandidate(kind: .spreadsheet, payload: .table(table), confidence: hasExplicitTabularType ? 95 : 80),
                    ConversionCandidate(kind: .text, payload: .text(text), confidence: 20)
                ]
            }
        }

        let score = Self.markdownScore(text)
        let isMarkdown: Bool
        switch mode {
        case .strict:
            isMarkdown = score >= 5
        case .aggressive, .askEveryTime:
            isMarkdown = score >= 2
        }

        if isMarkdown {
            return textCandidates(primary: .markdown, text: text, confidence: min(90, 55 + score * 5))
        }
        return [ConversionCandidate(kind: .text, payload: .text(text), confidence: 50)]
    }

    private func imageCandidate(in snapshot: ClipboardSnapshot) -> ConversionCandidate? {
        if let png = snapshot.firstData(for: [NSPasteboard.PasteboardType.png.rawValue, "public.png"]) {
            return ConversionCandidate(kind: .png, payload: .image(png), confidence: 100)
        }

        let jpegTypes = ["public.jpeg", "public.jpg", "public.jfif"]
        if let jpeg = snapshot.firstData(for: jpegTypes) {
            return ConversionCandidate(kind: .jpeg, payload: .image(jpeg), confidence: 100)
        }

        let sourceTypes = [
            NSPasteboard.PasteboardType.tiff.rawValue,
            "public.tiff",
            "public.heic",
            "public.heif",
            "com.compuserve.gif"
        ]
        guard let data = snapshot.firstData(for: sourceTypes),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        return ConversionCandidate(kind: .png, payload: .image(png), confidence: 90)
    }

    private func tableFromDelimitedText(_ text: String, allowCSV: Bool) -> TableData? {
        if let rows = DelimitedTextParser.parse(text, delimiter: "\t") {
            return TableData(rows: rows)
        }
        if allowCSV, let rows = DelimitedTextParser.parse(text, delimiter: ",") {
            return TableData(rows: rows)
        }
        return nil
    }

    private func textCandidates(primary: OutputKind, text: String, confidence: Int) -> [ConversionCandidate] {
        var result = [ConversionCandidate(kind: primary, payload: .text(text), confidence: confidence)]
        if primary != .text {
            result.append(ConversionCandidate(kind: .text, payload: .text(text), confidence: 20))
        }
        return result
    }

    private func urlCandidates(url: URL, preferred: URLShortcutFormat, originalText: String?) -> [ConversionCandidate] {
        let preferredKind: OutputKind = preferred == .webloc ? .webloc : .internetShortcut
        let alternateKind: OutputKind = preferred == .webloc ? .internetShortcut : .webloc
        return [
            ConversionCandidate(kind: preferredKind, payload: .url(url), confidence: 100),
            ConversionCandidate(kind: alternateKind, payload: .url(url), confidence: 95),
            ConversionCandidate(kind: .text, payload: .text(originalText ?? url.absoluteString), confidence: 20)
        ]
    }

    static func isMarkdownTable(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2, lines[0].contains("|") else { return false }
        let separator = lines[1].trimmingCharacters(in: .whitespaces)
        let pattern = #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#
        return separator.range(of: pattern, options: .regularExpression) != nil
    }

    static func markdownScore(_ text: String) -> Int {
        var score = 0
        let lines = text.components(separatedBy: .newlines)
        if text.range(of: #"(?m)^```"#, options: .regularExpression) != nil { score += 4 }
        if text.range(of: #"(?m)^#{1,6}\s+\S"#, options: .regularExpression) != nil { score += 2 }
        if text.range(of: #"(?m)^\s*([-*+] |\d+\. )\S"#, options: .regularExpression) != nil { score += 1 }
        if text.range(of: #"(?m)^>\s+\S"#, options: .regularExpression) != nil { score += 1 }
        if text.range(of: #"\[[^\]]+\]\(https?://[^\)]+\)"#, options: .regularExpression) != nil { score += 2 }
        if text.range(of: #"(\*\*|__)[^\n]+(\*\*|__)"#, options: .regularExpression) != nil { score += 1 }
        if lines.count > 1, isMarkdownTable(text) { score += 4 }
        return score
    }
}
