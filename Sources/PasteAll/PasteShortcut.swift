import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct PasteShortcut: Codable, Equatable, Sendable {
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)

        static let supportedMask: Modifiers = [.command, .shift, .option, .control]

        /// Shift alone only changes the character a key produces, so it cannot
        /// stand in for a shortcut modifier — at least one of these is required.
        static let requiredMask: Modifiers = [.command, .option, .control]

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        init(eventFlags: NSEvent.ModifierFlags) {
            var modifiers: Modifiers = []
            if eventFlags.contains(.command) { modifiers.insert(.command) }
            if eventFlags.contains(.shift) { modifiers.insert(.shift) }
            if eventFlags.contains(.option) { modifiers.insert(.option) }
            if eventFlags.contains(.control) { modifiers.insert(.control) }
            self = modifiers
        }

        init(eventFlags: CGEventFlags) {
            var modifiers: Modifiers = []
            if eventFlags.contains(.maskCommand) { modifiers.insert(.command) }
            if eventFlags.contains(.maskShift) { modifiers.insert(.shift) }
            if eventFlags.contains(.maskAlternate) { modifiers.insert(.option) }
            if eventFlags.contains(.maskControl) { modifiers.insert(.control) }
            self = modifiers
        }
    }

    static let defaultShortcut = PasteShortcut(
        keyCode: 9,
        modifiers: [.command],
        keyDisplay: "V"
    )!

    let keyCode: UInt16
    let modifiers: Modifiers
    let keyDisplay: String

    var displayName: String {
        var result = ""
        if modifiers.contains(.command) { result += "⌘" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.control) { result += "⌃" }
        return result + currentKeyDisplay
    }

    /// Matching is by key code, so the stored `keyDisplay` goes stale as soon as
    /// the keyboard layout changes. Resolve the label against the active layout
    /// and fall back to what was captured at record time.
    var currentKeyDisplay: String {
        Self.keyCodeDisplays[keyCode] ?? Self.layoutDisplay(for: keyCode) ?? keyDisplay
    }

    init?(keyCode: UInt16, modifiers: Modifiers, keyDisplay: String) {
        let normalizedDisplay = keyDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.modifierKeyCodes.contains(keyCode),
              !normalizedDisplay.isEmpty,
              normalizedDisplay.count <= 12,
              normalizedDisplay.rangeOfCharacter(from: .controlCharacters) == nil,
              modifiers.subtracting(.supportedMask).isEmpty,
              !modifiers.intersection(.requiredMask).isEmpty
        else { return nil }

        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplay = normalizedDisplay
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let keyCode = event.keyCode
        let display = Self.keyDisplay(for: event)
        self.init(
            keyCode: keyCode,
            modifiers: Modifiers(eventFlags: event.modifierFlags),
            keyDisplay: display
        )
    }

    func matches(keyCode: UInt16, modifiers: Modifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers.intersection(.supportedMask)
    }

    func matches(keyCode: Int64, eventFlags: CGEventFlags) -> Bool {
        guard let keyCode = UInt16(exactly: keyCode) else { return false }
        return matches(keyCode: keyCode, modifiers: Modifiers(eventFlags: eventFlags))
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case keyDisplay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let modifiers = try container.decode(Modifiers.self, forKey: .modifiers)
        let keyDisplay = try container.decode(String.self, forKey: .keyDisplay)
        guard let shortcut = PasteShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            keyDisplay: keyDisplay
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .keyCode,
                in: container,
                debugDescription: "Invalid paste shortcut"
            )
        }
        self = shortcut
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, // Command
        56, 60, // Shift
        57,     // Caps Lock
        58, 61, // Option
        59, 62, // Control
        63      // Function
    ]

    private static func keyDisplay(for event: NSEvent) -> String {
        if let specialKey = event.specialKey,
           let display = specialKeyDisplays[specialKey] {
            return display
        }

        if let characters = event.charactersIgnoringModifiers,
           !characters.isEmpty,
           characters.rangeOfCharacter(from: .controlCharacters) == nil {
            return characters.uppercased()
        }

        return keyCodeDisplays[event.keyCode] ?? "Key \(event.keyCode)"
    }

    /// The character the current keyboard layout produces for `keyCode`, with no
    /// modifiers applied. Returns nil for layouts without Unicode key data (some
    /// input methods) and for keys that produce nothing printable.
    private static func layoutDisplay(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let translated = layoutData.withUnsafeBytes { buffer -> Bool in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return false }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            ) == noErr
        }

        guard translated, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        guard !text.isEmpty,
              text.rangeOfCharacter(from: .controlCharacters) == nil,
              text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return nil }
        return text.uppercased()
    }

    private static let specialKeyDisplays: [NSEvent.SpecialKey: String] = [
        .backspace: "⌫",
        .delete: "⌦",
        .leftArrow: "←",
        .rightArrow: "→",
        .upArrow: "↑",
        .downArrow: "↓",
        .home: "↖",
        .end: "↘",
        .pageUp: "⇞",
        .pageDown: "⇟",
        .clearLine: "⌧",
        .enter: "⌤",
        .tab: "⇥"
    ]

    private static let keyCodeDisplays: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "⎋",
        71: "⌧",
        76: "⌤",
        114: "Help",
        115: "↖",
        116: "⇞",
        117: "⌦",
        119: "↘",
        121: "⇟",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]
}
