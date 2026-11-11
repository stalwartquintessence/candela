// Follows a MacBook's lid. When it opens or closes, power management sets `AppleClamshellState`
// on its root domain and then sends a clamshell message to every client interested in the root
// domain, so the state read on that message is already the new one.

import Foundation
import IOKit
import MonitorCore

public final class LidMonitor {
    /// Called on the main queue when the lid opens or closes.
    public var onChange: ((LidState) -> Void)?
    public private(set) var state: LidState = .noLid

    private let rootDomain: io_service_t
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0

    /// `kIOPMMessageClamshellStateChange` from IOKit/pwr_mgt/IOPM.h, a macro Swift cannot import:
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100).
    static let clamshellStateChange: UInt32 = 0xE003_4100

    public init() {
        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        state = read()
    }

    deinit {
        if notification != 0 { IOObjectRelease(notification) }
        if let port { IONotificationPortDestroy(port) }
        if rootDomain != 0 { IOObjectRelease(rootDomain) }
    }

    /// Starts listening for the lid. Calling it again does nothing.
    public func start() {
        guard port == nil, rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let callback: IOServiceInterestCallback = { context, _, message, _ in
            guard let context, message == LidMonitor.clamshellStateChange else { return }
            Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }
        let result = IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, callback,
                                                      Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            Log.error("lid: cannot listen for the lid (\(result)); it is read again after display changes")
            IONotificationPortDestroy(port)
            return
        }
        self.port = port
    }

    /// Reads the lid again and calls `onChange` if it changed. Also useful after a display change
    /// or wake, in case a message was missed.
    public func refresh() {
        let current = read()
        guard current != state else { return }
        state = current
        onChange?(current)
    }

    private func read() -> LidState {
        guard rootDomain != 0 else { return .noLid }
        let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return LidState(clamshellClosed: value as? Bool)
    }
}
