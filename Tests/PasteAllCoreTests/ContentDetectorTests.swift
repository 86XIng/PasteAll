import AppKit
import XCTest
@testable import PasteAllCore

final class ContentDetectorTests: XCTestCase {
    private let detector = ContentDetector()

    func testFileReferenceAlwaysPassesThrough() {
        let snapshot = makeSnapshot([
            (NSPasteboard.PasteboardType.fileURL.rawValue, Data("file:///tmp/example.txt".utf8)),
            (NSPasteboard.PasteboardType.string.rawValue, Data("hello".utf8))
        ])

        XCTAssertTrue(detector.candidates(for: snapshot, mode: .aggressive).isEmpty)
    }

    func testPNGHasPriorityOverText() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let snapshot = makeSnapshot([
            (NSPasteboard.PasteboardType.string.rawValue, Data("hello".utf8)),
            (NSPasteboard.PasteboardType.png.rawValue, png)
        ])

        let result = detector.candidates(for: snapshot, mode: .aggressive)
        XCTAssertEqual(result.first?.kind, .png)
        XCTAssertEqual(result.first?.payload, .image(png))
    }

    func testExplicitMarkdownWins() {
        let markdown = "# Heading\n\nBody"
        let snapshot = makeSnapshot([
            ("public.markdown", Data(markdown.utf8)),
            (NSPasteboard.PasteboardType.string.rawValue, Data(markdown.utf8))
        ])

        XCTAssertEqual(detector.candidates(for: snapshot, mode: .strict).first?.kind, .markdown)
    }

    func testMarkdownTableDoesNotBecomeSpreadsheet() {
        let text = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let snapshot = textSnapshot(text)

        XCTAssertEqual(detector.candidates(for: snapshot, mode: .aggressive).first?.kind, .markdown)
    }

    func testAggressiveDetectsTSV() {
        let result = detector.candidates(
            for: textSnapshot("name\tage\nAda\t36"),
            mode: .aggressive
        )

        XCTAssertEqual(result.first?.kind, .spreadsheet)
        guard case .table(let table) = result.first?.payload else {
            return XCTFail("Expected table payload")
        }
        XCTAssertEqual(table.rows, [["name", "age"], ["Ada", "36"]])
    }

    func testStrictDoesNotGuessCSVWithoutExplicitType() {
        let result = detector.candidates(
            for: textSnapshot("name,age\nAda,36"),
            mode: .strict
        )
        XCTAssertEqual(result.first?.kind, .text)
    }

    func testStrictAcceptsExplicitCSV() {
        let value = "name,age\nAda,36"
        let snapshot = makeSnapshot([
            ("public.comma-separated-values-text", Data(value.utf8)),
            (NSPasteboard.PasteboardType.string.rawValue, Data(value.utf8))
        ])
        XCTAssertEqual(detector.candidates(for: snapshot, mode: .strict).first?.kind, .spreadsheet)
    }

    func testAggressiveMarkdownHeuristic() {
        let result = detector.candidates(
            for: textSnapshot("# Heading\n\nSome text"),
            mode: .aggressive
        )
        XCTAssertEqual(result.first?.kind, .markdown)
    }

    func testStrictFallsBackForWeakMarkdown() {
        let result = detector.candidates(
            for: textSnapshot("# Heading\n\nSome text"),
            mode: .strict
        )
        XCTAssertEqual(result.first?.kind, .text)
    }

    func testURLProvidesBothShortcutFormatsAndText() {
        let result = detector.candidates(
            for: textSnapshot("https://example.com/path?q=1"),
            mode: .strict,
            preferredURLFormat: .internetShortcut
        )
        XCTAssertEqual(result.map(\.kind), [.internetShortcut, .webloc, .text])
    }

    func testTextContainingURLIsNotURLShortcut() {
        let result = detector.candidates(
            for: textSnapshot("See https://example.com for details"),
            mode: .aggressive
        )
        XCTAssertEqual(result.first?.kind, .text)
    }

    func testBOMlessUTF16PlainTextUsesDeclaredEncoding() {
        let text = "Alpha,\u{4E16}\u{754C}"
        let snapshot = makeSnapshot([
            ("public.utf16-plain-text", text.data(using: .utf16LittleEndian)!)
        ])

        XCTAssertEqual(snapshot.plainText, text)
        XCTAssertEqual(
            detector.candidates(for: snapshot, mode: .strict).first?.payload,
            .text(text)
        )
    }

    func testUTF16PlainTextStripsOptionalByteOrderMark() {
        let text = "Alpha,\u{4E16}\u{754C}"
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        let snapshot = makeSnapshot([("public.utf16-plain-text", data)])

        XCTAssertEqual(snapshot.plainText, text)
    }

    private func textSnapshot(_ text: String) -> ClipboardSnapshot {
        makeSnapshot([(NSPasteboard.PasteboardType.string.rawValue, Data(text.utf8))])
    }

    private func makeSnapshot(_ representations: [(String, Data)]) -> ClipboardSnapshot {
        ClipboardSnapshot(
            changeCount: 10,
            items: [ClipboardItemSnapshot(representations: representations.map {
                ClipboardRepresentation(type: $0.0, data: $0.1)
            })]
        )
    }
}
