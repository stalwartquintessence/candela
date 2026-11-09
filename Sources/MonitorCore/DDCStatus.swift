/// Why a monitor's own controls cannot be reached, and what to do about it. Kept short: a
/// headline and one or two sentences.
public struct DDCAdvice: Equatable, Sendable {
    public let headline: String
    public let detail: String

    public init(headline: String, detail: String) {
        self.headline = headline
        self.detail = detail
    }

    /// Headline and detail as one paragraph, for the command line and copied reports.
    public var text: String { "\(headline). \(detail)" }
}

/// What we know about hardware control of one display.
public enum DDCStatus: Equatable, Sendable {
    /// Not probed yet.
    case unknown
    case probing
    /// No I2C service exists for this display (virtual display, some adapters and docks).
    case noService
    /// A service exists but the display never answered a DDC/CI request.
    case noReply(advice: DDCAdvice)
    /// The display answers DDC/CI.
    case working(profile: String)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// One line for the window and reports.
    public var summary: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .probing: return "Checking DDC/CI..."
        case .noService: return "No DDC/CI channel for this display"
        case .noReply: return "Display does not answer DDC/CI"
        case .working: return "DDC/CI working"
        }
    }

    /// Title for the status shown at the top of Display Info.
    public var headline: String {
        switch self {
        case .unknown: return "Not checked yet"
        case .probing: return "Checking the monitor..."
        case .working: return "Candela controls this monitor directly"
        case .noReply, .noService: return advice?.headline ?? summary
        }
    }

    public var advice: DDCAdvice? {
        switch self {
        case .noReply(let advice): return advice
        case .noService: return DDCStatus.noServiceAdvice
        default: return nil
        }
    }

    /// Advice for a display that does not answer, based on how it is connected.
    public static func noReplyAdvice(transportUpstream up: String?, transportDownstream down: String?) -> DDCAdvice {
        if ControlPlan.isHDMIConverter(transportUpstream: up, transportDownstream: down) {
            return DDCAdvice(
                headline: "This HDMI port blocks monitor controls",
                detail: "Brightness dims the picture instead, so 100% equals the monitor's own brightness. "
                    + "For full control, connect with a USB-C or DisplayPort cable.")
        }
        return DDCAdvice(
            headline: "The monitor does not answer DDC/CI",
            detail: "Turn on DDC/CI in the monitor's on-screen menu, or connect without a dock or adapter. "
                + "Until then, brightness dims the picture and 100% equals the monitor's own brightness.")
    }

    static let noServiceAdvice = DDCAdvice(
        headline: "No DDC/CI channel for this display",
        detail: "macOS offers no way to reach this monitor's controls. "
            + "Brightness dims the picture instead, so 100% equals the monitor's own brightness.")
}
