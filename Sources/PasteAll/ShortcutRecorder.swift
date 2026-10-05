import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: PasteShortcut
    @Binding var isRecording: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, isRecording: $isRecording)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onStartRecording = { context.coordinator.isRecording.wrappedValue = true }
        button.onRecord = { recordedShortcut in
            context.coordinator.shortcut.wrappedValue = recordedShortcut
            context.coordinator.isRecording.wrappedValue = false
        }
        button.onCancel = { context.coordinator.isRecording.wrappedValue = false }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.isRecordingShortcut = isRecording
        button.updatePresentation()

        if isRecording, button.window?.firstResponder !== button {
            DispatchQueue.main.async {
                button.window?.makeFirstResponder(button)
            }
        }
    }

    final class Coordinator {
        var shortcut: Binding<PasteShortcut>
        var isRecording: Binding<Bool>

        init(shortcut: Binding<PasteShortcut>, isRecording: Binding<Bool>) {
            self.shortcut = shortcut
            self.isRecording = isRecording
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut = PasteShortcut.defaultShortcut
    var isRecordingShortcut = false
    var onStartRecording: (() -> Void)?
    var onRecord: ((PasteShortcut) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        controlSize = .regular
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func beginRecording() {
        onStartRecording?()
        window?.makeFirstResponder(self)
        updatePresentation()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecordingShortcut else {
            return super.performKeyEquivalent(with: event)
        }
        record(event)
        return true
    }

    private static let escapeKeyCode: UInt16 = 53

    private func record(_ event: NSEvent) {
        // Unmodified Escape is the standard "back out of recording" gesture, so
        // it must never bind itself as the shortcut.
        let heldModifiers = PasteShortcut.Modifiers(eventFlags: event.modifierFlags)
        if event.keyCode == Self.escapeKeyCode, heldModifiers.isEmpty {
            cancelRecording()
            return
        }

        guard let shortcut = PasteShortcut(event: event) else {
            NSSound.beep()
            return
        }
        onRecord?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func cancelRecording() {
        onCancel?()
        isRecordingShortcut = false
        updatePresentation()
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isRecordingShortcut {
            onCancel?()
        }
        return resigned
    }

    func updatePresentation() {
        title = isRecordingShortcut
            ? String(localized: "settings.shortcut.recording")
            : shortcut.displayName
        toolTip = String(localized: "settings.shortcut.recordHelp")
        setAccessibilityLabel(String(localized: "settings.shortcut"))
        setAccessibilityValue(shortcut.displayName)
        invalidateIntrinsicContentSize()
    }

    /// Both presentation states have to fit, otherwise the localized "type
    /// shortcut" prompt is truncated for as long as recording is in progress and
    /// the control jumps width when it ends. Derive the bezel padding from the
    /// current title so the floor stays correct across fonts and locales.
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let width = { (text: String) in
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let padding = max(size.width - width(title), 0)
        let widestTitle = max(
            width(String(localized: "settings.shortcut.recording")),
            width(shortcut.displayName)
        )
        return NSSize(width: max(size.width, ceil(widestTitle + padding)), height: size.height)
    }
}
