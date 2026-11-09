import Testing
@testable import MonitorCore

@Suite("Brightness math")
struct BrightnessMathTests {
    @Test func coarseStepsMatchMacOS() {
        #expect(BrightnessMath.step(from: 50, up: true, fine: false) == 56.25)
        #expect(BrightnessMath.step(from: 50, up: false, fine: false) == 43.75)
    }

    @Test func fineSteps() {
        #expect(BrightnessMath.step(from: 50, up: true, fine: true) == 51.5625)
    }

    @Test func stepsSnapToGrid() {
        // 52 is between grid points 50 and 56.25; it snaps to 50 first, then steps.
        #expect(BrightnessMath.step(from: 52, up: true, fine: false) == 56.25)
    }

    @Test func stepsClampAtEnds() {
        #expect(BrightnessMath.step(from: 0, up: false, fine: false) == 0)
        #expect(BrightnessMath.step(from: 100, up: true, fine: false) == 100)
        #expect(BrightnessMath.step(from: 140, up: true, fine: false) == 100)
    }

    @Test func rawConversion() {
        #expect(BrightnessMath.raw(fromPercent: 50, maximum: 100) == 50)
        #expect(BrightnessMath.raw(fromPercent: 33.3, maximum: 100) == 33)
        #expect(BrightnessMath.raw(fromPercent: 100, maximum: 255) == 255)
        #expect(BrightnessMath.raw(fromPercent: 120, maximum: 100) == 100)
        #expect(BrightnessMath.raw(fromPercent: 50, maximum: 0) == 0)
        #expect(BrightnessMath.percent(fromRaw: 25, maximum: 50) == 50)
        #expect(BrightnessMath.percent(fromRaw: 10, maximum: 0) == 0)
    }

    @Test func gammaFactorNeverReachesBlack() {
        #expect(BrightnessMath.gammaFactor(forPercent: 0) == BrightnessMath.minimumGammaFactor)
        #expect(BrightnessMath.gammaFactor(forPercent: 100) == 1)
        #expect(BrightnessMath.gammaFactor(forPercent: -10) == BrightnessMath.minimumGammaFactor)
    }

    @Test func scalesGammaTables() {
        #expect(BrightnessMath.scale([0, 0.5, 1], by: 0.5) == [0, 0.25, 0.5])
        #expect(BrightnessMath.scale([0.5, 1], by: 2) == [0.5, 1])
    }
}

@Suite("MCCS")
struct MCCSTests {
    @Test func featureNames() {
        #expect(MCCS.name(of: 0x10) == "Brightness")
        #expect(MCCS.name(of: 0x60) == "Input Source")
        #expect(MCCS.name(of: 0xE5).hasPrefix("Manufacturer Specific"))
        #expect(MCCS.name(of: 0x7F) == "Feature 0x7F")
    }

    @Test func kinds() {
        #expect(MCCS.kind(of: 0x10) == .continuous)
        #expect(MCCS.kind(of: 0x14) == .nonContinuous)
        #expect(MCCS.kind(of: 0x04) == .action)
    }

    @Test func valueNames() {
        #expect(MCCS.valueName(code: 0x60, value: 0x11) == "HDMI 1")
        #expect(MCCS.valueName(code: 0x60, value: 0x0F) == "DisplayPort 1")
        #expect(MCCS.valueName(code: 0x14, value: 0x05) == "6500 K")
        #expect(MCCS.valueName(code: 0xD6, value: 0x01) == "On")
        #expect(MCCS.valueName(code: 0x8D, value: 0x01) == "Muted")
    }

    @Test func defaultPickerValues() {
        #expect(MCCS.defaultValues(for: 0x60).contains(0x11))
        #expect(MCCS.defaultValues(for: 0x10).isEmpty)
    }
}

@Suite("Display matching")
struct DisplayMatchingTests {
    @Test func parsesEDIDUUID() throws {
        // Synthetic UUID: vendor DEL (0x10AC), product 0xA04B, 60 x 34 cm.
        let facts = try #require(ServiceFacts(index: 0, edidUUID: "10AC4BA0-0000-0000-1F1E-0104B53C2278"))
        #expect(facts.vendor == 0x10AC)
        #expect(facts.product == 0xA04B)
        #expect(facts.widthCM == 60)
        #expect(facts.heightCM == 34)
    }

    @Test func rejectsMalformedUUID() {
        #expect(ServiceFacts(index: 0, edidUUID: "not-a-uuid") == nil)
        #expect(ServiceFacts(index: 0, edidUUID: "ZZAC4BA0-0000-0000-1F1E-0104B53C2278") == nil)
    }

    static func display(_ id: UInt32, serial: UInt32 = 0) -> DisplayFacts {
        DisplayFacts(displayID: id, vendor: 0x10AC, model: 0xA04B, serial: serial, widthMM: 600, heightMM: 340)
    }

    @Test func matchesByVendorAndProduct() {
        let service = ServiceFacts(index: 7, vendor: 0x10AC, product: 0xA04B, serial: nil, widthCM: 60, heightCM: 34)
        #expect(DisplayMatcher.score(Self.display(1), service) == 9)
        #expect(DisplayMatcher.assign(displays: [Self.display(1)], services: [service]) == [1: 7])
    }

    @Test func refusesDifferentModel() {
        let other = ServiceFacts(index: 0, vendor: 0x10AC, product: 0x0001, serial: nil, widthCM: nil, heightCM: nil)
        #expect(DisplayMatcher.score(Self.display(1), other) == 0)
        #expect(DisplayMatcher.assign(displays: [Self.display(1)], services: [other]).isEmpty)
    }

    @Test func separatesIdenticalModelsBySerial() {
        let displays = [Self.display(1, serial: 111), Self.display(2, serial: 222)]
        let services = [
            ServiceFacts(index: 0, vendor: 0x10AC, product: 0xA04B, serial: 222, widthCM: 60, heightCM: 34),
            ServiceFacts(index: 1, vendor: 0x10AC, product: 0xA04B, serial: 111, widthCM: 60, heightCM: 34),
        ]
        #expect(DisplayMatcher.assign(displays: displays, services: services) == [1: 1, 2: 0])
    }

    @Test func serviceWithoutIdentityIsLastResort() {
        let anonymous = ServiceFacts(index: 3, vendor: nil, product: nil, serial: nil, widthCM: nil, heightCM: nil)
        #expect(DisplayMatcher.assign(displays: [Self.display(5)], services: [anonymous]) == [5: 3])
    }
}

@Suite("Display report")
struct DisplayReportTests {
    @Test func includesEDIDAndCapabilities() throws {
        var input = DisplayReport.Input(name: "Test 27", ddcStatus: "Working", controlMethod: "Hardware (DDC/CI)")
        input.edid = EDID(bytes: EDIDBuilder().build())
        input.capabilities = Capabilities.parse("(model(T27)vcp(10 12 60(0F 11))mccs_ver(2.2))")
        input.values[0x60] = VCPValue(code: 0x60, typeCode: 0, current: 0x11, maximum: 0x12)
        input.transportUpstream = "DP"
        input.transportDownstream = "HDMI"
        let report = DisplayReport.build(input)

        let titles = report.sections.map(\.title)
        #expect(titles.contains("Display"))
        #expect(titles.contains("DDC/CI"))
        #expect(titles.contains("Supported Features"))
        #expect(titles.contains("EDID"))

        let text = report.plainText
        #expect(text.contains("HPN (HP)"))
        #expect(text.contains("Week 34, 2018"))
        #expect(text.contains("3840 x 2160 @ 60.00 Hz"))
        #expect(text.contains("DP to HDMI (converter)"))
        #expect(text.contains("Input Source: HDMI 1"))
        #expect(text.contains("MCCS version"))
    }

    @Test func rendersWithoutOptionalData() {
        let report = DisplayReport.build(DisplayReport.Input(name: "Mystery", ddcStatus: "Not available", controlMethod: "Software"))
        #expect(report.sections.map(\.title) == ["Display", "DDC/CI"])
        #expect(report.plainText.hasPrefix("Mystery\n======="))
    }

    @Test func transportDescriptions() {
        #expect(DisplayReport.transportDescription(up: "DP", down: "DP") == "DP")
        #expect(DisplayReport.transportDescription(up: nil, down: nil) == "Unknown")
    }
}

@Suite("DDC status")
struct DDCStatusTests {
    @Test func hdmiConverterAdviceNamesTheCause() {
        let advice = DDCStatus.noReplyAdvice(transportUpstream: "DP", transportDownstream: "HDMI")
        #expect(advice.headline.contains("HDMI"))
        #expect(advice.detail.contains("USB-C"))
    }

    @Test func genericAdvicePointsToMonitorMenu() {
        let advice = DDCStatus.noReplyAdvice(transportUpstream: "DP", transportDownstream: "DP")
        #expect(advice.detail.contains("on-screen menu"))
    }

    @Test func workingAndAdvice() {
        #expect(DDCStatus.working(profile: "x").isWorking)
        #expect(!DDCStatus.noService.isWorking)
        #expect(!DDCStatus.probing.isWorking)
        #expect(DDCStatus.noService.advice != nil)
        let advice = DDCAdvice(headline: "Blocked", detail: "Try another cable.")
        #expect(DDCStatus.noReply(advice: advice).advice == advice)
        #expect(DDCStatus.noReply(advice: advice).headline == "Blocked")
        #expect(advice.text == "Blocked. Try another cable.")
        #expect(DDCStatus.unknown.advice == nil)
    }

    @Test func versionIsSemantic() {
        let parts = AppVersion.string.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}

@Suite("Feature set")
struct MenuFeatureTests {
    @Test func newFeatureNames() {
        #expect(MCCS.name(of: MCCS.saturation) == "Saturation")
        #expect(MCCS.kind(of: MCCS.saturation) == .continuous)
        #expect(MCCS.name(of: MCCS.pictureMode) == "Picture Mode")
        #expect(MCCS.kind(of: MCCS.pictureMode) == .nonContinuous)
    }

    @Test func pictureModeValues() {
        #expect(MCCS.valueName(code: MCCS.pictureMode, value: 0x03) == "Movie")
        #expect(MCCS.valueName(code: MCCS.pictureMode, value: 0x00) == "Standard")
        #expect(MCCS.pictureModeName(0x42) == "Mode 0x42")
        #expect(!MCCS.defaultValues(for: MCCS.pictureMode).isEmpty)
    }

    @Test func menuShowsOnlyTheAgreedControls() {
        #expect(MCCS.menuSliders == [MCCS.contrast, MCCS.saturation, MCCS.volume])
        #expect(MCCS.menuPickers == [MCCS.pictureMode, MCCS.colorPreset])
        #expect(MCCS.probedFeatures.first == MCCS.brightness)
    }

    @Test func volumeIsNeverAssumed() {
        // Volume must only appear when the monitor reports it.
        #expect(!MCCS.commonFeatures.contains(MCCS.volume))
    }

    @Test func adviceExplainsTheSoftwareBrightnessCeiling() throws {
        for advice in [DDCStatus.noReplyAdvice(transportUpstream: "DP", transportDownstream: "HDMI"),
                       DDCStatus.noReplyAdvice(transportUpstream: "DP", transportDownstream: "DP"),
                       try #require(DDCStatus.noService.advice)] {
            #expect(advice.detail.contains("100% equals the monitor's own brightness"))
        }
    }
}
