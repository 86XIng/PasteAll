import Foundation
import PasteAllCore
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let enabled = "enabled"
        static let detectionMode = "detectionMode"
        static let shortcutFormat = "shortcutFormat"
        static let pasteShortcut = "pasteShortcut"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }

    @Published var detectionMode: DetectionMode {
        didSet { defaults.set(detectionMode.rawValue, forKey: Key.detectionMode) }
    }

    @Published var shortcutFormat: URLShortcutFormat {
        didSet { defaults.set(shortcutFormat.rawValue, forKey: Key.shortcutFormat) }
    }

    @Published var pasteShortcut: PasteShortcut {
        didSet { persistPasteShortcut() }
    }

    @Published private(set) var loginItemError: String?
    @Published private(set) var shouldShowOnboarding: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.enabled) == nil {
            defaults.set(true, forKey: Key.enabled)
        }
        isEnabled = defaults.bool(forKey: Key.enabled)
        detectionMode = DetectionMode(
            rawValue: defaults.string(forKey: Key.detectionMode) ?? ""
        ) ?? .aggressive
        shortcutFormat = URLShortcutFormat(
            rawValue: defaults.string(forKey: Key.shortcutFormat) ?? ""
        ) ?? .webloc
        pasteShortcut = Self.loadPasteShortcut(from: defaults)
        shouldShowOnboarding = OnboardingProgress.shouldPresent(
            storedVersion: defaults.integer(forKey: OnboardingProgress.defaultsKey)
        )
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
            objectWillChange.send()
        } catch {
            loginItemError = error.localizedDescription
        }
    }

    func markOnboardingCompleted() {
        defaults.set(OnboardingProgress.currentVersion, forKey: OnboardingProgress.defaultsKey)
        shouldShowOnboarding = false
    }

    func resetShortcut() {
        pasteShortcut = .defaultShortcut
    }

    private func persistPasteShortcut() {
        guard let data = try? JSONEncoder().encode(pasteShortcut) else { return }
        defaults.set(data, forKey: Key.pasteShortcut)
    }

    private static func loadPasteShortcut(from defaults: UserDefaults) -> PasteShortcut {
        guard let data = defaults.data(forKey: Key.pasteShortcut),
              let shortcut = try? JSONDecoder().decode(PasteShortcut.self, from: data)
        else { return .defaultShortcut }
        return shortcut
    }
}
