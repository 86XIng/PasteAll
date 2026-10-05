import AppKit
import XCTest
@testable import PasteAll

@MainActor
final class CandidatePickerTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 949)
    private let size = NSSize(width: 300, height: 120)

    func testBottomRightCornerSitsAtPointer() {
        let origin = CandidatePicker.origin(for: size, at: NSPoint(x: 600, y: 400), within: screen)
        XCTAssertEqual(origin, NSPoint(x: 300, y: 400))
    }

    func testFlipsBelowNearTopEdge() {
        let origin = CandidatePicker.origin(for: size, at: NSPoint(x: 600, y: 900), within: screen)
        XCTAssertEqual(origin, NSPoint(x: 300, y: 780))
    }

    func testFlipsRightNearLeftEdge() {
        let origin = CandidatePicker.origin(for: size, at: NSPoint(x: 100, y: 400), within: screen)
        XCTAssertEqual(origin, NSPoint(x: 100, y: 400))
    }

    func testStaysOnSecondaryScreenWithNegativeCoordinates() {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = CandidatePicker.origin(for: size, at: NSPoint(x: -1000, y: 500), within: left)
        XCTAssertEqual(origin, NSPoint(x: -1300, y: 500))
    }
}
