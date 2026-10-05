import AppKit
import XCTest
@testable import PasteAll

@MainActor
final class FinderPasteReceiverTests: XCTestCase {
    private let request = FinderPasteRequest(containerPath: "/tmp", selectedPaths: [], choosesFormat: false)
    private let testToken = Data([1, 2, 3])

    func testColdLaunchQueuesAuthenticatedRequestUntilReadyExactlyOnce() {
        var delivered: [FinderPasteRequest] = []
        let receiver = FinderPasteReceiver(authenticate: { $0 == self.testToken }) { delivered.append($0) }
        receiver.receive(urlString: request.url?.absoluteString, auditToken: testToken)
        XCTAssertTrue(receiver.receivedLaunchRequest)
        XCTAssertTrue(delivered.isEmpty)
        receiver.finishLaunching()
        receiver.finishLaunching()
        XCTAssertEqual(delivered, [request])
    }

    func testWarmRequestDoesNotDependOnForegroundApp() {
        var delivered: [FinderPasteRequest] = []
        let receiver = FinderPasteReceiver(authenticate: { $0 == self.testToken }) { delivered.append($0) }
        receiver.finishLaunching()
        receiver.receive(urlString: request.url?.absoluteString, auditToken: testToken)
        XCTAssertEqual(delivered, [request])
    }

    func testMissingAndUntrustedSendersCannotQueueOrDeliver() {
        let receiver = FinderPasteReceiver(authenticate: { _ in false }) { _ in XCTFail("Untrusted request delivered") }
        receiver.receive(urlString: request.url?.absoluteString, auditToken: nil)
        receiver.receive(urlString: request.url?.absoluteString, auditToken: testToken)
        XCTAssertFalse(receiver.receivedLaunchRequest)
        receiver.finishLaunching()
        receiver.receive(urlString: request.url?.absoluteString, auditToken: testToken)
    }

    func testMalformedURLDoesNotSuppressLaunchUI() {
        let receiver = FinderPasteReceiver(authenticate: { _ in true }) { _ in XCTFail("Malformed request delivered") }
        receiver.receive(urlString: "pasteall-finder://paste?request=invalid", auditToken: testToken)
        XCTAssertFalse(receiver.receivedLaunchRequest)
    }

    func testAuthenticationFailsClosedForInvalidTokenOrMissingExtension() {
        let missing = URL(fileURLWithPath: "/nonexistent/PasteAllFinderExtension.appex")
        XCTAssertFalse(FinderPasteSenderAuthentication.accepts(Data(), extensionURL: missing))
        XCTAssertFalse(FinderPasteSenderAuthentication.accepts(
            Data(repeating: 0, count: MemoryLayout<audit_token_t>.size), extensionURL: missing
        ))
    }
}
