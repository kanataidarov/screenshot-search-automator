import Carbon
import Foundation

// MARK: - HotKeyStore

@MainActor
final class HotKeyStore {
    static let shared = HotKeyStore()

    private enum DefaultsKey {
        static let keyCode  = "hotKeyKeyCode"
        static let mods     = "hotKeyModifiers"
    }

    static let defaultKeyCode:   UInt32 = UInt32(kVK_ANSI_9)
    static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private(set) var keyCode:   UInt32
    private(set) var modifiers: UInt32

    private init() {
        let d = UserDefaults.standard
        if let kc = d.object(forKey: DefaultsKey.keyCode) as? Int,
           let m  = d.object(forKey: DefaultsKey.mods)    as? Int {
            keyCode   = UInt32(bitPattern: Int32(kc))
            modifiers = UInt32(bitPattern: Int32(m))
        } else {
            keyCode   = HotKeyStore.defaultKeyCode
            modifiers = HotKeyStore.defaultModifiers
        }
    }

    func save(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode   = keyCode
        self.modifiers = modifiers
        UserDefaults.standard.set(Int(keyCode),   forKey: DefaultsKey.keyCode)
        UserDefaults.standard.set(Int(modifiers), forKey: DefaultsKey.mods)
    }

    var displayString: String {
        HotKeyStore.describe(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: Display helpers (nonisolated — pure computation, no state access)

    nonisolated static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyLabel(for: keyCode)
        return s
    }

    nonisolated static func keyLabel(for keyCode: UInt32) -> String {
        let specialKeys: [Int: String] = [
            kVK_F1: "F1",  kVK_F2: "F2",  kVK_F3: "F3",  kVK_F4: "F4",
            kVK_F5: "F5",  kVK_F6: "F6",  kVK_F7: "F7",  kVK_F8: "F8",
            kVK_F9: "F9",  kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_Space: "Space",     kVK_Return: "↩",  kVK_Tab: "⇥",
            kVK_Delete: "⌫",        kVK_ForwardDelete: "⌦",
            kVK_UpArrow: "↑",       kVK_DownArrow: "↓",
            kVK_LeftArrow: "←",     kVK_RightArrow: "→",
            kVK_Home: "↖",          kVK_End: "↘",
            kVK_PageUp: "⇞",        kVK_PageDown: "⇟",
            kVK_Escape: "⎋",
        ]
        if let label = specialKeys[Int(keyCode)] { return label }

        // Derive printable character via UCKeyTranslate
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }

        let data   = Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKey: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len    = 0

        UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                       0, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysBit),
                       &deadKey, 4, &len, &chars)

        guard len > 0 else { return "?" }
        return String(String.UnicodeScalarView(chars[0..<len].compactMap { Unicode.Scalar($0) })).uppercased()
    }
}

// MARK: - Notification

extension Notification.Name {
    static let hotKeyDidChange = Notification.Name("hotKeyDidChange")
}
