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
    /// Extra physical modifiers can change the intended paste command, so wait
    /// for release or cancel on timeout. Deliver both events to the validated
    /// Finder process so a subsequent focus switch cannot redirect the paste.
    static func postPaste(
        isValid: @escaping @MainActor () -> Bool,
        modifiers: @escaping @MainActor () -> PasteShortcut.Modifiers = {
            PasteShortcut.Modifiers(eventFlags: NSEvent.modifierFlags)
        },
        frontmostApplication: @escaping @MainActor () -> (bundleIdentifier: String?, processIdentifier: pid_t)? = {
            guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
            return (application.bundleIdentifier, application.processIdentifier)
        },
        post: @escaping @MainActor (pid_t) -> Bool = { postCommandV(to: $0) },
        timeout: TimeInterval = 0.5,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        func attempt() {
            guard isValid(), let target = frontmostApplication(),
                  target.bundleIdentifier == "com.apple.finder" else {
                completion(false)
                return
            }
            if modifiers().subtracting(.command).isEmpty {
                completion(post(target.processIdentifier))
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    attempt()
                }
            }
        }
        attempt()
    }

    @discardableResult
    private static func postCommandV(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else { return false }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: pasteAllSyntheticEventMarker)
            event.postToPid(processIdentifier)
        }
        return true
    }
}
