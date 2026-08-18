// DDC/CI packet encoding and reply decoding (VESA DDC/CI 1.1, MCCS 2.2).
//
// Wire format for a host to display write, as seen on the I2C bus:
//     [0x6E dest] [0x51 src] [0x80 | length] [payload ...] [checksum]
// The IOAVService I2C call takes the destination as the 7-bit chip address (0x37) and sends the
// source byte (0x51) as its "data address", so the buffers built here start at the length byte.
//
// Display to host replies are read back starting at the source byte:
//     [0x6E src] [0x80 | length] [payload ...] [checksum]
// where the reply checksum is seeded with the virtual host address 0x50.

/// How the checksum of a request is seeded. Different Apple Silicon setups have been observed to
/// accept different variants, so the hardware layer probes both and remembers what works.
public enum DDCFraming: Sendable {
    /// Single-byte requests (Get VCP) seeded with 0x6E only, everything else with 0x6E ^ 0x51.
    /// This is what MonitorControl and m1ddc send and is the most widely field-tested choice.
    case monitorControl
    /// Every request seeded with 0x6E ^ 0x51, as the DDC/CI specification describes.
    case specification
}

public enum DDCPacket {
    /// 7-bit I2C address of the DDC/CI endpoint in the display.
    public static let chipAddress: UInt8 = 0x37
    /// 8-bit destination address (0x37 << 1).
    public static let displayAddress: UInt8 = 0x6E
    /// Source address byte of the host.
    public static let hostAddress: UInt8 = 0x51
    /// Seed for checksums of display to host replies.
    public static let replySeed: UInt8 = 0x50

    /// XOR checksum.
    public static func checksum<S: Sequence>(_ bytes: S, seed: UInt8) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Get VCP Feature request: [0x82, 0x01, code, checksum].
    public static func getVCP(_ code: UInt8, framing: DDCFraming = .monitorControl) -> [UInt8] {
        let body: [UInt8] = [0x82, 0x01, code]
        let seed = framing == .monitorControl ? displayAddress : displayAddress ^ hostAddress
        return body + [checksum(body, seed: seed)]
    }

    /// Set VCP Feature request: [0x84, 0x03, code, valueHi, valueLo, checksum].
    public static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        return body + [checksum(body, seed: displayAddress ^ hostAddress)]
    }

    /// Capabilities Request for the fragment starting at `offset`: [0x83, 0xF3, offHi, offLo, checksum].
    public static func capabilitiesRequest(offset: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
        return body + [checksum(body, seed: displayAddress ^ hostAddress)]
    }

    /// The DDC/CI Null Message a display sends when it has nothing to report.
    public static let nullMessage: [UInt8] = [0x6E, 0x80, 0xBE]

    /// Length of a Get VCP reply: src, len, opcode, result, code, type, maxHi, maxLo, curHi, curLo, chk.
    public static let vcpReplyLength = 11

    /// Read size for one capabilities fragment: 5 header bytes, up to 32 data bytes, checksum.
    public static let capabilitiesReplyLength = 38
}

/// A decoded VCP value.
public struct VCPValue: Equatable, Sendable {
    public let code: UInt8
    /// 0x00 = set parameter (continuous), 0x01 = momentary.
    public let typeCode: UInt8
    public let current: UInt16
    public let maximum: UInt16

    public init(code: UInt8, typeCode: UInt8, current: UInt16, maximum: UInt16) {
        self.code = code
        self.typeCode = typeCode
        self.current = current
        self.maximum = maximum
    }
}

/// Outcome of decoding a Get VCP reply.
public enum VCPReply: Equatable, Sendable {
    case value(VCPValue)
    /// The display answered and says it does not support this feature code.
    case unsupported(code: UInt8)
    /// The display sent the Null Message (no data). Common when DDC/CI is blocked on the path.
    case null
    /// Anything else: wrong length, bad checksum, wrong opcode or code.
    case invalid(String)

    public var value: VCPValue? {
        if case .value(let v) = self { return v }
        return nil
    }

    /// True when the display actually produced a well formed answer (value or unsupported).
    public var isAnswer: Bool {
        switch self {
        case .value, .unsupported: return true
        case .null, .invalid: return false
        }
    }

    public var summary: String {
        switch self {
        case .value(let v): return "value current=\(v.current) max=\(v.maximum)"
        case .unsupported(let code): return "unsupported feature \(Hex.byte(code))"
        case .null: return "null message (display sent no data)"
        case .invalid(let reason): return "invalid reply: \(reason)"
        }
    }
}

extension DDCPacket {
    /// Decode a Get VCP Feature reply for `code`.
    public static func parseVCPReply(_ bytes: [UInt8], expecting code: UInt8) -> VCPReply {
        guard bytes.count >= 3 else { return .invalid("too short (\(bytes.count) bytes)") }
        if bytes[0] == displayAddress, bytes[1] == 0x80 { return .null }
        guard bytes.count >= vcpReplyLength else { return .invalid("too short (\(bytes.count) bytes)") }
        guard bytes[0] == displayAddress else { return .invalid("unexpected source byte \(Hex.byte(bytes[0]))") }
        guard bytes[1] == 0x88 else { return .invalid("unexpected length byte \(Hex.byte(bytes[1]))") }

        let expected = checksum(bytes[0 ..< 10], seed: replySeed)
        guard expected == bytes[10] else {
            return .invalid("bad checksum, expected \(Hex.byte(expected)) got \(Hex.byte(bytes[10]))")
        }
        guard bytes[2] == 0x02 else { return .invalid("unexpected opcode \(Hex.byte(bytes[2]))") }
        guard bytes[4] == code else { return .invalid("reply is for \(Hex.byte(bytes[4])), not \(Hex.byte(code))") }

        switch bytes[3] {
        case 0x00:
            return .value(VCPValue(code: code,
                                   typeCode: bytes[5],
                                   current: UInt16(bytes[8]) << 8 | UInt16(bytes[9]),
                                   maximum: UInt16(bytes[6]) << 8 | UInt16(bytes[7])))
        case 0x01:
            return .unsupported(code: code)
        default:
            return .invalid("result code \(Hex.byte(bytes[3]))")
        }
    }
}

/// Outcome of decoding one Capabilities Reply fragment.
public enum CapabilitiesFragment: Equatable, Sendable {
    case data(offset: UInt16, bytes: [UInt8])
    case null
    case invalid(String)
}

extension DDCPacket {
    /// Decode a Capabilities Reply: [0x6E, 0x80 | n, 0xE3, offHi, offLo, data (n - 3 bytes), chk].
    public static func parseCapabilitiesReply(_ bytes: [UInt8]) -> CapabilitiesFragment {
        guard bytes.count >= 3 else { return .invalid("too short") }
        guard bytes[0] == displayAddress else { return .invalid("unexpected source byte \(Hex.byte(bytes[0]))") }
        guard bytes[1] & 0x80 != 0 else { return .invalid("length byte without 0x80 flag") }
        let length = Int(bytes[1] & 0x7F)
        if length == 0 { return .null }
        guard length >= 3 else { return .invalid("length \(length) is too small") }
        guard bytes.count >= 2 + length + 1 else { return .invalid("truncated, need \(3 + length) bytes") }

        let expected = checksum(bytes[0 ..< 2 + length], seed: replySeed)
        guard expected == bytes[2 + length] else {
            return .invalid("bad checksum, expected \(Hex.byte(expected)) got \(Hex.byte(bytes[2 + length]))")
        }
        guard bytes[2] == 0xE3 else { return .invalid("unexpected opcode \(Hex.byte(bytes[2]))") }
        let offset = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
        return .data(offset: offset, bytes: Array(bytes[5 ..< 2 + length]))
    }

    /// Reassemble the capabilities string from fragments. `fetch` performs one request/reply for the
    /// given offset (with its own retries) and returns nil when the display could not be read.
    /// Kept transport-agnostic so the algorithm is unit tested.
    public static func assembleCapabilities(maxBytes: Int = 2048,
                                            fetch: (UInt16) -> CapabilitiesFragment?) -> String? {
        var collected: [UInt8] = []
        var offset: UInt16 = 0
        while collected.count < maxBytes {
            guard let fragment = fetch(offset) else { return nil }
            switch fragment {
            case .data(let replyOffset, let data):
                guard replyOffset == offset else { return nil }
                if data.isEmpty { return finish(collected) }
                collected += data
                offset &+= UInt16(data.count)
            case .null, .invalid:
                return nil
            }
        }
        return finish(collected)
    }

    private static func finish(_ bytes: [UInt8]) -> String? {
        let trimmed = bytes.filter { $0 != 0 }
        guard !trimmed.isEmpty else { return nil }
        return String(decoding: trimmed, as: UTF8.self)
    }
}

/// Hex formatting helpers shared by logs, the CLI and the info window.
public enum Hex {
    public static func byte(_ b: UInt8) -> String {
        let s = String(b, radix: 16, uppercase: true)
        return "0x" + (s.count == 1 ? "0" + s : s)
    }

    public static func word(_ w: UInt16) -> String {
        let s = String(w, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 4 - s.count)) + s
    }

    public static func bytes(_ bytes: [UInt8], separator: String = " ") -> String {
        bytes.map { b -> String in
            let s = String(b, radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }.joined(separator: separator)
    }

    /// Parse a VCP code written as "0x10" or "10". Always hex, matching how codes are written in
    /// MCCS and capability strings ("VCP 10" is brightness, "8D" is mute).
    public static func parseCode(_ text: String) -> UInt8? {
        var t = text.lowercased()
        if t.hasPrefix("0x") { t.removeFirst(2) }
        return UInt8(t, radix: 16)
    }
}
