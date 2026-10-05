import AppKit
import PasteAllCore

/// Checks GitHub Releases for a newer version. It only notifies: downloads go
/// through the browser or Homebrew, so PasteAll never replaces itself.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    static let repository = "86XIng/paste-all"
    static let caskToken = "paste-all"
    static var upgradeCommand: String { "brew upgrade --cask \(caskToken)" }

    private enum Key {
        static let automaticallyChecks = "automaticallyChecksForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedUpdateVersion"
        static let lastLaunchedBuild = "lastLaunchedBuild"
    }

    private static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: Key.automaticallyChecks) }
    }
    @Published private(set) var lastCheck: Date?
    @Published private(set) var isChecking = false

    private let defaults: UserDefaults
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.automaticallyChecks) == nil {
            defaults.set(true, forKey: Key.automaticallyChecks)
        }
        automaticallyChecks = defaults.bool(forKey: Key.automaticallyChecks)
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var currentBuild: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(currentVersion) (\(build))"
    }

    /// Records this launch's build and reports whether it differs from the
    /// previous launch, i.e. PasteAll was just updated.
    func recordLaunch() -> Bool {
        let previous = defaults.string(forKey: Key.lastLaunchedBuild)
        defaults.set(Self.currentBuild, forKey: Key.lastLaunchedBuild)
        return UpdateCheck.didUpdate(previousBuild: previous, currentBuild: Self.currentBuild)
    }

    func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateController.shared.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkIfDue()
        }
    }

    func checkNow() {
        check(userInitiated: true)
    }

    private func checkIfDue() {
        guard automaticallyChecks else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    private func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchLatestRelease()
                lastCheck = Date()
                defaults.set(lastCheck, forKey: Key.lastCheck)

                guard let release,
                      case .updateAvailable(let version, let info)? = UpdateCheck.evaluate(
                        currentVersion: Self.currentVersion,
                        release: release
                      )
                else {
                    if userInitiated { showUpToDate() }
                    return
                }
                if !userInitiated, defaults.string(forKey: Key.skippedVersion) == version.description { return }
                showUpdate(version: version, release: info)
            } catch {
                if userInitiated { showFailure() }
            }
        }
    }

    /// Returns nil when the repository has no published release yet.
    private func fetchLatestRelease() async throws -> ReleaseInfo? {
        guard let url = UpdateCheck.latestReleaseURL(repository: Self.repository) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PasteAll/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    private func showUpdate(version: AppVersion, release: ReleaseInfo) {
        let viaHomebrew = UpdateCheck.isHomebrewInstall(caskToken: Self.caskToken)
        let alert = NSAlert()
        alert.messageText = String.localizedStringWithFormat(
            String(localized: "update.available.title"),
            version.description
        )
        var details = String.localizedStringWithFormat(
            String(localized: "update.available.message"),
            Self.currentVersion
        )
        if viaHomebrew {
            details += "\n\n" + String(localized: "update.homebrew.message") + "\n" + Self.upgradeCommand
        }
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            details += "\n\n" + (notes.count > 600 ? String(notes.prefix(600)) + "…" : notes)
        }
        alert.informativeText = details
        alert.addButton(withTitle: String(localized: viaHomebrew ? "update.copyCommand" : "update.download"))
        if viaHomebrew { alert.addButton(withTitle: String(localized: "update.releaseNotes")) }
        alert.addButton(withTitle: String(localized: "update.later"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "update.skip")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(version.description, forKey: Key.skippedVersion)
        }
        if viaHomebrew {
            if response == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        } else if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.upToDate.title")
        alert.informativeText = String.localizedStringWithFormat(
            String(localized: "update.upToDate.message"),
            Self.currentVersion
        )
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "update.failed.title")
        alert.informativeText = String(localized: "update.failed.message")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
