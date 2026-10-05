import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func presentIfNeeded() {
        guard SettingsStore.shared.shouldShowOnboarding else { return }
        show()
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = OnboardingView(
            settings: .shared,
            accessibility: .shared,
            onComplete: { [weak self] in
                SettingsStore.shared.markOnboardingCompleted()
                self?.window?.close()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "onboarding.windowTitle")
        window.contentViewController = NSHostingController(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

private struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var accessibility: AccessibilityController
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionStep
                default: tryItStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 42)
            .padding(.vertical, 30)

            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
            Text("app.name")
                .font(.headline)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == step ? 24 : 8, height: 8)
                }
            }
            .accessibilityLabel(Text(verbatim: "\(step + 1) / 3"))
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                Text("app.marketingTitle")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("app.tagline")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(spacing: 12) {
                featureCard(icon: "photo", title: "onboarding.feature.image", detail: "PNG / JPEG")
                featureCard(icon: "doc.text", title: "onboarding.feature.text", detail: "TXT / MD")
                featureCard(icon: "tablecells", title: "onboarding.feature.table", detail: "XLSX")
                featureCard(icon: "link", title: "onboarding.feature.url", detail: "WEBLOC / URL")
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding.permission.title")
                    .font(.system(size: 25, weight: .bold))
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "onboarding.permission.subtitle"),
                        settings.pasteShortcut.displayName
                    )
                )
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Image(systemName: accessibility.isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(accessibility.isTrusted ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(accessibility.isTrusted ? "permission.granted" : "permission.missing")
                        .font(.headline)
                    Text(accessibility.isTrusted ? "onboarding.permission.ready" : "onboarding.permission.required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))

            if !accessibility.isTrusted {
                VStack(alignment: .leading, spacing: 11) {
                    instructionRow(number: 1, text: "onboarding.permission.step1")
                    instructionRow(number: 2, text: "onboarding.permission.step2")
                    instructionRow(number: 3, text: "onboarding.permission.step3")
                }

                HStack {
                    Button("permission.request") {
                        accessibility.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("permission.openSettings") {
                        accessibility.openSystemSettings()
                    }
                }
            }
        }
        .frame(maxWidth: 590)
    }

    private var tryItStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            VStack(spacing: 7) {
                Text("onboarding.try.title")
                    .font(.system(size: 26, weight: .bold))
                Text("onboarding.try.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 14) {
                tryCard(number: 1, icon: "doc.on.clipboard", text: "onboarding.try.copy")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                tryCard(number: 2, icon: "folder", text: "onboarding.try.finder")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                tryCard(
                    number: 3,
                    icon: "command",
                    verbatim: String.localizedStringWithFormat(
                        String(localized: "onboarding.try.paste"),
                        settings.pasteShortcut.displayName
                    )
                )
            }
            Text("onboarding.try.reopen")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("onboarding.back") { step -= 1 }
            }

            Spacer()

            if step == 1 && !accessibility.isTrusted {
                Button("onboarding.later") { onComplete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            if step == 2 {
                Button("onboarding.finish") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("onboarding.continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && !accessibility.isTrusted)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
    }

    private func featureCard(icon: String, title: LocalizedStringKey, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 94)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text)
        }
    }

    private func tryCard(number: Int, icon: String, text: LocalizedStringKey) -> some View {
        tryCardContent(number: number, icon: icon, text: Text(text))
    }

    // Deliberately not an overload of `tryCard(number:icon:text:)`: a bare string
    // literal defaults to `String`, so an overload would silently capture the
    // localized call sites above and render their raw keys.
    private func tryCard(number: Int, icon: String, verbatim text: String) -> some View {
        tryCardContent(number: number, icon: icon, text: Text(verbatim: text))
    }

    private func tryCardContent(number: Int, icon: String, text: Text) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 25))
                .foregroundStyle(.tint)
            text
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(width: 145, height: 105)
        .overlay(alignment: .topLeading) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(9)
        }
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}
