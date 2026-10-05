import AppKit
import FinderSync

/// Tracks whether the Finder Sync extension that adds the context menu items
/// is enabled, and turns it on for the user where macOS allows it.
@MainActor
final class FinderExtensionController: ObservableObject {
    static let shared = FinderExtensionController()

    @Published private(set) var isEnabled = FIFinderSyncController.isExtensionEnabled

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { FinderExtensionController.shared.refresh() }
        }
    }

    func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    /// Registers and enables the bundled extension directly; if macOS still
    /// reports it disabled, falls back to the system's extension settings.
    func enable() {
        if let extensionURL, let identifier = extensionIdentifier {
            runPluginKit(["-a", extensionURL.path])
            runPluginKit(["-e", "use", "-i", identifier])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            refresh()
            if !isEnabled { FIFinderSyncController.showExtensionManagementInterface() }
        }
    }

    private var extensionIdentifier: String? {
        Bundle.main.bundleIdentifier.map { $0 + FinderPasteRequest.extensionBundleSuffix }
    }

    private var extensionURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("PasteAllFinderExtension.appex")
    }

    private func runPluginKit(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The system settings fallback in enable() covers this.
        }
    }
}
