// Recognizes a brightness key press, whichever way the keyboard reports it.
//
// A Mac's built-in keyboard sends its brightness keys as media key events (NX_SYSDEFINED, aux
// control buttons). An external Apple keyboard sends ordinary key presses instead: key codes 144
// and 145 for its brightness keys, and on full-size keyboards F14 and F15, which macOS's Display
// shortcut (Keyboard Shortcuts > Display) turns into brightness keys.

public enum BrightnessKey: Equatable, Sendable {
    case up, down

    // Media key events: NX_KEYTYPE_BRIGHTNESS_UP and NX_KEYTYPE_BRIGHTNESS_DOWN.
    static let auxBrightnessUp = 2
    static let auxBrightnessDown = 3
    static let auxKeyDownState = 0x0A

    /// The dedicated brightness key codes an external Apple keyboard sends.
    public static let brightnessUpKeyCode = 144
    public static let brightnessDownKeyCode = 145

    /// The brightness key in a media key event's data1, and whether it was pressed (true) or
    /// released (false); nil for any other media key.
    public static func fromMediaKey(data1: Int) -> (key: BrightnessKey, isDown: Bool)? {
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let isDown = (data1 & 0xFF00) >> 8 == auxKeyDownState
        switch keyType {
        case auxBrightnessUp: return (.up, isDown)
        case auxBrightnessDown: return (.down, isDown)
        default: return nil
        }
    }

    /// The brightness key a key press stands for, or nil for any other key.
    /// `flags` are the event's modifier flags (CGEventFlags or NSEvent.ModifierFlags raw value,
    /// which use the same bits). The dedicated brightness keys count with any modifiers, like the
    /// built-in keyboard's. Keys bound by the Display shortcut count only with the modifiers it is
    /// set to, or those plus Option and Shift (fine steps); with others they belong to apps.
    public static func fromKeyPress(keyCode: Int, flags: UInt64, shortcut: DisplayShortcut) -> BrightnessKey? {
        switch keyCode {
        case brightnessUpKeyCode: return .up
        case brightnessDownKeyCode: return .down
        default: break
        }
        let held = flags & ModifierFlags.relevant
        let matches: (DisplayShortcut.Binding?) -> Bool = { binding in
            guard let binding, binding.keyCode == keyCode else { return false }
            let bound = binding.modifiers & ModifierFlags.relevant
            return held == bound || held == bound | ModifierFlags.fineStep
        }
        if matches(shortcut.increase) { return .up }
        if matches(shortcut.decrease) { return .down }
        return nil
    }

    /// True when Option and Shift are both held: step in quarter steps like macOS.
    public static func isFineStep(flags: UInt64) -> Bool {
        flags & ModifierFlags.fineStep == ModifierFlags.fineStep
    }
}

/// Modifier bits shared by CGEventFlags and NSEvent.ModifierFlags.
enum ModifierFlags {
    static let shift: UInt64 = 0x2_0000
    static let control: UInt64 = 0x4_0000
    static let option: UInt64 = 0x8_0000
    static let command: UInt64 = 0x10_0000
    /// The modifiers a shortcut is told apart by. Fn and Caps Lock are left out: macOS sets Fn on
    /// every function key press by itself.
    static let relevant = shift | control | option | command
    static let fineStep = shift | option
}

/// macOS's "Decrease display brightness" and "Increase display brightness" shortcuts
/// (System Settings > Keyboard > Keyboard Shortcuts > Display), F14 and F15 unless changed.
public struct DisplayShortcut: Equatable, Sendable {
    public struct Binding: Equatable, Sendable {
        public var keyCode: Int
        public var modifiers: UInt64

        public init(keyCode: Int, modifiers: UInt64) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    /// nil when that shortcut is turned off.
    public var decrease: Binding?
    public var increase: Binding?

    public init(decrease: Binding?, increase: Binding?) {
        self.decrease = decrease
        self.increase = increase
    }

    static let f14 = 107
    static let f15 = 113
    static let fnFlag: UInt64 = 0x80_0000

    /// macOS's defaults: F14 and F15.
    public static let standard = DisplayShortcut(decrease: Binding(keyCode: f14, modifiers: fnFlag),
                                                 increase: Binding(keyCode: f15, modifiers: fnFlag))

    // Symbolic hot key ids in com.apple.symbolichotkeys.
    static let decreaseID = "53"
    static let increaseID = "54"

    /// Reads the shortcuts from the AppleSymbolicHotKeys dictionary of the
    /// com.apple.symbolichotkeys preferences. A shortcut missing there has its default.
    public init(symbolicHotKeys: [String: Any]?) {
        self.init(decrease: Self.binding(symbolicHotKeys?[Self.decreaseID], default: Self.standard.decrease),
                  increase: Self.binding(symbolicHotKeys?[Self.increaseID], default: Self.standard.increase))
    }

    /// An entry looks like {enabled = 1; value = {parameters = (65535, 107, 8388608); type = standard;}}:
    /// the parameters are the character (unused here), the key code and the modifier flags.
    private static func binding(_ entry: Any?, default standard: Binding?) -> Binding? {
        guard let entry = entry as? [String: Any] else { return standard }
        if let enabled = entry["enabled"], (enabled as? Bool == false || integer(enabled) == 0) { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = integer(parameters[1]), let modifiers = integer(parameters[2]),
              keyCode >= 0, keyCode != 0xFFFF, modifiers >= 0 else { return standard }
        return Binding(keyCode: keyCode, modifiers: UInt64(modifiers))
    }

    private static func integer(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? Double { return Int(exactly: number) }
        return nil
    }
}
