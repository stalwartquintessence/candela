import Testing
@testable import MonitorCore

/// Builds a synthetic but valid EDID 1.4 base block. No real device data is used in tests.
struct EDIDBuilder {
    var manufacturer = "HPN"
    var product: UInt16 = 0x1234
    var serial: UInt32 = 0x0101_0101
    var week: UInt8 = 34
    var yearOffset: UInt8 = 28 // 2018
    var versionMinor: UInt8 = 4
    var inputByte: UInt8 = 0xA5 // digital, 8 bits per color, DisplayPort
    var widthCM: UInt8 = 60
    var heightCM: UInt8 = 34
    var name: String? = "Test 27"
    var serialText: String? = "SYN0001"
    var extensions: UInt8 = 0

    func build() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 128)
        b[0 ..< 8] = ArraySlice(EDID.header)
        let letters = Array(manufacturer.utf8).map { UInt16($0 - 64) }
        let mfg = letters[0] << 10 | letters[1] << 5 | letters[2]
        b[8] = UInt8(mfg >> 8); b[9] = UInt8(mfg & 0xFF)
        b[10] = UInt8(product & 0xFF); b[11] = UInt8(product >> 8)
        for i in 0 ..< 4 { b[12 + i] = UInt8((serial >> (8 * UInt32(i))) & 0xFF) }
        b[16] = week; b[17] = yearOffset
        b[18] = 1; b[19] = versionMinor
        b[20] = inputByte; b[21] = widthCM; b[22] = heightCM; b[23] = 120 // gamma 2.20

        // Descriptor 1: 3840 x 2160 @ 60 Hz (594 MHz, 4400 x 2250 total).
        let dtd: [UInt8] = [0x08, 0xE8, 0x00, 0x30, 0xF2, 0x70, 0x5A, 0x80, 0, 0, 0, 0, 0x58, 0x54, 0x21, 0, 0, 0x1E]
        b[54 ..< 72] = ArraySlice(dtd)
        b[72 ..< 90] = ArraySlice(Self.text(0xFC, name))
        b[90 ..< 108] = ArraySlice(Self.text(0xFF, serialText))
        b[108 ..< 126] = ArraySlice([0, 0, 0, 0xFD, 0, 24, 60, 30, 140, 60, 0, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20])
        b[126] = extensions
        b[127] = UInt8((256 - Int(b[0 ..< 127].reduce(UInt8(0), &+))) & 0xFF)
        return b
    }

    static func text(_ tag: UInt8, _ s: String?) -> [UInt8] {
        guard let s else { return [0, 0, 0, 0x10] + [UInt8](repeating: 0, count: 14) }
        var bytes = Array(s.utf8.prefix(13))
        if bytes.count < 13 { bytes.append(0x0A) }
        while bytes.count < 13 { bytes.append(0x20) }
        return [0, 0, 0, tag, 0] + bytes
    }
}

@Suite("EDID")
struct EDIDTests {
    @Test func decodesIdentity() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder().build()))
        #expect(edid.manufacturerID == "HPN")
        #expect(edid.productCode == 0x1234)
        #expect(edid.serialNumber == 0x0101_0101)
        #expect(edid.week == 34)
        #expect(edid.year == 2018)
        #expect(edid.version == "1.4")
        #expect(edid.checksumValid)
    }

    @Test func decodesDescriptors() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder().build()))
        #expect(edid.displayName == "Test 27")
        #expect(edid.serialString == "SYN0001")
        #expect(edid.rangeLimits == EDID.RangeLimits(minVerticalHz: 24, maxVerticalHz: 60, minHorizontalKHz: 30, maxHorizontalKHz: 140, maxPixelClockMHz: 600))
    }

    @Test func decodesPreferredTiming() throws {
        let timing = try #require(EDID(bytes: EDIDBuilder().build())?.preferredTiming)
        #expect(timing.horizontalActive == 3840)
        #expect(timing.verticalActive == 2160)
        #expect(timing.pixelClockKHz == 594_000)
        #expect(abs(timing.refreshRate - 60) < 0.01)
        #expect(timing.widthMM == 600)
        #expect(timing.heightMM == 340)
    }

    @Test func decodesVideoInput() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder().build()))
        #expect(edid.isDigital)
        #expect(edid.bitsPerColor == 8)
        #expect(edid.videoInterface == "DisplayPort")
        #expect(edid.gamma == 2.2)
    }

    @Test func videoInterfaceOnlyForEDID14() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder(versionMinor: 3).build()))
        #expect(edid.version == "1.3")
        #expect(edid.videoInterface == nil)
        #expect(edid.bitsPerColor == nil)
    }

    @Test func computesDiagonal() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder().build()))
        let diagonal = try #require(edid.diagonalInches)
        #expect(abs(diagonal - 27.15) < 0.05)
        #expect(EDID(bytes: EDIDBuilder(widthCM: 0, heightCM: 0).build())?.diagonalInches == nil)
    }

    @Test func modelYearAndUnknownWeek() throws {
        #expect(EDID(bytes: EDIDBuilder(week: 0xFF).build())?.isModelYear == true)
        #expect(EDID(bytes: EDIDBuilder(week: 0xFF).build())?.week == nil)
        #expect(EDID(bytes: EDIDBuilder(week: 0).build())?.week == nil)
    }

    @Test func missingDescriptorsAreNil() throws {
        let edid = try #require(EDID(bytes: EDIDBuilder(name: nil, serialText: nil).build()))
        #expect(edid.displayName == nil)
        #expect(edid.serialString == nil)
    }

    @Test func detectsBadChecksum() throws {
        var bytes = EDIDBuilder().build()
        bytes[20] ^= 0x01
        #expect(EDID(bytes: bytes)?.checksumValid == false)
    }

    @Test func identifiesExtensionBlocks() throws {
        var bytes = EDIDBuilder(extensions: 1).build()
        var ext = [UInt8](repeating: 0, count: 128)
        ext[0] = 0x02
        bytes += ext
        let edid = try #require(EDID(bytes: bytes))
        #expect(edid.extensionCount == 1)
        #expect(edid.extensionTags == [0x02])
        #expect(EDID.extensionName(0x02) == "CTA-861")
    }

    @Test func rejectsInvalidData() {
        #expect(EDID(bytes: []) == nil)
        #expect(EDID(bytes: [UInt8](repeating: 0, count: 128)) == nil)
        #expect(EDID(bytes: Array(EDIDBuilder().build().prefix(100))) == nil)
    }

    @Test(arguments: [("DEL", UInt16(0x10AC)), ("HPN", 0x220E), ("SAM", 0x4C2D), ("GSM", 0x1E6D)])
    func decodesManufacturerIDs(expected: String, raw: UInt16) {
        #expect(EDID.decodeManufacturer(raw) == expected)
    }
}
