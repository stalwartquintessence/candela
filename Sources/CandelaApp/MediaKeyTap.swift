import AppKit

/// Intercepts the brightness keys (NX_SYSDEFINED aux control events) before macOS handles them.
/// Requires the Accessibility permission.
final class MediaKeyTap {
    enum Key { case brightnessUp, brightnessDown }

    /// Called for every brightness key event: (key, fine step requested, isKeyDown).
    /// Return true to swallow the event.
    var handler: ((Key, Bool, Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private let systemDefinedType: UInt32 = 14      // NX_SYSDEFINED
    private let auxControlSubtype: Int16 = 8        // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    private let brightnessUpKey = 2                 // NX_KEYTYPE_BRIGHTNESS_UP
    private let brightnessDownKey = 3               // NX_KEYTYPE_BRIGHTNESS_DOWN

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        let mask = CGEventMask(1) << CGEventMask(systemDefinedType)
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

        // macOS disables taps that are slow or interrupted. Turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }

        guard type.rawValue == systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == auxControlSubtype else { return passThrough }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let isDown = ((data & 0xFF00) >> 8) == 0x0A

        let key: Key
        switch keyCode {
        case brightnessUpKey: key = .brightnessUp
        case brightnessDownKey: key = .brightnessDown
        default: return passThrough
        }

        let fine = nsEvent.modifierFlags.contains([.option, .shift])
        return handler?(key, fine, isDown) == true ? nil : passThrough
    }
}
