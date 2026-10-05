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
