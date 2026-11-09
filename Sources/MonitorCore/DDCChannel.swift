// DDC/CI requests and replies over an I2C transport.
//
// Timing and framing follow MonitorControl's Arm64DDC (MIT, see THIRD_PARTY_NOTICES.md), which is
// the most field-tested implementation on Apple Silicon: every request is written twice with a
// short pause, replies are read from offset 0 after 50 ms, and a few retries smooth over noise.
// Because some setups only answer the specification framing, `probe()` tries every known profile
// and remembers the first one that produces a real answer.
//
// The transport is a protocol so all of this is unit tested against a simulated monitor.
// MonitorIO implements it with the private IOAVService I2C calls.

import Foundation

/// Raw I2C access to a display's DDC/CI endpoint (7-bit address 0x37).
public protocol DDCTransport: AnyObject {
    /// Writes one request. `bytes` start at the length byte; the transport sends the host
    /// address 0x51 before them. Returns 0 on success or an I/O error code.
    func write(_ bytes: [UInt8]) -> Int32
    /// Fills `buffer` with bytes read starting at `offset`. Returns 0 on success or an I/O error code.
    func read(into buffer: inout [UInt8], offset: UInt8) -> Int32
}

/// A combination of request framing and read offset that a display may answer.
public struct DDCProfile: Equatable, Sendable, CustomStringConvertible {
    public var framing: DDCFraming
    public var readOffset: UInt8

    public init(framing: DDCFraming, readOffset: UInt8) {
        self.framing = framing
        self.readOffset = readOffset
    }

    /// Tried in order by `DDCChannel.probe()`.
    public static let candidates: [DDCProfile] = [
        DDCProfile(framing: .monitorControl, readOffset: 0x00),
        DDCProfile(framing: .specification, readOffset: 0x00),
        DDCProfile(framing: .specification, readOffset: 0x51),
    ]

    public var description: String {
        let name = framing == .monitorControl ? "MonitorControl" : "DDC/CI spec"
        return "\(name) checksum, read offset \(Hex.byte(readOffset))"
    }
}

public final class DDCChannel {
    public struct Timing: Sendable {
        /// Each request is written this many times (single writes are often missed on Apple Silicon).
        public var writeCycles = 2
        /// Pause before each write, in microseconds.
        public var writeDelay: UInt32 = 10_000
        /// Pause between the request and reading the reply. DDC/CI requires at least 40 ms.
        public var replyDelay: UInt32 = 50_000
        public var attempts = 3
        public var retryDelay: UInt32 = 20_000

        public init() {}

        public static let standard = Timing()
        public static var probe: Timing {
            var t = Timing()
            t.attempts = 2
            return t
        }
    }

    public struct ProbeAttempt: Sendable {
        public let profile: DDCProfile
        public let reply: VCPReply
    }

    public struct ProbeResult: Sendable {
        /// The profile that produced a real answer, or nil when the display never answered.
        public let working: DDCProfile?
        public let attempts: [ProbeAttempt]
    }

    private let transport: DDCTransport
    private let pause: (UInt32) -> Void
    private let lock = NSLock()
    public private(set) var profile: DDCProfile
    public var timing: Timing
    /// Receives one line per raw I2C transaction. Used for logging and `candelactl --verbose`.
    public var trace: ((String) -> Void)?

    /// `sleep` waits the given number of microseconds; tests pass one that returns immediately.
    public init(transport: DDCTransport, profile: DDCProfile = DDCProfile.candidates[0], timing: Timing = .standard,
                sleep: @escaping (UInt32) -> Void = { _ = usleep($0) }) {
        self.transport = transport
        self.profile = profile
        self.timing = timing
        pause = sleep
    }

    // MARK: Public operations (thread safe, blocking)

    /// Set a VCP feature. Returns false only when the I2C write itself fails; a display that
    /// silently ignores the command still returns true, because DDC/CI has no acknowledgement.
    @discardableResult
    public func setVCP(_ code: UInt8, value: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let packet = DDCPacket.setVCP(code, value: value)
        for _ in 0 ..< max(1, timing.attempts) {
            if send(packet) { return true }
            pause(timing.retryDelay)
        }
        return false
    }

    public func getVCP(_ code: UInt8) -> VCPReply {
        lock.lock()
        defer { lock.unlock() }
        return getVCPLocked(code, profile: profile, timing: timing)
    }

    /// Read and parse the capabilities string. Takes roughly 100 ms per 32 byte fragment.
    public func readCapabilities() -> Capabilities? {
        lock.lock()
        defer { lock.unlock() }
        let text = DDCPacket.assembleCapabilities { offset in
            for _ in 0 ..< max(1, timing.attempts) {
                guard send(DDCPacket.capabilitiesRequest(offset: offset)) else {
                    pause(timing.retryDelay)
                    continue
                }
                pause(timing.replyDelay)
                let read = readRaw(DDCPacket.capabilitiesReplyLength, offset: profile.readOffset)
                if read.ok {
                    let fragment = DDCPacket.parseCapabilitiesReply(read.bytes)
                    if case .data = fragment { return fragment }
                }
                pause(timing.retryDelay)
            }
            return nil
        }
        return text.flatMap(Capabilities.parse)
    }

    /// The capabilities string plus the current value of every readable feature it lists (or of
    /// the features Candela shows when the display sends no capabilities). Used by the app and `candelactl info`.
    public func readCapabilitiesAndValues() -> (capabilities: Capabilities?, values: [UInt8: VCPValue]) {
        let capabilities = readCapabilities()
        let codes = capabilities?.vcpCodes.filter { code in
            let kind = MCCS.kind(of: code)
            return kind == .continuous || kind == .nonContinuous
        } ?? MCCS.probedFeatures
        var values: [UInt8: VCPValue] = [:]
        for code in codes {
            if let v = getVCP(code).value { values[code] = v }
        }
        return (capabilities, values)
    }

    /// Find a profile the display answers. On success the channel keeps using that profile.
    public func probe() -> ProbeResult {
        lock.lock()
        defer { lock.unlock() }
        var attempts: [ProbeAttempt] = []
        for candidate in DDCProfile.candidates {
            let reply = getVCPLocked(MCCS.brightness, profile: candidate, timing: .probe)
            attempts.append(ProbeAttempt(profile: candidate, reply: reply))
            trace?("probe \(candidate): \(reply.summary)")
            if reply.isAnswer {
                profile = candidate
                return ProbeResult(working: candidate, attempts: attempts)
            }
        }
        return ProbeResult(working: nil, attempts: attempts)
    }

    /// Switch to a profile found earlier, for example by another channel to the same display.
    public func use(_ profile: DDCProfile) {
        lock.lock()
        self.profile = profile
        lock.unlock()
    }

    /// "ok", or the I/O error code in hex.
    public static func describe(_ result: Int32) -> String {
        result == 0 ? "ok" : String(format: "0x%08X", UInt32(bitPattern: result))
    }

    // MARK: Internals (call with the lock held)

    private func getVCPLocked(_ code: UInt8, profile: DDCProfile, timing: Timing) -> VCPReply {
        let request = DDCPacket.getVCP(code, framing: profile.framing)
        var last = VCPReply.invalid("no attempt made")
        for _ in 0 ..< max(1, timing.attempts) {
            guard send(request, cycles: timing.writeCycles) else {
                last = .invalid("I2C write failed")
                pause(timing.retryDelay)
                continue
            }
            pause(timing.replyDelay)
            let read = readRaw(DDCPacket.vcpReplyLength, offset: profile.readOffset)
            if read.ok {
                last = DDCPacket.parseVCPReply(read.bytes, expecting: code)
                if last.isAnswer { return last }
            } else {
                last = .invalid("I2C read failed (\(read.status))")
            }
            pause(timing.retryDelay)
        }
        return last
    }

    /// Writes the request `cycles` times. Succeeds when the last write succeeded.
    private func send(_ bytes: [UInt8], cycles: Int? = nil) -> Bool {
        var ok = false
        for _ in 0 ..< max(1, cycles ?? timing.writeCycles) {
            pause(timing.writeDelay)
            let result = transport.write(bytes)
            trace?("write [\(Hex.bytes(bytes))] -> \(Self.describe(result))")
            ok = result == 0
        }
        return ok
    }

    private func readRaw(_ length: Int, offset: UInt8) -> (ok: Bool, bytes: [UInt8], status: String) {
        var buffer = [UInt8](repeating: 0, count: length)
        let result = transport.read(into: &buffer, offset: offset)
        let status = Self.describe(result)
        trace?("read  offset \(Hex.byte(offset)) len \(length) -> \(status) [\(Hex.bytes(buffer))]")
        return (result == 0, buffer, status)
    }
}
