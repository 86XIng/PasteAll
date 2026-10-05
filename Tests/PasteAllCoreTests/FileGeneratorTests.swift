import AppKit
import Foundation
import XCTest
@testable import PasteAllCore

final class FileGeneratorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteAllTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testTextIsUTF8WithoutBOM() throws {
        let url = temporaryDirectory.appendingPathComponent("example.txt")
        try FileGenerator().generate(
            ConversionCandidate(kind: .text, payload: .text("你好"), confidence: 100),
            at: url
        )
        XCTAssertEqual(try Data(contentsOf: url), Data("你好".utf8))
    }

    func testPNGAndJPEGImagesAreValidatedAndWritten() throws {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let cases: [(OutputKind, NSBitmapImageRep.FileType, String)] = [
            (.png, .png, "image.png"),
            (.jpeg, .jpeg, "image.jpg")
        ]

        for (kind, fileType, filename) in cases {
            let data = try XCTUnwrap(representation.representation(using: fileType, properties: [:]))
            let url = temporaryDirectory.appendingPathComponent(filename)
            try FileGenerator().generate(
                ConversionCandidate(kind: kind, payload: .image(data), confidence: 100),
                at: url
            )
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testInvalidImageDataIsRejected() {
        let url = temporaryDirectory.appendingPathComponent("invalid.png")
        XCTAssertThrowsError(
            try FileGenerator().generate(
                ConversionCandidate(kind: .png, payload: .image(Data("not an image".utf8)), confidence: 100),
                at: url
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInternetShortcutContents() throws {
        let url = temporaryDirectory.appendingPathComponent("example.url")
        try FileGenerator().generate(
            ConversionCandidate(
                kind: .internetShortcut,
                payload: .url(URL(string: "https://example.com/a?b=1")!),
                confidence: 100
            ),
            at: url
        )
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "[InternetShortcut]\r\nURL=https://example.com/a?b=1\r\n"
        )
    }

    func testWeblocIsValidPropertyList() throws {
        let url = temporaryDirectory.appendingPathComponent("example.webloc")
        try FileGenerator().generate(
            ConversionCandidate(
                kind: .webloc,
                payload: .url(URL(string: "https://example.com")!),
                confidence: 100
            ),
            at: url
        )
        let value = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            options: [],
            format: nil
        ) as? [String: String]
        XCTAssertEqual(value?["URL"], "https://example.com")
    }

    func testSpreadsheetIsARealZipAndTreatsFormulaAsText() throws {
        let url = temporaryDirectory.appendingPathComponent("example.xlsx")
        let table = TableData(
            rows: [["Name", "Value"], ["Safe", "=1+1"], ["Count", "42"]],
            headerRows: [0]
        )
        try FileGenerator().generate(
            ConversionCandidate(kind: .spreadsheet, payload: .table(table), confidence: 100),
            at: url
        )

        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "xl/sharedStrings.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("=1+1"))
        XCTAssertFalse(xml.contains("<f>1+1</f>"))
    }

    func testSpreadsheetTreatsNonFiniteNumericTextAsText() throws {
        let url = temporaryDirectory.appendingPathComponent("non-finite.xlsx")
        let table = TableData(rows: [["Value"], ["1e999"]], headerRows: [0])
        try FileGenerator().generate(
            ConversionCandidate(kind: .spreadsheet, payload: .table(table), confidence: 100),
            at: url
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "xl/sharedStrings.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("1e999"))
    }

    func testSpreadsheetRejectsEmbeddedNULBeforeWritingDestination() throws {
        let url = temporaryDirectory.appendingPathComponent("nul.xlsx")
        let sentinel = Data("existing file".utf8)
        try sentinel.write(to: url)
        let table = TableData(rows: [["Header", "Value"], ["Label", "before\0after"]], headerRows: [0])
        XCTAssertThrowsError(try SpreadsheetGenerator().generate(table, at: url))
        XCTAssertEqual(try Data(contentsOf: url), sentinel)

        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try SpreadsheetGenerator().generate(table, at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFilenameCollisionAddsSuffix() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let generator = FilenameGenerator(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US_POSIX"))
        let first = generator.filename(for: .text, at: date, in: temporaryDirectory) { _ in "Clipboard" }
        try Data().write(to: temporaryDirectory.appendingPathComponent(first))
        let second = generator.filename(for: .text, at: date, in: temporaryDirectory) { _ in "Clipboard" }
        XCTAssertEqual(second, first.replacingOccurrences(of: ".txt", with: " 2.txt"))
    }

    func testReservedDestinationsAreUniqueAndPrivate() throws {
        let cache = try CacheStore(directory: temporaryDirectory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try cache.reserveDestination(for: .text, at: date) { _ in "Clipboard" }
        let second = try cache.reserveDestination(for: .text, at: date) { _ in "Clipboard" }

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCleanupNeverDeletesFilesInsideMinimumRetention() throws {
        let cache = try CacheStore(directory: temporaryDirectory)
        let file = try cache.reserveDestination(for: .text, at: Date()) { _ in "Clipboard" }
        let oldDate = Date().addingTimeInterval(-(CacheStore.minimumRetention - 1))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        cache.cleanup(now: Date(), expirationAge: 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupDeletesExpiredFiles() throws {
        let cache = try CacheStore(directory: temporaryDirectory)
        let file = try cache.reserveDestination(for: .text, at: Date()) { _ in "Clipboard" }
        let now = Date()
        let oldDate = now.addingTimeInterval(-(CacheStore.expirationAge + 1))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        cache.cleanup(now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRestorationRequiresUnchangedPasteboard() {
        XCTAssertTrue(ClipboardRestorationPolicy.shouldRestore(currentChangeCount: 12, preparedChangeCount: 12))
        XCTAssertFalse(ClipboardRestorationPolicy.shouldRestore(currentChangeCount: 13, preparedChangeCount: 12))
    }
}
