import AppKit
import PasteAllCore
import SwiftUI

@main
struct PasteAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var accessibility = AccessibilityController.shared
    @StateObject private var coordinator = PasteCoordinator.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                accessibility: accessibility,
                coordinator: coordinator
            )
        } label: {
            Label("app.name", systemImage: coordinator.isMonitoring ? "doc.on.clipboard.fill" : "doc.on.clipboard")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings, accessibility: accessibility)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PasteCoordinator.shared.refreshMonitoring()
        DispatchQueue.main.async {
            OnboardingWindowController.shared.presentIfNeeded()
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var accessibility: AccessibilityController
    @ObservedObject var coordinator: PasteCoordinator

    var body: some View {
        Toggle("menu.enabled", isOn: $settings.isEnabled)

        Picker("menu.mode", selection: $settings.detectionMode) {
            ForEach(DetectionMode.allCases, id: \.self) { mode in
                Text(mode.localizedLabel).tag(mode)
            }
        }

        Divider()

        if accessibility.isTrusted {
            Label("permission.granted", systemImage: "checkmark.shield.fill")
        } else {
            Button {
                accessibility.requestPermission()
            } label: {
                Label("permission.request", systemImage: "exclamationmark.shield")
            }
        }

        Button {
            OnboardingWindowController.shared.show()
        } label: {
            Label("menu.guide", systemImage: "questionmark.circle")
        }

        SettingsLink {
            Label("menu.settings", systemImage: "gear")
        }

        Divider()

        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var accessibility: AccessibilityController
    @State private var isRecordingShortcut = false

    var body: some View {
        Form {
            Section("settings.general") {
                Toggle("menu.enabled", isOn: $settings.isEnabled)
                Picker("menu.mode", selection: $settings.detectionMode) {
                    ForEach(DetectionMode.allCases, id: \.self) { mode in
                        Text(mode.localizedLabel).tag(mode)
                    }
                }
                Picker("settings.urlFormat", selection: $settings.shortcutFormat) {
                    Text("format.webloc").tag(URLShortcutFormat.webloc)
                    Text("format.url").tag(URLShortcutFormat.internetShortcut)
                }
                Toggle(
                    "settings.launchAtLogin",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: settings.setLaunchAtLogin
                    )
                )
                if let error = settings.loginItemError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }

            Section("settings.shortcut.section") {
                HStack {
                    Text("settings.shortcut")
                    Spacer()
                    ShortcutRecorder(
                        shortcut: $settings.pasteShortcut,
                        isRecording: $isRecordingShortcut
                    )
                    .frame(minWidth: 116)

                    if isRecordingShortcut {
                        Button("settings.shortcut.cancel") {
                            isRecordingShortcut = false
                        }
                    } else {
                        Button("settings.shortcut.reset") {
                            settings.resetShortcut()
                        }
                        .disabled(settings.pasteShortcut == .defaultShortcut)
                    }
                }

                Text("settings.shortcut.help")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                if settings.pasteShortcut != .defaultShortcut {
                    Label("settings.shortcut.warning", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("settings.permission") {
                HStack {
                    Label(
                        accessibility.isTrusted ? "permission.granted" : "permission.missing",
                        systemImage: accessibility.isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield"
                    )
                    Spacer()
                    if !accessibility.isTrusted {
                        Button("permission.request") { accessibility.requestPermission() }
                        Button("permission.openSettings") { accessibility.openSystemSettings() }
                    }
                }
                Text("permission.explanation")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section("settings.guide") {
                HStack {
                    Text("settings.guide.explanation")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("menu.guide") {
                        OnboardingWindowController.shared.show()
                    }
                }
            }

            Section("settings.privacy") {
                Text("privacy.explanation")
                    .foregroundStyle(.secondary)
            }

            Section("settings.licenses") {
                HStack {
                    Text("settings.licenses.explanation")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("SwiftSoup") {
                        openLicense(named: "SwiftSoup-LICENSE")
                    }
                    Button("libxlsxwriter") {
                        openLicense(named: "libxlsxwriter-LICENSE")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
        .navigationTitle("app.name")
    }

    private func openLicense(named resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension DetectionMode {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .strict: "mode.strict"
        case .aggressive: "mode.aggressive"
        case .askEveryTime: "mode.ask"
        }
    }
}
