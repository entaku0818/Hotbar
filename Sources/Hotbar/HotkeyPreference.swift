import AppKit
import Carbon.HIToolbox

/// User-configurable hotkey for toggling the overlay.
struct HotkeyPreference: Codable, Equatable {
    var keyCode: UInt16
    var option: Bool
    var command: Bool
    var shift: Bool
    var control: Bool

    // ⌥Tab — Alt+Tab-style default; ⌥Space commonly collides with Raycast/Spotlight/Alfred
    static let `default` = HotkeyPreference(keyCode: 48, option: true, command: false, shift: false, control: false)

    private static let defaultsKey = "toggleHotkey"

    static func load(from defaults: UserDefaults = .standard) -> HotkeyPreference {
        guard let data = defaults.data(forKey: defaultsKey),
              let pref = try? JSONDecoder().decode(HotkeyPreference.self, from: data) else {
            return .default
        }
        return pref
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .hotkeyPreferenceChanged, object: nil)
    }

    // MARK: - Matching

    func matches(keyCode: Int64, cgFlags: CGEventFlags) -> Bool {
        guard keyCode == Int64(self.keyCode) else { return false }
        return cgFlags.contains(.maskAlternate) == option
            && cgFlags.contains(.maskCommand) == command
            && cgFlags.contains(.maskShift) == shift
            && cgFlags.contains(.maskControl) == control
    }

    /// Match tolerating Shift — Shift+hotkey cycles backwards (AltTab-style).
    func matchesIgnoringShift(keyCode: Int64, cgFlags: CGEventFlags) -> Bool {
        guard keyCode == Int64(self.keyCode) else { return false }
        return cgFlags.contains(.maskAlternate) == option
            && cgFlags.contains(.maskCommand) == command
            && cgFlags.contains(.maskControl) == control
    }

    /// True while every modifier required by this hotkey is still held.
    func modifiersStillHeld(cgFlags: CGEventFlags) -> Bool {
        if option, !cgFlags.contains(.maskAlternate) { return false }
        if command, !cgFlags.contains(.maskCommand) { return false }
        if shift, !cgFlags.contains(.maskShift) { return false }
        if control, !cgFlags.contains(.maskControl) { return false }
        return true
    }

    func matches(event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let flags = event.modifierFlags
        return flags.contains(.option) == option
            && flags.contains(.command) == command
            && flags.contains(.shift) == shift
            && flags.contains(.control) == control
    }

    var hasModifier: Bool { option || command || shift || control }

    // MARK: - Display

    var displayString: String {
        var parts = ""
        if control { parts += "⌃" }
        if option { parts += "⌥" }
        if shift { parts += "⇧" }
        if command { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_F1...kVK_F20 where fKeyNames[Int(keyCode)] != nil:
            return fKeyNames[Int(keyCode)] ?? "?"
        default:
            return characterName(for: keyCode)
        }
    }

    private static let fKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static func characterName(for keyCode: UInt16) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "key\(keyCode)"
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = ptr.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "key\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

extension Notification.Name {
    static let hotkeyPreferenceChanged = Notification.Name("hotkeyPreferenceChanged")
}
