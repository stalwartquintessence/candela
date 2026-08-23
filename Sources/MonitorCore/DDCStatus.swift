/// What we know about hardware control of one display.
public enum DDCStatus: Equatable, Sendable {
    /// Not probed yet.
    case unknown
    case probing
    /// No I2C service exists for this display (virtual display, some adapters and docks).
    case noService
    /// A service exists but the display never answered a DDC/CI request.
    case noReply(advice: String)
    /// The display answers DDC/CI.
    case working(profile: String)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// One line for menus and reports.
    public var summary: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .probing: return "Checking DDC/CI..."
        case .noService: return "No DDC/CI channel for this display"
        case .noReply: return "Display does not answer DDC/CI"
        case .working: return "DDC/CI working"
        }
    }

    public var advice: String? {
        switch self {
        case .noReply(let advice): return advice
        case .noService: return "macOS exposes no DDC/CI channel for this display, so Candela cannot reach the monitor's own controls. " + DDCStatus.softwareDimmingNote
        default: return nil
        }
    }

    /// Advice for a display that does not answer, based on how it is connected.
    public static func noReplyAdvice(transportUpstream up: String?, transportDownstream down: String?) -> String {
        if ControlPlan.isHDMIConverter(transportUpstream: up, transportDownstream: down) {
            return "This display is connected through a DisplayPort to HDMI converter, like the built-in HDMI port of many Apple Silicon Macs, and that connection does not pass DDC/CI, so Candela cannot reach the monitor's own controls. " + softwareDimmingNote + " For brightness, contrast, saturation, picture modes and volume from the monitor itself, connect it with a video-capable USB-C cable or a USB-C to DisplayPort cable."
        }
        return "The monitor does not answer DDC/CI. Make sure DDC/CI is enabled in its on-screen menu; some docks, adapters and KVM switches block it, so try a direct cable. " + softwareDimmingNote
    }

    /// Why 100% in software dimming is not the monitor's full brightness.
    public static let softwareDimmingNote = "Meanwhile Brightness dims the picture in software, which can only go darker than the monitor's own brightness setting: 100% in Candela equals the brightness set in the monitor's menu. Set the monitor's brightness to 100 with its buttons to get the full range."
}
