import AppKit
import CoreGraphics
import Foundation

private let pasteAllSyntheticEventMarker: Int64 = 0x5041535445414C4C
@MainActor
final class FinderPasteEventTap {
    var onFinderPaste: (() -> Bool)?
    var shortcutProvider: (() -> PasteShortcut)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<FinderPasteEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return owner.handle(type: type, event: event)
            },
            userInfo: pointer
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                guard let tap = self?.tap else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != pasteAllSyntheticEventMarker,
              let shortcut = MainActor.assumeIsolated({ shortcutProvider?() }),
              shortcut.matches(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                eventFlags: event.flags
              ),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        else { return Unmanaged.passUnretained(event) }

        let intercepted = MainActor.assumeIsolated { onFinderPaste?() ?? false }
        return intercepted ? nil : Unmanaged.passUnretained(event)
    }

    /// Replays Finder's paste command once the user's shortcut modifiers are out
    /// of the way, then reports whether the events were posted.
    ///
    /// Events injected at the HID tap are combined with the modifier keys that
    /// are physically held, so posting ⌘V while a custom shortcut such as ⌥⌘V is
    /// still down reaches Finder as ⌥⌘V — "Move Item Here", which relocates the
    /// prepared file instead of copying it. Holding only ⌘ merges to exactly the
    /// chord we want, so the common case still posts immediately.
    static func postPaste(completion: @escaping @MainActor (Bool) -> Void) {
        waitForExtraModifierRelease(deadline: Date() + modifierReleaseTimeout) {
            completion(postCommandV())
        }
    }

    private static let modifierReleaseTimeout: TimeInterval = 0.5
    private static let modifierPollInterval: TimeInterval = 0.02

    private static func waitForExtraModifierRelease(
        deadline: Date,
        then body: @escaping @MainActor () -> Void
    ) {
        let held = PasteShortcut.Modifiers(eventFlags: NSEvent.modifierFlags)
        guard !held.subtracting(.command).isEmpty, Date() < deadline else {
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + modifierPollInterval) {
            MainActor.assumeIsolated {
                waitForExtraModifierRelease(deadline: deadline, then: body)
            }
        }
    }

    @discardableResult
    static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return false }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: pasteAllSyntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
