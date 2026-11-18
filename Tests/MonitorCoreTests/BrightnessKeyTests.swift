import Testing
@testable import MonitorCore

@Suite struct BrightnessKeyTests {
    private let fn: UInt64 = 0x80_0000
    private let shift: UInt64 = 0x2_0000
    private let control: UInt64 = 0x4_0000
    private let option: UInt64 = 0x8_0000
    private let command: UInt64 = 0x10_0000
    private let capsLock: UInt64 = 0x1_0000

    /// data1 of a media key event: key type, then key state (0x0A down, 0x0B up).
    private func mediaKey(_ type: Int, down: Bool) -> Int { type << 16 | (down ? 0x0A : 0x0B) << 8 }

    private func key(_ code: Int, _ flags: UInt64 = 0, shortcut: DisplayShortcut = .standard) -> BrightnessKey? {
        BrightnessKey.fromKeyPress(keyCode: code, flags: flags, shortcut: shortcut)
    }

    // MARK: Media key events (built-in keyboard)

    @Test func mediaKeys() {
        #expect(BrightnessKey.fromMediaKey(data1: mediaKey(2, down: true))! == (.up, true))
        #expect(BrightnessKey.fromMediaKey(data1: mediaKey(3, down: true))! == (.down, true))
        #expect(BrightnessKey.fromMediaKey(data1: mediaKey(2, down: false))! == (.up, false))
        #expect(BrightnessKey.fromMediaKey(data1: mediaKey(3, down: false))! == (.down, false))
    }

    @Test func otherMediaKeysAreIgnored() {
        // Volume up, volume down, play, keyboard backlight up.
        for type in [0, 1, 16, 21] {
            #expect(BrightnessKey.fromMediaKey(data1: mediaKey(type, down: true)) == nil)
        }
    }

    // MARK: Key presses (external Apple keyboards)

    @Test func dedicatedBrightnessKeys() {
        #expect(key(144) == .up)
        #expect(key(145) == .down)
        // With any modifiers, like the built-in keyboard's keys.
        #expect(key(144, fn | command) == .up)
        #expect(key(145, shift | option) == .down)
        // Even with the Display shortcut off.
        #expect(key(144, shortcut: DisplayShortcut(decrease: nil, increase: nil)) == .up)
    }

    @Test func f14AndF15() {
        // macOS sets Fn on every function key press.
        #expect(key(107, fn) == .down)
        #expect(key(113, fn) == .up)
        #expect(key(107) == .down)
        #expect(key(113, fn | capsLock) == .up)
    }

    @Test func f14AndF15WithFineStep() {
        #expect(key(107, fn | shift | option) == .down)
        #expect(key(113, fn | shift | option) == .up)
    }

    @Test func f14AndF15WithOtherModifiersBelongToApps() {
        for flags in [command, control, option, shift, command | shift, control | option, shift | option | command] {
            #expect(key(107, fn | flags) == nil)
            #expect(key(113, fn | flags) == nil)
        }
    }

    @Test func otherKeysAreIgnored() {
        // F1, F2, F13, F16, A, Space, Return.
        for code in [122, 120, 105, 106, 0, 49, 36] {
            #expect(key(code, fn) == nil)
        }
    }

    @Test func fineStep() {
        #expect(BrightnessKey.isFineStep(flags: shift | option))
        #expect(BrightnessKey.isFineStep(flags: fn | shift | option | command))
        #expect(!BrightnessKey.isFineStep(flags: option))
        #expect(!BrightnessKey.isFineStep(flags: shift))
        #expect(!BrightnessKey.isFineStep(flags: 0))
    }

    // MARK: Display shortcut settings

    private func entry(enabled: Any, keyCode: Int, modifiers: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, keyCode, modifiers], "type": "standard"]]
    }

    @Test func missingSettingsMeanDefaults() {
        #expect(DisplayShortcut(symbolicHotKeys: nil) == .standard)
        #expect(DisplayShortcut(symbolicHotKeys: [:]) == .standard)
        #expect(DisplayShortcut(symbolicHotKeys: ["32": entry(enabled: 1, keyCode: 0, modifiers: 0)]) == .standard)
    }

    @Test func readsTheSavedShortcut() {
        let saved = DisplayShortcut(symbolicHotKeys: [
            "53": entry(enabled: 1, keyCode: 107, modifiers: 8_388_608),
            "54": entry(enabled: 1, keyCode: 113, modifiers: 8_388_608),
        ])
        #expect(saved == .standard)
    }

    @Test func turnedOffShortcutIsNotUsed() {
        for enabled: Any in [0, false] {
            let shortcut = DisplayShortcut(symbolicHotKeys: [
                "53": entry(enabled: enabled, keyCode: 107, modifiers: 8_388_608),
                "54": entry(enabled: 1, keyCode: 113, modifiers: 8_388_608),
            ])
            #expect(shortcut.decrease == nil)
            #expect(key(107, fn, shortcut: shortcut) == nil)
            #expect(key(113, fn, shortcut: shortcut) == .up)
        }
    }

    @Test func movedShortcutFollowsTheSetting() {
        // Decrease moved to Control-F1 (key code 122).
        let shortcut = DisplayShortcut(symbolicHotKeys: [
            "53": entry(enabled: 1, keyCode: 122, modifiers: Int(control | fn)),
        ])
        #expect(key(122, fn | control, shortcut: shortcut) == .down)
        #expect(key(122, fn | control | shift | option, shortcut: shortcut) == .down)
        #expect(key(122, fn, shortcut: shortcut) == nil)
        #expect(key(107, fn, shortcut: shortcut) == nil)
        #expect(key(113, fn, shortcut: shortcut) == .up)
    }

    @Test func malformedEntryFallsBackToDefault() {
        let shortcut = DisplayShortcut(symbolicHotKeys: [
            "53": ["enabled": 1, "value": ["parameters": [65535]]],
            "54": "nonsense",
        ])
        #expect(shortcut == .standard)
    }
}
