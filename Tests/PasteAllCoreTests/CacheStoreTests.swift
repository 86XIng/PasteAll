import Foundation
import XCTest
@testable import PasteAllCore

final class CacheStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteAllReserve-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReservationsInTheSameSecondGetDistinctNames() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try CacheStore.reserveFile(for: .png, in: directory, at: date, permissions: 0o644) { _ in "Image" }
        let second = try CacheStore.reserveFile(for: .png, in: directory, at: date, permissions: 0o644) { _ in "Image" }

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(second.lastPathComponent.hasSuffix(" 2.png"))
    }

    func testReservationUsesRequestedPermissions() throws {
        let url = try CacheStore.reserveFile(for: .text, in: directory, permissions: 0o644) { _ in "Clipboard" }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
    }

    func testMissingDirectoryReportsDestinationError() {
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(
            try CacheStore.reserveFile(for: .text, in: missing, permissions: 0o644) { _ in "Clipboard" }
        ) { error in
            XCTAssertEqual(error as? PasteAllError, .cannotWriteDestination)
        }
    }
}
