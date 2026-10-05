public enum OnboardingProgress {
    public static let currentVersion = 1
    public static let defaultsKey = "onboardingVersion"

    public static func shouldPresent(storedVersion: Int) -> Bool {
        storedVersion < currentVersion
    }
}
