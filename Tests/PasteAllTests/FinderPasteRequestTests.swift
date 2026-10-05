import Foundation
import XCTest
@testable import PasteAll

@MainActor
final class FinderPasteRequestTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteAllFinder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tool.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("note.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRequestSurvivesEncoding() throws {
        let request = FinderPasteRequest(containerPath: "/tmp", selectedPaths: ["/tmp/a b"], choosesFormat: true)
        let encoded = try XCTUnwrap(request.encoded)
        XCTAssertEqual(FinderPasteRequest(encoded: encoded), request)
        XCTAssertNil(FinderPasteRequest(encoded: "not json"))
    }

    func testContainerIsUsedForBackgroundClicks() {
        let request = FinderPasteRequest(containerPath: root.path, selectedPaths: [], choosesFormat: false)
        XCTAssertEqual(PasteCoordinator.destinationDirectory(for: request)?.path, root.standardizedFileURL.path)
    }

    func testSingleSelectedFolderIsTheDestination() {
        let folder = root.appendingPathComponent("Folder").path
        let request = FinderPasteRequest(containerPath: root.path, selectedPaths: [folder], choosesFormat: false)
        XCTAssertEqual(PasteCoordinator.destinationDirectory(for: request)?.lastPathComponent, "Folder")
    }

    func testSelectedFilesAndPackagesFallBackToContainer() {
        for name in ["note.txt", "Tool.app"] {
            let request = FinderPasteRequest(
                containerPath: root.path,
                selectedPaths: [root.appendingPathComponent(name).path],
                choosesFormat: false
            )
            XCTAssertEqual(PasteCoordinator.destinationDirectory(for: request)?.path, root.standardizedFileURL.path)
        }
    }

    func testRelativeOrMissingPathsAreRejected() {
        XCTAssertNil(PasteCoordinator.destinationDirectory(
            for: FinderPasteRequest(containerPath: "relative/path", selectedPaths: [], choosesFormat: false)
        ))
        XCTAssertNil(PasteCoordinator.destinationDirectory(
            for: FinderPasteRequest(containerPath: root.appendingPathComponent("missing").path, selectedPaths: [], choosesFormat: false)
        ))
    }

    func testItemMenuUsesClickedFileParent() {
        for name in ["note.txt", "Tool.app"] {
            let item = root.appendingPathComponent(name)
            let request = FinderPasteRequest(
                targetedURL: item, selectedURLs: [item], isItemMenu: true, choosesFormat: false
            )
            XCTAssertEqual(PasteCoordinator.destinationDirectory(for: request)?.path, root.standardizedFileURL.path)
        }
    }

    func testItemMenuPreservesFolderAndMultipleSelectionBehavior() {
        let folder = root.appendingPathComponent("Folder")
        let file = root.appendingPathComponent("note.txt")
        let single = FinderPasteRequest(
            targetedURL: folder, selectedURLs: [folder], isItemMenu: true, choosesFormat: true
        )
        XCTAssertEqual(PasteCoordinator.destinationDirectory(for: single)?.path, folder.standardizedFileURL.path)
        let multiple = FinderPasteRequest(
            targetedURL: file, selectedURLs: [folder, file], isItemMenu: true, choosesFormat: false
        )
        XCTAssertTrue(multiple.selectedPaths.isEmpty)
        XCTAssertEqual(PasteCoordinator.destinationDirectory(for: multiple)?.path, root.standardizedFileURL.path)
    }

    func testBackgroundMenuIgnoresSelection() {
        let request = FinderPasteRequest(
            targetedURL: root, selectedURLs: [root.appendingPathComponent("Folder")],
            isItemMenu: false, choosesFormat: false
        )
        XCTAssertTrue(request.selectedPaths.isEmpty)
        XCTAssertEqual(PasteCoordinator.destinationDirectory(for: request)?.path, root.standardizedFileURL.path)
    }

    func testURLRoundTripPreservesSpecialCharacters() throws {
        let request = FinderPasteRequest(
            containerPath: "/tmp/中文 & # ? % +", selectedPaths: ["/tmp/a\nb"], choosesFormat: true
        )
        XCTAssertEqual(FinderPasteRequest(url: try XCTUnwrap(request.url)), request)
        XCTAssertNil(FinderPasteRequest(url: URL(string: "https://paste?request=x")!))
        XCTAssertNil(FinderPasteRequest(url: URL(string: "pasteall-finder://paste?request=bad")!))
    }
}
