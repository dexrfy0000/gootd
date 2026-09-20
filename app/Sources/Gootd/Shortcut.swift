import AppKit
import Carbon.HIToolbox

/// A key combination, stored as the raw virtual key plus Cocoa modifier flags.
struct Shortcut: Codable, Equatable {

    var keyCode: UInt16
    var modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRawValue) }

    /// Option + Command + backslash. Close to the sleep-ish corner of the
    /// keyboard, and not claimed by anything in macOS.
    static let `default` = Shortcut(
        keyCode: UInt16(kVK_ANSI_Backslash),
        modifierRawValue: (NSEvent.ModifierFlags.option.union(.command)).rawValue
    )

    init(keyCode: UInt16, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])
        // A bare letter would swallow typing everywhere, so require a modifier.
        guard !flags.isEmpty else { return nil }
        self.keyCode = event.keyCode
        self.modifierRawValue = flags.rawValue
    }

    /// Carbon wants its own modifier bitfield, not Cocoa's.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { value |= UInt32(shiftKey) }
        return value
    }

    // MARK: - Display

    var display: String { modifierGlyphs + keyGlyph }

    /// The same combination split into one string per physical key, so the UI
    /// can set each one as its own legend instead of one run of glyphs.
    var tokens: [String] { modifierGlyphs.map(String.init) + [keyGlyph] }

    private var modifierGlyphs: String {
        var out = ""
        if modifiers.contains(.control) { out += "\u{2303}" }
        if modifiers.contains(.option)  { out += "\u{2325}" }
        if modifiers.contains(.shift)   { out += "\u{21E7}" }
        if modifiers.contains(.command) { out += "\u{2318}" }
        return out
    }

    private var keyGlyph: String {
        if let named = Shortcut.namedKeys[Int(keyCode)] { return named }
        return Shortcut.character(for: keyCode)?.uppercased() ?? "?"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "space", kVK_Return: "\u{21A9}", kVK_Tab: "\u{21E5}",
        kVK_Delete: "\u{232B}", kVK_Escape: "esc", kVK_ForwardDelete: "\u{2326}",
        kVK_LeftArrow: "\u{2190}", kVK_RightArrow: "\u{2192}",
        kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// Ask the current keyboard layout what this key prints, so an AZERTY or a
    /// Dvorak user sees their own legend rather than a US one.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
