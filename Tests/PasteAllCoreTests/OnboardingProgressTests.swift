import XCTest
@testable import PasteAllCore

final class OnboardingProgressTests: XCTestCase {
    func testFirstLaunchPresentsOnboarding() {
        XCTAssertTrue(OnboardingProgress.shouldPresent(storedVersion: 0))
    }

    func testCompletedCurrentVersionDoesNotPresentOnboarding() {
        XCTAssertFalse(
            OnboardingProgress.shouldPresent(storedVersion: OnboardingProgress.currentVersion)
        )
    }

    func testOlderOnboardingVersionPresentsAgain() {
        XCTAssertTrue(
            OnboardingProgress.shouldPresent(storedVersion: OnboardingProgress.currentVersion - 1)
        )
    }

    func testNewerStoredVersionDoesNotRegress() {
        XCTAssertFalse(
            OnboardingProgress.shouldPresent(storedVersion: OnboardingProgress.currentVersion + 1)
        )
    }
}
