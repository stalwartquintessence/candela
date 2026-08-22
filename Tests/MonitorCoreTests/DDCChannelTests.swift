import Testing
@testable import MonitorCore

/// A DDC/CI monitor in software. It answers Get VCP, Set VCP and Capabilities requests the way
/// the MCCS specification describes. Checksums are computed here without DDCPacket, so these
/// tests check the packet code instead of repeating it.
final class SimulatedMonitor: DDCTransport {
    struct Feature {
        var current: UInt16
        var maximum: UInt16
    }

    static let ioError = Int32(bitPattern: 0xE000_02BC) // kIOReturnError
    static let nullMessage: [UInt8] = [0x6E, 0x80, 0xBE]

    var features: [UInt8: Feature]
    var capabilities: String
    /// Request checksum seeds the monitor accepts: 0x6E ^ 0x51 as the specification says, and
    /// 0x6E for the single-byte requests MonitorControl sends. A strict monitor accepts only the first.
    var acceptedSeeds: Set<UInt8> = [0x6E ^ 0x51, 0x6E]
    /// Read offset where replies appear. Reads anywhere else return the Null Message.
    var replyOffset: UInt8 = 0x00
    /// Never answers, like a monitor behind a connection that blocks DDC/CI.
    var isSilent = false
    /// The next this many writes fail at the I2C level.
    var failingWrites = 0
    private(set) var writes: [[UInt8]] = []
    private var reply: [UInt8]?

    init(features: [UInt8: Feature] = [0x10: Feature(current: 50, maximum: 100)], capabilities: String = "") {
        self.features = features
        self.capabilities = capabilities
    }

    func write(_ bytes: [UInt8]) -> Int32 {
        writes.append(bytes)
        if failingWrites > 0 {
            failingWrites -= 1
            return Self.ioError
        }
        guard !isSilent, let first = bytes.first, first & 0x80 != 0 else { return 0 }
        let length = Int(first & 0x7F)
        guard bytes.count == length + 2,
              acceptedSeeds.contains(where: { bytes.dropLast().reduce($0, ^) == bytes.last }) else {
            return 0 // a real monitor ignores requests it cannot verify
        }
        let payload = Array(bytes[1 ... length])
        switch (payload.first, payload.count) {
        case (0x01, 2): reply = vcpReply(code: payload[1])
        case (0x03, 4):
            features[payload[1]]?.current = UInt16(payload[2]) << 8 | UInt16(payload[3])
            reply = nil
        case (0xF3, 3): reply = capabilitiesReply(offset: UInt16(payload[1]) << 8 | UInt16(payload[2]))
        default: reply = nil
        }
        return 0
    }

    func read(into buffer: inout [UInt8], offset: UInt8) -> Int32 {
        let source = offset == replyOffset ? reply : nil
        for i in buffer.indices {
            if let source { buffer[i] = i < source.count ? source[i] : 0 } else { buffer[i] = Self.nullMessage[i % 3] }
        }
        return 0
    }

    private func vcpReply(code: UInt8) -> [UInt8] {
        let f = features[code]
        let maximum = f?.maximum ?? 0
        let current = f?.current ?? 0
        let body: [UInt8] = [0x6E, 0x88, 0x02, f == nil ? 0x01 : 0x00, code, 0x00,
                             UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        return body + [body.reduce(0x50, ^)]
    }

    private func capabilitiesReply(offset: UInt16) -> [UInt8] {
        let text = Array(capabilities.utf8)
        let start = min(Int(offset), text.count)
        let chunk = Array(text[start ..< min(start + 32, text.count)])
        let body: [UInt8] = [0x6E, 0x80 | UInt8(3 + chunk.count), 0xE3, UInt8(offset >> 8), UInt8(offset & 0xFF)] + chunk
        return body + [body.reduce(0x50, ^)]
    }
}

@Suite("DDC/CI channel against a simulated monitor")
struct DDCChannelTests {
    static func channel(_ monitor: SimulatedMonitor) -> DDCChannel {
        DDCChannel(transport: monitor, sleep: { _ in })
    }

    @Test func probeUsesTheFirstProfileThatAnswers() {
        let monitor = SimulatedMonitor()
        let channel = Self.channel(monitor)
        let result = channel.probe()
        #expect(result.working == DDCProfile.candidates[0])
        #expect(result.attempts.count == 1)
        #expect(channel.profile == DDCProfile.candidates[0])
    }

    @Test func probeFallsBackToSpecificationChecksum() {
        let monitor = SimulatedMonitor()
        monitor.acceptedSeeds = [0x6E ^ 0x51]
        let channel = Self.channel(monitor)
        #expect(channel.probe().working == DDCProfile(framing: .specification, readOffset: 0x00))
        #expect(channel.getVCP(0x10).value?.current == 50)
    }

    @Test func probeFindsTheReplyOffset() {
        let monitor = SimulatedMonitor()
        monitor.acceptedSeeds = [0x6E ^ 0x51]
        monitor.replyOffset = 0x51
        let channel = Self.channel(monitor)
        let result = channel.probe()
        #expect(result.working == DDCProfile(framing: .specification, readOffset: 0x51))
        #expect(result.attempts.map(\.reply.isAnswer) == [false, false, true])
        #expect(channel.getVCP(0x10).value?.current == 50)
    }

    @Test func silentMonitorHasNoWorkingProfile() {
        // What the HP Z27 on the MacBook Pro HDMI port does: every reply is the Null Message.
        let monitor = SimulatedMonitor()
        monitor.isSilent = true
        let result = Self.channel(monitor).probe()
        #expect(result.working == nil)
        #expect(result.attempts.count == DDCProfile.candidates.count)
        #expect(result.attempts.allSatisfy { $0.reply == .null })
    }

    @Test func requestsAreWrittenTwice() {
        let monitor = SimulatedMonitor()
        let channel = Self.channel(monitor)
        var trace: [String] = []
        channel.trace = { trace.append($0) }
        _ = channel.getVCP(0x10)
        #expect(monitor.writes == [[0x82, 0x01, 0x10, 0xFD], [0x82, 0x01, 0x10, 0xFD]])
        #expect(trace.first == "write [82 01 10 FD] -> ok")
    }

    @Test func setThenGetRoundTrips() {
        let monitor = SimulatedMonitor(features: [0x12: .init(current: 75, maximum: 100)])
        let channel = Self.channel(monitor)
        #expect(channel.setVCP(0x12, value: 30))
        #expect(monitor.features[0x12]?.current == 30)
        #expect(channel.getVCP(0x12) == .value(VCPValue(code: 0x12, typeCode: 0, current: 30, maximum: 100)))
    }

    @Test func unsupportedFeatureIsAnAnswerWithoutValue() {
        let reply = Self.channel(SimulatedMonitor()).getVCP(0x62)
        #expect(reply == .unsupported(code: 0x62))
        #expect(reply.value == nil)
    }

    @Test func setRetriesAfterFailedWrites() {
        let monitor = SimulatedMonitor()
        monitor.failingWrites = 2 // both writes of the first attempt
        #expect(Self.channel(monitor).setVCP(0x10, value: 20))
        #expect(monitor.features[0x10]?.current == 20)
        #expect(monitor.writes.count == 4)
    }

    @Test func setFailsWhenEveryWriteFails() {
        let monitor = SimulatedMonitor()
        monitor.failingWrites = .max
        #expect(!Self.channel(monitor).setVCP(0x10, value: 20))
        #expect(monitor.writes.count == 2 * DDCChannel.Timing.standard.attempts)
    }

    @Test func readsCapabilitiesAcrossFragments() throws {
        let text = "(prot(monitor)type(LCD)model(SIM27)cmds(01 02 03 07 0C E3 F3)vcp(02 10 12 14(05 08 0B) 60(0F 11) DF)mccs_ver(2.2))"
        #expect(text.utf8.count > 64) // needs at least three fragments
        let caps = try #require(Self.channel(SimulatedMonitor(capabilities: text)).readCapabilities())
        #expect(caps.raw == text)
        #expect(caps.model == "SIM27")
        #expect(caps.vcp[0x14] == [0x05, 0x08, 0x0B])
    }

    @Test func readsValuesOfListedFeaturesOnly() {
        let monitor = SimulatedMonitor(
            features: [0x10: .init(current: 40, maximum: 100), 0x12: .init(current: 70, maximum: 100),
                       0x14: .init(current: 0x05, maximum: 0x0B), 0x87: .init(current: 5, maximum: 10)],
            capabilities: "(vcp(02 04 10 12 14(05 08) DF)mccs_ver(2.2))")
        let (caps, values) = Self.channel(monitor).readCapabilitiesAndValues()
        #expect(caps != nil)
        // 0x02 and 0xDF are read-only info, 0x04 is an action, 0x87 is not listed.
        #expect(Set(values.keys) == [0x10, 0x12, 0x14])
        #expect(values[0x12]?.current == 70)
    }

    @Test func readsMenuFeaturesWithoutCapabilities() {
        let monitor = SimulatedMonitor(features: [0x10: .init(current: 40, maximum: 100), 0x8A: .init(current: 50, maximum: 100)])
        let (caps, values) = Self.channel(monitor).readCapabilitiesAndValues()
        #expect(caps == nil)
        #expect(Set(values.keys) == [0x10, 0x8A])
    }
}
