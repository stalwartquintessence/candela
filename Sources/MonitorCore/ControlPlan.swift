// Which controls the menu offers for one display, and how its brightness is driven.
//
// This is the agreed menu scope in one place: Brightness is always there; the Contrast,
// Saturation and Volume sliders and the Picture Mode and Color Preset pickers appear only when the
// monitor reports them. Nothing else (input source, sharpness, color gains) is ever offered.
// Kept free of AppKit so the rules are unit tested; changing them means changing their tests.

public struct ControlPlan: Equatable, Sendable {
    public struct Picker: Equatable, Sendable {
        public let code: UInt8
        /// Values to offer, as the monitor lists them.
        public let values: [UInt16]
    }

    public let status: DDCStatus
    /// True when brightness goes to the monitor over DDC/CI, false when it dims the picture.
    public let usesHardwareBrightness: Bool
    /// Sliders shown below Brightness, in menu order.
    public let sliders: [UInt8]
    /// Pickers for the monitor's own preset modes, in menu order.
    public let pickers: [Picker]
    /// The advanced "send DDC/CI without replies" option applies only to a channel that never answers.
    public let canSendWithoutReplies: Bool
    private let isHDMIConverter: Bool

    /// - Parameters:
    ///   - hasChannel: macOS exposes an I2C channel for the display.
    ///   - sendWithoutReplies: the advanced Display Info option is switched on.
    ///   - knownFeatures: features with a known current value (read from the monitor or written earlier).
    ///   - isHDMIConverter: see `isHDMIConverter(transportUpstream:transportDownstream:)`.
    public init(hasChannel: Bool, status: DDCStatus, sendWithoutReplies: Bool = false,
                capabilities: Capabilities? = nil, knownFeatures: Set<UInt8> = [], isHDMIConverter: Bool = false) {
        self.status = status
        self.isHDMIConverter = isHDMIConverter
        let forced = hasChannel && sendWithoutReplies
        usesHardwareBrightness = hasChannel && (status.isWorking || sendWithoutReplies)
        if case .noReply = status { canSendWithoutReplies = hasChannel } else { canSendWithoutReplies = false }

        guard usesHardwareBrightness else {
            sliders = []
            pickers = []
            return
        }
        func isSupported(_ code: UInt8) -> Bool {
            if let capabilities { return capabilities.supports(code) }
            // No capabilities string: offer what was readable, or the common set when forced.
            return knownFeatures.contains(code) || (forced && MCCS.commonFeatures.contains(code))
        }
        sliders = MCCS.menuSliders.filter(isSupported)
        pickers = MCCS.menuPickers.compactMap { code in
            guard isSupported(code) else { return nil }
            let listed = capabilities?.vcp[code] ?? []
            let values = listed.isEmpty ? MCCS.defaultValues(for: code) : listed
            return values.isEmpty ? nil : Picker(code: code, values: values)
        }
    }

    /// A DisplayPort to HDMI converter, like the built-in HDMI port of many Apple Silicon Macs.
    /// These do not pass DDC/CI.
    public static func isHDMIConverter(transportUpstream up: String?, transportDownstream down: String?) -> Bool {
        up == "DP" && down == "HDMI"
    }

    /// Up to two short lines under the display name in the menu. The full explanation is
    /// `status.advice`, shown as a tooltip and in Display Info.
    public var statusLine: String {
        if case .probing = status { return "Checking the monitor..." }
        let ceiling = "100% = the brightness set in the monitor's own menu."
        switch (usesHardwareBrightness, status) {
        case (true, .working): return "Controls the monitor directly (DDC/CI)."
        case (true, _): return "Sending DDC/CI without replies (see Display Info)."
        case (false, .noReply) where isHDMIConverter: return "No monitor controls over HDMI. " + ceiling
        case (false, .noReply): return "Monitor does not answer DDC/CI. " + ceiling
        case (false, .noService): return "No DDC/CI channel. " + ceiling
        default: return ceiling
        }
    }

    /// How brightness is controlled, worded the same in Display Info and `candelactl info`.
    public var methodDescription: String {
        switch (usesHardwareBrightness, status.isWorking) {
        case (true, true): return "Monitor's own controls (DDC/CI)"
        case (true, false): return "DDC/CI without replies (advanced setting)"
        default: return "Software dimming of brightness"
        }
    }
}
