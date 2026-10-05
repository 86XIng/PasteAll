import CoreGraphics
import XCTest
@testable import PasteAll

final class PasteShortcutTests: XCTestCase {
    func testDefaultShortcutIsCommandV() {
        XCTAssertEqual(PasteShortcut.defaultShortcut.keyCode, 9)
        XCTAssertEqual(PasteShortcut.defaultShortcut.modifiers, [.command])
        XCTAssertEqual(PasteShortcut.defaultShortcut.displayName, "⌘V")
    }

    func testEncodingRoundTrip() throws {
        let shortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 9, modifiers: [.command, .shift], keyDisplay: "V")
        )

        let data = try JSONEncoder().encode(shortcut)

        XCTAssertEqual(try JSONDecoder().decode(PasteShortcut.self, from: data), shortcut)
    }

    func testDecodingRejectsModifierOnlyShortcut() throws {
        let data = Data(
            #"{"keyCode":55,"modifiers":{"rawValue":1},"keyDisplay":"Command"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(PasteShortcut.self, from: data))
    }

    func testDecodingRejectsControlCharactersInDisplayName() {
        let data = Data(
            #"{"keyCode":9,"modifiers":{"rawValue":1},"keyDisplay":"V\n"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(PasteShortcut.self, from: data))
    }

    func testMatchesExactSupportedModifiers() throws {
        let shortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 9, modifiers: [.command, .shift], keyDisplay: "V")
        )

        XCTAssertTrue(shortcut.matches(keyCode: 9, modifiers: [.command, .shift]))
        XCTAssertFalse(shortcut.matches(keyCode: 9, modifiers: [.command]))
        XCTAssertFalse(shortcut.matches(keyCode: 9, modifiers: [.command, .shift, .option]))
    }

    func testCapsLockDoesNotAffectMatching() {
        XCTAssertTrue(
            PasteShortcut.defaultShortcut.matches(
                keyCode: 9,
                eventFlags: [.maskCommand, .maskAlphaShift]
            )
        )
    }

    func testShiftOnlyAndUnmodifiedShortcutsAreRejected() {
        // Without ⌘/⌥/⌃ the tap would swallow ordinary Finder keystrokes such as
        // Space (Quick Look), type-select navigation, and inline rename typing.
        XCTAssertNil(PasteShortcut(keyCode: 9, modifiers: [.shift], keyDisplay: "V"))
        XCTAssertNil(PasteShortcut(keyCode: 9, modifiers: [], keyDisplay: "V"))
        XCTAssertNil(PasteShortcut(keyCode: 49, modifiers: [], keyDisplay: "Space"))
    }

    func testDecodingRejectsShortcutWithoutRequiredModifier() {
        let data = Data(
            #"{"keyCode":49,"modifiers":{"rawValue":2},"keyDisplay":"Space"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(PasteShortcut.self, from: data))
    }

    func testOptionAndControlAloneAreAcceptedModifiers() throws {
        XCTAssertNotNil(PasteShortcut(keyCode: 9, modifiers: [.option], keyDisplay: "V"))
        XCTAssertNotNil(PasteShortcut(keyCode: 9, modifiers: [.control], keyDisplay: "V"))
    }

    func testDisplayNameFallsBackToStoredKeyDisplay() throws {
        // Key code 10 (§/± on ANSI) has no entry in the special-key table, so the
        // label comes from the active layout or, failing that, what was recorded.
        let shortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 10, modifiers: [.command], keyDisplay: "§")
        )

        XCTAssertTrue(shortcut.displayName.hasPrefix("⌘"))
        XCTAssertFalse(shortcut.displayName.dropFirst().isEmpty)
    }

    func testSpecialKeyDisplayIgnoresStoredLabel() throws {
        let shortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 49, modifiers: [.command], keyDisplay: "stale")
        )

        XCTAssertEqual(shortcut.displayName, "⌘Space")
    }
}

@MainActor
final class FinderPasteReplayTests: XCTestCase {
    func testPostsWhenOnlyCommandIsHeld() {
        var posted = false
        FinderPasteEventTap.postPaste(
            isValid: { true }, modifiers: { [.command] },
            frontmostApplication: { ("com.apple.finder", 42) },
            post: { pid in XCTAssertEqual(pid, 42); posted = true; return true }
        ) { XCTAssertTrue($0) }
        XCTAssertTrue(posted)
    }

    func testRejectsAnotherForegroundApp() {
        FinderPasteEventTap.postPaste(
            isValid: { true }, modifiers: { [] },
            frontmostApplication: { ("com.apple.TextEdit", 99) },
            post: { _ in XCTFail("Must not paste into another app"); return true }
        ) { XCTAssertFalse($0) }
    }

    func testHeldExtraModifierTimesOutWithoutPosting() {
        FinderPasteEventTap.postPaste(
            isValid: { true }, modifiers: { [.command, .option] },
            frontmostApplication: { ("com.apple.finder", 42) },
            post: { _ in XCTFail("Must not post with Option held"); return true },
            timeout: 0
        ) { XCTAssertFalse($0) }
    }

    func testRechecksClipboardValidityAfterWaiting() async {
        let finished = expectation(description: "Cancelled changed clipboard")
        var valid = true
        FinderPasteEventTap.postPaste(
            isValid: { valid },
            modifiers: { valid = false; return [.option] },
            frontmostApplication: { ("com.apple.finder", 42) },
            post: { _ in XCTFail("Must not paste a changed clipboard"); return true }
        ) {
            XCTAssertFalse($0)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
    }

    func testRechecksForegroundAfterWaiting() async {
        let finished = expectation(description: "Cancelled app switch")
        var foreground = "com.apple.finder"
        FinderPasteEventTap.postPaste(
            isValid: { true },
            modifiers: { foreground = "com.apple.TextEdit"; return [.option] },
            frontmostApplication: { (foreground, 42) },
            post: { _ in XCTFail("Must not paste after app switch"); return true }
        ) {
            XCTAssertFalse($0)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
    }

    func testPostsAfterExtraModifierIsReleased() async {
        let finished = expectation(description: "Posted after release")
        var held: PasteShortcut.Modifiers = [.option]
        var count = 0
        FinderPasteEventTap.postPaste(
            isValid: { true },
            modifiers: { let current = held; held = []; return current },
            frontmostApplication: { ("com.apple.finder", 42) },
            post: { pid in XCTAssertEqual(pid, 42); count += 1; return true }
        ) {
            XCTAssertTrue($0)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(count, 1)
    }
}
