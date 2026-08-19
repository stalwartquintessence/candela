import Testing
@testable import MonitorCore

@Suite("Capabilities string")
struct CapabilitiesTests {
    // Representative of a typical office monitor (format per MCCS 2.2).
    static let typical = "(prot(monitor)type(LCD)model(P2419H)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B 0C) 16 18 1A 52 60(0F 11 ) AA(01 02 04) AC AE B2 B6 C6 C8 C9 D6(01 04 05) DC(00 02 03 05) DF E0 E1 E2(00 01 02 04 0E 12 14 19) F0(00 08) F1 F2 FD)mswhql(1)asset_eep(40)mccs_ver(2.1))"

    @Test func parsesTopLevelFields() throws {
        let caps = try #require(Capabilities.parse(Self.typical))
        #expect(caps.model == "P2419H")
        #expect(caps.type == "LCD")
        #expect(caps.mccsVersion == "2.1")
        #expect(caps.fields["prot"] == "monitor")
    }

    @Test func parsesVCPCodesAndValues() throws {
        let caps = try #require(Capabilities.parse(Self.typical))
        #expect(caps.supports(0x10))
        #expect(caps.supports(0x12))
        #expect(!caps.supports(0x62))
        #expect(caps.vcp[0x14] == [0x05, 0x08, 0x0B, 0x0C])
        #expect(caps.vcp[0x60] == [0x0F, 0x11])
        #expect(caps.vcp[0x10] == [])
        #expect(caps.vcp[0xD6] == [0x01, 0x04, 0x05])
    }

    @Test func parsesCommands() throws {
        let caps = try #require(Capabilities.parse(Self.typical))
        #expect(caps.commands == [0x01, 0x02, 0x03, 0x07, 0x0C, 0xE3, 0xF3])
    }

    @Test func handlesCodesWithoutSpaces() throws {
        let caps = try #require(Capabilities.parse("(vcp(1012146062)model(X))"))
        #expect(caps.vcpCodes == [0x10, 0x12, 0x14, 0x60, 0x62])
    }

    @Test func handlesMissingOuterParenthesesAndTrailingGarbage() throws {
        let caps = try #require(Capabilities.parse("prot(monitor)type(lcd)model(X)vcp(10 12)mccs_ver(2.2)\u{0}junk"))
        #expect(caps.vcpCodes == [0x10, 0x12])
        #expect(caps.mccsVersion == "2.2")
    }

    @Test func handlesUnbalancedParentheses() throws {
        let caps = try #require(Capabilities.parse("(vcp(10 12 60(11 0F)"))
        #expect(caps.vcpCodes == [0x10, 0x12, 0x60])
        #expect(caps.vcp[0x60] == [0x11, 0x0F])
    }

    @Test func keysAreCaseInsensitive() throws {
        let caps = try #require(Capabilities.parse("(MODEL(Z27)VCP(10))"))
        #expect(caps.model == "Z27")
        #expect(caps.supports(0x10))
    }

    @Test func rejectsNonsense() {
        #expect(Capabilities.parse("hello") == nil)
        #expect(Capabilities.parse("") == nil)
    }
}
