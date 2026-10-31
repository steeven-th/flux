import AppKit

/// A key and its modifiers. The key is the character it types without modifiers on the user's
/// keyboard, so a shortcut recorded on a French keyboard is matched on it.
struct KeyShortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt

    static let usableModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.usableModifiers).rawValue
    }

    init?(menuItem: NSMenuItem) {
        guard !menuItem.keyEquivalent.isEmpty else { return nil }
        self.init(key: menuItem.keyEquivalent, modifiers: menuItem.keyEquivalentModifierMask)
    }

    init?(event: NSEvent) {
        guard var key = event.characters(byApplyingModifiers: []), !key.isEmpty else { return nil }
        // What the Delete key types. Menus expect a backspace for it.
        if key == "\u{7f}" { key = "\u{8}" }
        self.init(key: key.lowercased(), modifiers: event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// Without one of these, the shortcut would take a key from text being typed.
    var hasCommandKey: Bool {
        !flags.isDisjoint(with: [.command, .control, .option]) || isFunctionKey
    }

    private var isFunctionKey: Bool {
        guard let scalar = key.unicodeScalars.first?.value else { return false }
        return (UInt32(NSF1FunctionKey)...UInt32(NSF20FunctionKey)).contains(scalar)
    }

    /// Menus only match a shortcut with Shift on the character Shift makes, which depends on the
    /// keyboard, "+" or "_" for "=" on some, "+" or "6" on a French one. Letters are fine.
    var needsKeyMatching: Bool {
        guard flags.contains(.shift), let scalar = key.unicodeScalars.first else { return false }
        return !CharacterSet.letters.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar)
            && scalar.value < UInt32(NSUpArrowFunctionKey)
    }

    var displayName: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(key)
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first?.value else { return key }
        switch Int(scalar) {
        case 0x8, 0x7f: return "⌫"
        case 0xd, 0x3: return "↩"
        case 0x9: return "⇥"
        case 0x1b: return "⎋"
        case 0x20: return String(localized: "Space")
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSDeleteFunctionKey: return "⌦"
        case NSHomeFunctionKey: return "↖"
        case NSEndFunctionKey: return "↘"
        case NSPageUpFunctionKey: return "⇞"
        case NSPageDownFunctionKey: return "⇟"
        case NSF1FunctionKey...NSF20FunctionKey: return "F\(Int(scalar) - NSF1FunctionKey + 1)"
        default: return key.uppercased()
        }
    }
}
