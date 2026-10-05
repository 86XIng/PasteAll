import XCTest
@testable import PasteAll

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMissingShortcutUsesDefault() {
        XCTAssertEqual(SettingsStore(defaults: defaults).pasteShortcut, .defaultShortcut)
    }

    func testShortcutPersistsAcrossStores() throws {
        let customShortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 9, modifiers: [.command, .shift], keyDisplay: "V")
        )
        let store = SettingsStore(defaults: defaults)

        store.pasteShortcut = customShortcut

        XCTAssertEqual(SettingsStore(defaults: defaults).pasteShortcut, customShortcut)
    }

    func testCorruptShortcutFallsBackToDefault() {
        defaults.set(Data("not-json".utf8), forKey: "pasteShortcut")

        XCTAssertEqual(SettingsStore(defaults: defaults).pasteShortcut, .defaultShortcut)
    }

    func testResetRestoresAndPersistsDefault() throws {
        let store = SettingsStore(defaults: defaults)
        store.pasteShortcut = try XCTUnwrap(
            PasteShortcut(keyCode: 49, modifiers: [.control, .option], keyDisplay: "Space")
        )

        store.resetShortcut()

        XCTAssertEqual(store.pasteShortcut, .defaultShortcut)
        XCTAssertEqual(SettingsStore(defaults: defaults).pasteShortcut, .defaultShortcut)
    }
}
