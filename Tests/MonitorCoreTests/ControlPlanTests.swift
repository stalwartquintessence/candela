import Testing
@testable import MonitorCore

/// The agreed menu scope: Brightness always; Contrast, Saturation, Volume, Picture Mode and Color
/// Preset only when the monitor reports them; never input source, sharpness or color gains.
@Suite("Menu controls")
struct ControlPlanTests {
    static let working = DDCStatus.working(profile: "test")
    static let silent = DDCStatus.noReply(advice: "advice")

    @Test func hdmiConverterOffersOnlyBrightness() {
        let plan = ControlPlan(hasChannel: true, status: Self.silent, isHDMIConverter: true)
        #expect(!plan.usesHardwareBrightness)
        #expect(plan.sliders.isEmpty)
        #expect(plan.pickers.isEmpty)
        #expect(plan.canSendWithoutReplies)
        #expect(plan.statusLine.hasPrefix("No monitor controls over HDMI."))
        #expect(plan.statusLine.contains("100%"))
        #expect(plan.methodDescription == "Software dimming of brightness")
    }

    @Test func missingChannelOffersOnlyBrightness() {
        let plan = ControlPlan(hasChannel: false, status: .noService, sendWithoutReplies: true)
        #expect(!plan.usesHardwareBrightness)
        #expect(plan.sliders.isEmpty)
        #expect(!plan.canSendWithoutReplies)
        #expect(plan.statusLine.hasPrefix("No DDC/CI channel."))
    }

    @Test func showsOnlyWhatTheMonitorReports() throws {
        let caps = try #require(Capabilities.parse("(vcp(10 12 14(05 08 0B) 8A DC(00 03))mccs_ver(2.2))"))
        let plan = ControlPlan(hasChannel: true, status: Self.working, capabilities: caps)
        #expect(plan.usesHardwareBrightness)
        #expect(plan.sliders == [MCCS.contrast, MCCS.saturation])
        #expect(plan.pickers == [ControlPlan.Picker(code: MCCS.pictureMode, values: [0x00, 0x03]),
                                 ControlPlan.Picker(code: MCCS.colorPreset, values: [0x05, 0x08, 0x0B])])
        #expect(plan.statusLine == "Controls the monitor directly (DDC/CI).")
        #expect(plan.methodDescription == "Monitor's own controls (DDC/CI)")
        #expect(!plan.canSendWithoutReplies)
    }

    @Test func volumeAppearsOnlyWithSpeakers() throws {
        let withSpeakers = try #require(Capabilities.parse("(vcp(10 12 62))"))
        let without = try #require(Capabilities.parse("(vcp(10 12))"))
        #expect(ControlPlan(hasChannel: true, status: Self.working, capabilities: withSpeakers).sliders == [MCCS.contrast, MCCS.volume])
        #expect(ControlPlan(hasChannel: true, status: Self.working, capabilities: without).sliders == [MCCS.contrast])
    }

    @Test func neverOffersRejectedControls() throws {
        let caps = try #require(Capabilities.parse("(vcp(10 12 16 18 1A 60(0F 11 1B) 87 8D(01 02) D6(01 04))mccs_ver(2.2))"))
        let plan = ControlPlan(hasChannel: true, status: Self.working, capabilities: caps)
        let offered = Set(plan.sliders + plan.pickers.map(\.code))
        #expect(offered == [MCCS.contrast])
    }

    @Test func pickerWithoutListedValuesUsesDefaults() throws {
        let caps = try #require(Capabilities.parse("(vcp(10 14))"))
        let plan = ControlPlan(hasChannel: true, status: Self.working, capabilities: caps)
        #expect(plan.pickers == [ControlPlan.Picker(code: MCCS.colorPreset, values: MCCS.defaultValues(for: MCCS.colorPreset))])
    }

    @Test func withoutCapabilitiesOffersWhatWasReadable() {
        let plan = ControlPlan(hasChannel: true, status: Self.working, knownFeatures: [MCCS.brightness, MCCS.saturation])
        #expect(plan.sliders == [MCCS.saturation])
        #expect(plan.pickers.isEmpty)
    }

    @Test func sendingWithoutRepliesOffersCommonFeaturesButNeverVolume() {
        let plan = ControlPlan(hasChannel: true, status: Self.silent, sendWithoutReplies: true)
        #expect(plan.usesHardwareBrightness)
        #expect(plan.sliders == [MCCS.contrast])
        #expect(plan.pickers.map(\.code) == [MCCS.colorPreset])
        #expect(plan.canSendWithoutReplies)
        #expect(plan.statusLine == "Sending DDC/CI without replies (see Display Info).")
        #expect(plan.methodDescription == "DDC/CI without replies (advanced setting)")
    }

    @Test func probingSaysSo() {
        #expect(ControlPlan(hasChannel: true, status: .probing).statusLine == "Checking the monitor...")
    }

    @Test func silentMonitorOnOtherConnections() {
        let plan = ControlPlan(hasChannel: true, status: Self.silent)
        #expect(plan.statusLine.hasPrefix("Monitor does not answer DDC/CI."))
    }

    @Test func detectsHDMIConverters() {
        #expect(ControlPlan.isHDMIConverter(transportUpstream: "DP", transportDownstream: "HDMI"))
        #expect(!ControlPlan.isHDMIConverter(transportUpstream: "DP", transportDownstream: "DP"))
        #expect(!ControlPlan.isHDMIConverter(transportUpstream: nil, transportDownstream: "HDMI"))
    }

    @Test func pickerChecksCompareTheLowByte() {
        #expect(MCCS.isSameChoice(0x0005, 0x05))
        #expect(MCCS.isSameChoice(0x0205, 0x05)) // monitor put other data in the high byte
        #expect(!MCCS.isSameChoice(0x0008, 0x05))
        #expect(!MCCS.isSameChoice(nil, 0x05))
    }

    @Test func simulatedMonitorEndToEnd() {
        // A monitor with speakers that also lists input source and sharpness.
        let monitor = SimulatedMonitor(
            features: [0x10: .init(current: 60, maximum: 100), 0x12: .init(current: 75, maximum: 100),
                       0x14: .init(current: 0x05, maximum: 0x0B), 0x60: .init(current: 0x0F, maximum: 0x11),
                       0x62: .init(current: 20, maximum: 100), 0x87: .init(current: 5, maximum: 10)],
            capabilities: "(prot(monitor)type(LCD)model(SIM27)vcp(10 12 14(05 08) 60(0F 11) 62 87)mccs_ver(2.2))")
        let channel = DDCChannel(transport: monitor, sleep: { _ in })
        let probe = channel.probe()
        let (caps, values) = channel.readCapabilitiesAndValues()
        let status = DDCStatus.working(profile: probe.working?.description ?? "")
        let plan = ControlPlan(hasChannel: true, status: status, capabilities: caps, knownFeatures: Set(values.keys))
        #expect(plan.sliders == [MCCS.contrast, MCCS.volume])
        #expect(plan.pickers == [ControlPlan.Picker(code: MCCS.colorPreset, values: [0x05, 0x08])])
    }
}
