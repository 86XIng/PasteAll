import Foundation
import XCTest
@testable import PasteAllCore

final class UpdateCheckTests: XCTestCase {
    private let page = URL(string: "https://github.com/86XIng/PasteAll/releases/tag/v1.2.0")!

    func testVersionParsingAcceptsTagsAndIgnoresSuffixes() throws {
        XCTAssertEqual(try XCTUnwrap(AppVersion("v1.2.3")).components, [1, 2, 3])
        XCTAssertEqual(try XCTUnwrap(AppVersion("1.2.0-beta.1")).components, [1, 2, 0])
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion("+1.2"))
    }

    func testVersionComparisonPadsMissingComponents() throws {
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.9")), try XCTUnwrap(AppVersion("1.10")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.1.0")), try XCTUnwrap(AppVersion("0.1.1")))
    }

    func testNewerReleaseIsOffered() {
        let release = ReleaseInfo(tagName: "v1.2.0", pageURL: page)
        XCTAssertEqual(
            UpdateCheck.evaluate(currentVersion: "1.1.9", release: release),
            .updateAvailable(AppVersion("1.2.0")!, release)
        )
    }

    func testSameOrOlderReleaseIsUpToDate() {
        XCTAssertEqual(
            UpdateCheck.evaluate(currentVersion: "1.2", release: ReleaseInfo(tagName: "v1.2.0", pageURL: page)),
            .upToDate
        )
        XCTAssertEqual(
            UpdateCheck.evaluate(currentVersion: "2.0.0", release: ReleaseInfo(tagName: "v1.2.0", pageURL: page)),
            .upToDate
        )
    }

    func testPrereleaseIsIgnored() {
        let release = ReleaseInfo(tagName: "v9.0.0", pageURL: page, isPrerelease: true)
        XCTAssertEqual(UpdateCheck.evaluate(currentVersion: "1.0.0", release: release), .upToDate)
    }

    func testReleasePageOutsideGitHubIsRejected() {
        let release = ReleaseInfo(tagName: "v9.0.0", pageURL: URL(string: "https://example.com/download")!)
        XCTAssertNil(UpdateCheck.evaluate(currentVersion: "1.0.0", release: release))
    }

    func testDecodesGitHubReleaseJSON() throws {
        let json = """
        {"tag_name": "v1.3.0", "html_url": "https://github.com/86XIng/PasteAll/releases/tag/v1.3.0",
         "body": null, "draft": false, "prerelease": false, "assets": []}
        """
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(release.tagName, "v1.3.0")
        XCTAssertEqual(release.notes, "")
        XCTAssertFalse(release.isPrerelease)
    }

    func testFirstLaunchIsNotAnUpdate() {
        XCTAssertFalse(UpdateCheck.didUpdate(previousBuild: nil, currentBuild: "1.0 (1)"))
        XCTAssertFalse(UpdateCheck.didUpdate(previousBuild: "1.0 (1)", currentBuild: "1.0 (1)"))
        XCTAssertTrue(UpdateCheck.didUpdate(previousBuild: "1.0 (1)", currentBuild: "1.1 (2)"))
    }

    func testHomebrewInstallIsDetectedFromCaskroom() throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteAllBrew-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }

        XCTAssertFalse(UpdateCheck.isHomebrewInstall(caskToken: "paste-all", prefixes: [prefix.path]))
        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("Caskroom/paste-all"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(UpdateCheck.isHomebrewInstall(caskToken: "paste-all", prefixes: [prefix.path]))
    }
}
