import AppKit
import MonitorCore

/// Intercepts the brightness keys before macOS handles them. Requires the Accessibility permission.
///
/// A Mac's built-in keyboard sends them as media key events; an external Apple keyboard sends
/// ordinary key presses (see BrightnessKey). So the tap also sees every key press, but it only
/// looks at the key code, acts on the brightness keys alone and passes everything else straight
/// on. Nothing is recorded.
final class MediaKeyTap {
    /// Called for every brightness key event: (key, fine step requested, isKeyDown).
    /// Return true to swallow the event.
    var handler: ((BrightnessKey, Bool, Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private let systemDefinedType: UInt32 = 14      // NX_SYSDEFINED
    private let auxControlSubtype: Int16 = 8        // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    /// macOS's Display shortcut (F14 and F15 unless changed), read again every few seconds so a
    /// change in System Settings applies without a relaunch.
    private var shortcut = DisplayShortcut.standard
    private var shortcutReadAt = Date.distantPast
    private let hotKeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        let mask = CGEventMask(1) << CGEventMask(systemDefinedType)
            | CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
            | CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue)
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                             eventsOfInterest: mask, callback: callback,
                                             userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false // the Accessibility permission is missing
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        source = runLoopSource
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that are slow or interrupted. Turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough

        case .keyDown, .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            guard let key = BrightnessKey.fromKeyPress(keyCode: keyCode, flags: flags, shortcut: currentShortcut())
            else { return passThrough }
            let fine = BrightnessKey.isFineStep(flags: flags)
            return handler?(key, fine, type == .keyDown) == true ? nil : passThrough

        default:
            guard type.rawValue == systemDefinedType,
                  let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == auxControlSubtype,
                  let (key, isDown) = BrightnessKey.fromMediaKey(data1: nsEvent.data1) else { return passThrough }
            let fine = BrightnessKey.isFineStep(flags: event.flags.rawValue)
            return handler?(key, fine, isDown) == true ? nil : passThrough
        }
    }

    private func currentShortcut() -> DisplayShortcut {
        let now = Date()
        if now.timeIntervalSince(shortcutReadAt) > 3 {
            shortcutReadAt = now
            shortcut = DisplayShortcut(symbolicHotKeys: hotKeys?.dictionary(forKey: "AppleSymbolicHotKeys"))
        }
        return shortcut
    }
}
