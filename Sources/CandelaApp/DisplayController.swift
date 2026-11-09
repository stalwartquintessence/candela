import Combine
import CoreGraphics
import Foundation
import MonitorCore
import MonitorIO

/// Persistent per-display settings, keyed by the display's identity.
struct DisplaySettings {
    private let prefix: String
    private let defaults = UserDefaults.standard

    init(key: String) { prefix = "display.\(key)." }

    /// The advanced Display Info option: send DDC/CI even though the monitor never answers
    /// (a few monitors accept commands without ever replying).
    var sendWithoutReplies: Bool {
        get { defaults.bool(forKey: prefix + "sendWithoutReplies") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "sendWithoutReplies") }
    }

    var softwareBrightness: Double {
        get { defaults.object(forKey: prefix + "softwareBrightness") as? Double ?? 100 }
        nonmutating set { defaults.set(newValue, forKey: prefix + "softwareBrightness") }
    }

    /// Last value written for a VCP code, used when the display cannot be read back.
    func storedValue(_ code: UInt8) -> UInt16? {
        (defaults.object(forKey: prefix + "vcp.\(code)") as? Int).map { UInt16(clamping: $0) }
    }

    func store(_ value: UInt16, for code: UInt8) {
        defaults.set(Int(value), forKey: prefix + "vcp.\(code)")
    }
}

/// Owns everything about one external display: DDC state, software dimming and saved settings.
/// All public members are main-thread only; DDC I/O runs on `DisplayController.ddcQueue`.
/// Published state drives the Candela window.
final class DisplayController: ObservableObject, Identifiable {
    /// One queue for all displays so I2C traffic is never interleaved.
    static let ddcQueue = DispatchQueue(label: "candela.ddc", qos: .userInitiated)

    private(set) var display: ExternalDisplay
    @Published private(set) var name: String
    @Published private(set) var status: DDCStatus = .unknown
    private(set) var profile: DDCProfile?
    @Published private(set) var capabilities: Capabilities?
    /// Last known values, read from the display or written by us.
    @Published private(set) var values: [UInt8: VCPValue] = [:]
    /// Brightness used when dimming in software, saved per display.
    @Published private(set) var softwareBrightness: Double = 100

    private var channel: DDCChannel?
    private let gamma: GammaDimmer
    private let settings: DisplaySettings
    private var writeGenerations: [UInt8: Int] = [:]
    private let generationLock = NSLock()

    /// Called on the main thread whenever state changes.
    var onChange: (() -> Void)?

    var displayID: CGDirectDisplayID { display.displayID }

    init(display: ExternalDisplay, name: String, gamma: GammaDimmer) {
        self.display = display
        self.name = name
        self.gamma = gamma
        settings = DisplaySettings(key: display.settingsKey)
        softwareBrightness = settings.softwareBrightness
        channel = Self.makeChannel(for: display, profile: nil)
        if channel == nil { status = .noService }
    }

    /// The same monitor on the same connection, discovered again after a display change or wake.
    /// macOS may have rebuilt the registry entries (and renumbered the display), so the DDC channel
    /// is recreated from the fresh service, keeping the framing that already worked.
    func update(display: ExternalDisplay, name: String) {
        self.display = display
        self.name = name
        channel = Self.makeChannel(for: display, profile: profile)
    }

    private static func makeChannel(for display: ExternalDisplay, profile: DDCProfile?) -> DDCChannel? {
        guard let service = display.avService?.service else { return nil }
        let channel = DDCChannel(service: service, profile: profile ?? DDCProfile.candidates[0])
        channel.trace = { Log.trace($0) }
        return channel
    }

    // MARK: State

    /// The advanced "send DDC/CI without replies" option from Display Info.
    var sendWithoutReplies: Bool {
        get { settings.sendWithoutReplies }
        set {
            objectWillChange.send()
            settings.sendWithoutReplies = newValue
            if newValue { values = storedValues().merging(values) { _, current in current } }
            applySoftwareDimming()
            onChange?()
        }
    }

    /// What the menu offers and how brightness is driven, given the current state.
    var plan: ControlPlan {
        let transport = display.avService
        return ControlPlan(hasChannel: channel != nil, status: status, sendWithoutReplies: settings.sendWithoutReplies,
                           capabilities: capabilities, knownFeatures: Set(values.keys),
                           isHDMIConverter: ControlPlan.isHDMIConverter(transportUpstream: transport?.transportUpstream,
                                                                        transportDownstream: transport?.transportDownstream))
    }

    /// Brightness in percent for whichever method is active.
    var brightness: Double {
        plan.usesHardwareBrightness ? percent(of: MCCS.brightness) : softwareBrightness
    }

    func percent(of code: UInt8) -> Double {
        guard let v = values[code] else { return 50 }
        return BrightnessMath.percent(fromRaw: v.current, maximum: v.maximum)
    }

    func currentValue(of code: UInt8) -> UInt16? { values[code]?.current }

    var report: DisplayReport {
        let input = display.reportInput(name: name, ddcStatus: status, controlMethod: plan.methodDescription,
                                        profile: status.isWorking ? profile : nil, capabilities: capabilities, values: values)
        return DisplayReport.build(input)
    }

    // MARK: Actions

    func setBrightness(_ percent: Double) {
        let p = BrightnessMath.clamp(percent)
        if plan.usesHardwareBrightness {
            gamma.restore(displayID)
            set(code: MCCS.brightness, percent: p)
        } else {
            softwareBrightness = p
            settings.softwareBrightness = p
            gamma.setBrightness(p, for: displayID)
        }
    }

    func set(code: UInt8, percent: Double) {
        let maximum = values[code]?.maximum ?? 100
        set(code: code, value: BrightnessMath.raw(fromPercent: percent, maximum: maximum))
    }

    /// Write a VCP value. Rapid calls are coalesced so only the latest value is sent.
    func set(code: UInt8, value: UInt16) {
        guard let channel else { return }
        let maximum = values[code]?.maximum ?? 100
        values[code] = VCPValue(code: code, typeCode: 0, current: value, maximum: maximum)
        settings.store(value, for: code)

        generationLock.lock()
        let generation = (writeGenerations[code] ?? 0) + 1
        writeGenerations[code] = generation
        generationLock.unlock()

        Self.ddcQueue.async { [weak self] in
            guard let self, self.isLatest(generation, for: code) else { return }
            if !channel.setVCP(code, value: value) {
                Log.error("DDC write failed: \(MCCS.name(of: code)) = \(value) on \(self.name)")
            }
        }
    }

    private func isLatest(_ generation: Int, for code: UInt8) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return writeGenerations[code] == generation
    }

    /// Apply or remove software dimming according to the current method and status.
    func applySoftwareDimming() {
        if plan.usesHardwareBrightness {
            gamma.restore(displayID)
        } else {
            gamma.setBrightness(softwareBrightness, for: displayID)
        }
    }

    /// Check whether the display answers DDC/CI, then read its capabilities and current values.
    func probe() {
        guard let channel else {
            status = .noService
            applySoftwareDimming()
            onChange?()
            return
        }
        // Keep a working status while re-checking so brightness does not flip to software dimming.
        if !status.isWorking { status = .probing }
        onChange?()
        let display = self.display
        Self.ddcQueue.async { [weak self] in
            let result = channel.probe()
            let state: (capabilities: Capabilities?, values: [UInt8: VCPValue]) =
                result.working != nil ? channel.readCapabilitiesAndValues() : (nil, [:])
            Log.ddc("probe \(display.name): \(result.working.map { "working, \($0)" } ?? "no answer"), "
                + "capabilities: \(state.capabilities.map { "\($0.vcpCodes.count) features" } ?? "none"), "
                + "read \(state.values.count) values")

            DispatchQueue.main.async {
                guard let self else { return }
                if let working = result.working {
                    self.status = .working(profile: working.description)
                    self.profile = working
                    // The channel may have been replaced while probing (display change or wake).
                    self.channel?.use(working)
                    self.capabilities = state.capabilities
                    self.values = state.values
                } else {
                    self.status = .noReply(advice: DDCStatus.noReplyAdvice(
                        transportUpstream: display.avService?.transportUpstream,
                        transportDownstream: display.avService?.transportDownstream))
                    self.capabilities = nil
                    self.values = self.storedValues()
                }
                self.applySoftwareDimming()
                self.onChange?()
            }
        }
    }

    /// Values we wrote earlier, for displays that cannot be read (advanced "send without replies").
    private func storedValues() -> [UInt8: VCPValue] {
        var result: [UInt8: VCPValue] = [:]
        for code in MCCS.probedFeatures {
            if let v = settings.storedValue(code) {
                result[code] = VCPValue(code: code, typeCode: 0, current: v, maximum: 100)
            }
        }
        return result
    }
}
