import Testing
@testable import MonitorCore

@Suite("DDC/CI packets")
struct DDCPacketTests {
    // Byte sequences below were verified against a real HP Z27 on an M1 Pro (see docs/HARDWARE-NOTES.md).

    @Test func getVCPMonitorControlFraming() {
        #expect(DDCPacket.getVCP(0x10, framing: .monitorControl) == [0x82, 0x01, 0x10, 0xFD])
    }

    @Test func getVCPSpecificationFraming() {
        #expect(DDCPacket.getVCP(0x10, framing: .specification) == [0x82, 0x01, 0x10, 0xAC])
    }

    @Test func setVCPIncludesSourceAddressInChecksum() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        #expect(DDCPacket.setVCP(0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    @Test func setVCPSplitsSixteenBitValues() {
        let packet = DDCPacket.setVCP(0x62, value: 0x0123)
        #expect(packet[3] == 0x01)
        #expect(packet[4] == 0x23)
    }

    @Test func capabilitiesRequest() {
        #expect(DDCPacket.capabilitiesRequest(offset: 0) == [0x83, 0xF3, 0x00, 0x00, 0x4F])
        #expect(DDCPacket.capabilitiesRequest(offset: 0x0120)[2 ... 3] == [0x01, 0x20])
    }

    // MARK: Get VCP replies

    static func reply(result: UInt8 = 0, code: UInt8 = 0x10, max: UInt16 = 100, current: UInt16 = 42) -> [UInt8] {
        let body: [UInt8] = [0x6E, 0x88, 0x02, result, code, 0x00,
                             UInt8(max >> 8), UInt8(max & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        return body + [DDCPacket.checksum(body, seed: 0x50)]
    }

    @Test func parsesValidReply() {
        let r = DDCPacket.parseVCPReply(Self.reply(), expecting: 0x10)
        #expect(r == .value(VCPValue(code: 0x10, typeCode: 0, current: 42, maximum: 100)))
        #expect(r.isAnswer)
    }

    @Test func parsesLargeValues() {
        let r = DDCPacket.parseVCPReply(Self.reply(max: 0x0400, current: 0x0201), expecting: 0x10)
        #expect(r.value?.maximum == 1024)
        #expect(r.value?.current == 513)
    }

    @Test func recognizesNullMessage() {
        // Exactly what the HP Z27 returns on the MacBook Pro HDMI port, repeated to fill the buffer.
        let observed: [UInt8] = [0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80, 0xBE, 0x6E, 0x80]
        #expect(DDCPacket.parseVCPReply(observed, expecting: 0x10) == .null)
        #expect(!DDCPacket.parseVCPReply(observed, expecting: 0x10).isAnswer)
    }

    @Test func recognizesUnsupportedFeature() {
        #expect(DDCPacket.parseVCPReply(Self.reply(result: 0x01), expecting: 0x10) == .unsupported(code: 0x10))
    }

    @Test func rejectsBadChecksum() {
        var bytes = Self.reply()
        bytes[9] ^= 0x01
        guard case .invalid(let reason) = DDCPacket.parseVCPReply(bytes, expecting: 0x10) else {
            Issue.record("expected invalid")
            return
        }
        #expect(reason.contains("checksum"))
    }

    @Test func rejectsReplyForDifferentCode() {
        guard case .invalid = DDCPacket.parseVCPReply(Self.reply(code: 0x12), expecting: 0x10) else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func rejectsObservedHDMIBufferEcho() {
        // Returned on the HDMI port for a Get VCP with 0x6E-only checksum and read offset 0x51.
        // It echoes bytes of earlier writes ("10 AC", "00 32 9A") and must never be taken as data.
        let observed: [UInt8] = [0x6E, 0x85, 0xC2, 0x00, 0x00, 0x03, 0x51, 0x71, 0x6E, 0x10, 0xAC]
        #expect(DDCPacket.parseVCPReply(observed, expecting: 0x10).value == nil)
    }

    @Test func rejectsShortReply() {
        #expect(DDCPacket.parseVCPReply([0x6E], expecting: 0x10) != .null)
        #expect(DDCPacket.parseVCPReply([0x6E, 0x88, 0x02, 0x00], expecting: 0x10).value == nil)
    }

    // MARK: Capabilities

    static func fragment(offset: UInt16, data: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [0x6E, 0x80 | UInt8(data.count + 3), 0xE3, UInt8(offset >> 8), UInt8(offset & 0xFF)] + data
        return body + [DDCPacket.checksum(body, seed: 0x50)]
    }

    @Test func parsesCapabilitiesFragment() {
        let bytes = Self.fragment(offset: 32, data: Array("vcp(10 12)".utf8))
        #expect(DDCPacket.parseCapabilitiesReply(bytes) == .data(offset: 32, bytes: Array("vcp(10 12)".utf8)))
    }

    @Test func parsesFinalEmptyFragment() {
        #expect(DDCPacket.parseCapabilitiesReply(Self.fragment(offset: 64, data: [])) == .data(offset: 64, bytes: []))
    }

    @Test func capabilitiesNullAndCorrupt() {
        #expect(DDCPacket.parseCapabilitiesReply(DDCPacket.nullMessage) == .null)
        var bad = Self.fragment(offset: 0, data: Array("abc".utf8))
        bad[5] ^= 0xFF
        guard case .invalid = DDCPacket.parseCapabilitiesReply(bad) else {
            Issue.record("expected invalid")
            return
        }
    }

    @Test func assemblesCapabilitiesAcrossFragments() {
        let full = "(prot(monitor)type(LCD)model(TEST)vcp(10 12 14(05 08) 60(0F 11) 62)mccs_ver(2.2))"
        let bytes = Array(full.utf8)
        var requested: [UInt16] = []
        let result = DDCPacket.assembleCapabilities { offset in
            requested.append(offset)
            let start = Int(offset)
            let chunk = start < bytes.count ? Array(bytes[start ..< min(bytes.count, start + 32)]) : []
            return DDCPacket.parseCapabilitiesReply(Self.fragment(offset: offset, data: chunk))
        }
        #expect(result == full)
        #expect(requested == [0, 32, 64, UInt16(bytes.count)])
    }

    @Test func assemblyFailsOnOffsetMismatchOrNoReply() {
        #expect(DDCPacket.assembleCapabilities { _ in .data(offset: 99, bytes: [0x41]) } == nil)
        #expect(DDCPacket.assembleCapabilities { _ in nil } == nil)
        #expect(DDCPacket.assembleCapabilities { _ in .null } == nil)
    }

    @Test func assemblyStripsNulPadding() {
        var sent = false
        let result = DDCPacket.assembleCapabilities { offset in
            if sent { return .data(offset: offset, bytes: []) }
            sent = true
            return .data(offset: 0, bytes: Array("vcp(10)".utf8) + [0, 0])
        }
        #expect(result == "vcp(10)")
    }

    // MARK: Hex helpers

    @Test func hexFormatting() {
        #expect(Hex.byte(0x0A) == "0x0A")
        #expect(Hex.bytes([0x6E, 0x80, 0xBE]) == "6E 80 BE")
        #expect(Hex.word(0x3538) == "0x3538")
    }

    @Test(arguments: [("0x10", UInt8(0x10)), ("10", 0x10), ("8D", 0x8D), ("0x0d", 0x0D), ("D6", 0xD6)])
    func parsesCodes(input: String, expected: UInt8) {
        #expect(Hex.parseCode(input) == expected)
    }

    @Test func rejectsBadCodes() {
        #expect(Hex.parseCode("zz") == nil)
        #expect(Hex.parseCode("0x1000") == nil)
    }
}
