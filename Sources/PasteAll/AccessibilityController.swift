import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AccessibilityController: ObservableObject {
    static let shared = AccessibilityController()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// macOS ties the approval to the exact code signature, so after an update
    /// of an ad-hoc signed build the System Settings switch can look enabled
    /// while no longer applying. Clearing our own entry first makes the system
    /// prompt and list PasteAll again, leaving the user a single switch to flip.
    func requestPermission() {
        if !AXIsProcessTrusted() { resetStaleApproval() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        refresh()
    }

    private func resetStaleApproval() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The prompt below still works when no stale entry exists.
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
