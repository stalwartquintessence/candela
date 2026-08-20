// Decoder for the EDID 1.3 / 1.4 base block (VESA E-EDID). Extension blocks are counted and
// identified but not decoded.

import Foundation

public struct EDID: Equatable, Sendable {
    public struct DetailedTiming: Equatable, Sendable {
        public let pixelClockKHz: Int
        public let horizontalActive: Int
        public let verticalActive: Int
        public let horizontalBlanking: Int
        public let verticalBlanking: Int
        public let widthMM: Int
        public let heightMM: Int

        public var refreshRate: Double {
            let total = Double((horizontalActive + horizontalBlanking) * (verticalActive + verticalBlanking))
            return total > 0 ? Double(pixelClockKHz) * 1000 / total : 0
        }
    }

    public struct RangeLimits: Equatable, Sendable {
        public let minVerticalHz: Int
        public let maxVerticalHz: Int
        public let minHorizontalKHz: Int
        public let maxHorizontalKHz: Int
        public let maxPixelClockMHz: Int
    }

    public let bytes: [UInt8]

    /// Three letter PNP manufacturer ID, for example "HPN" for HP, "DEL" for Dell.
    public let manufacturerID: String
    public let productCode: UInt16
    public let serialNumber: UInt32
    /// Week of manufacture (1 to 54), nil when unspecified or when `isModelYear` is set.
    public let week: Int?
    public let year: Int
    /// True when byte 16 is 0xFF, meaning `year` is a model year rather than a manufacture date.
    public let isModelYear: Bool
    public let version: String
    public let isDigital: Bool
    /// Bits per color, EDID 1.4 digital displays only.
    public let bitsPerColor: Int?
    /// Video interface, EDID 1.4 digital displays only ("HDMI", "DisplayPort", ...).
    public let videoInterface: String?
    /// Maximum image size in centimeters (0 when unknown or variable).
    public let widthCM: Int
    public let heightCM: Int
    public let gamma: Double?
    public let displayName: String?
    public let serialString: String?
    public let text: String?
    public let preferredTiming: DetailedTiming?
    public let rangeLimits: RangeLimits?
    public let extensionCount: Int
    /// Tags of the extension blocks present in `bytes` (0x02 = CTA-861, 0x70 = DisplayID).
    public let extensionTags: [UInt8]
    public let checksumValid: Bool

    public static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    public var diagonalInches: Double? {
        guard widthCM > 0, heightCM > 0 else { return nil }
        return (Double(widthCM * widthCM + heightCM * heightCM)).squareRoot() / 2.54
    }

    /// Returns nil when the data is shorter than 128 bytes or the header is wrong.
    public init?(bytes: [UInt8]) {
        guard bytes.count >= 128, Array(bytes[0 ..< 8]) == EDID.header else { return nil }
        self.bytes = bytes

        let mfg = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        manufacturerID = EDID.decodeManufacturer(mfg)
        productCode = UInt16(bytes[10]) | UInt16(bytes[11]) << 8
        serialNumber = UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24

        isModelYear = bytes[16] == 0xFF
        week = (bytes[16] == 0 || bytes[16] == 0xFF) ? nil : Int(bytes[16])
        year = Int(bytes[17]) + 1990
        version = "\(bytes[18]).\(bytes[19])"

        isDigital = bytes[20] & 0x80 != 0
        if isDigital, bytes[18] == 1, bytes[19] >= 4 {
            let depthBits = Int((bytes[20] >> 4) & 0x07)
            bitsPerColor = (1 ... 6).contains(depthBits) ? 4 + depthBits * 2 : nil
            switch bytes[20] & 0x0F {
            case 1: videoInterface = "DVI"
            case 2: videoInterface = "HDMI-a"
            case 3: videoInterface = "HDMI-b"
            case 4: videoInterface = "MDDI"
            case 5: videoInterface = "DisplayPort"
            default: videoInterface = nil
            }
        } else {
            bitsPerColor = nil
            videoInterface = nil
        }

        widthCM = Int(bytes[21])
        heightCM = Int(bytes[22])
        gamma = bytes[23] == 0xFF ? nil : (Double(bytes[23]) + 100) / 100

        var name: String?
        var serial: String?
        var text: String?
        var timing: DetailedTiming?
        var limits: RangeLimits?
        for start in stride(from: 54, through: 108, by: 18) {
            let d = Array(bytes[start ..< start + 18])
            if d[0] != 0 || d[1] != 0 {
                if timing == nil { timing = EDID.decodeTiming(d) }
                continue
            }
            switch d[3] {
            case 0xFC: name = EDID.decodeText(d)
            case 0xFF: serial = EDID.decodeText(d)
            case 0xFE: text = EDID.decodeText(d)
            case 0xFD:
                limits = RangeLimits(minVerticalHz: Int(d[5]), maxVerticalHz: Int(d[6]),
                                     minHorizontalKHz: Int(d[7]), maxHorizontalKHz: Int(d[8]),
                                     maxPixelClockMHz: Int(d[9]) * 10)
            default: break
            }
        }
        displayName = name
        serialString = serial
        self.text = text
        preferredTiming = timing
        rangeLimits = limits

        extensionCount = Int(bytes[126])
        var tags: [UInt8] = []
        var block = 128
        while block + 128 <= bytes.count, tags.count < extensionCount {
            tags.append(bytes[block])
            block += 128
        }
        extensionTags = tags
        checksumValid = bytes[0 ..< 128].reduce(UInt8(0), &+) == 0
    }

    /// Five bits per letter, 1 = "A".
    public static func decodeManufacturer(_ value: UInt16) -> String {
        let letters = [(value >> 10) & 0x1F, (value >> 5) & 0x1F, value & 0x1F]
        return String(letters.map { v -> Character in
            (1 ... 26).contains(v) ? Character(UnicodeScalar(UInt8(v) + 64)) : "?"
        })
    }

    static func decodeText(_ d: [UInt8]) -> String? {
        let raw = d[5 ..< 18].prefix { $0 != 0x0A }
        let s = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    static func decodeTiming(_ d: [UInt8]) -> DetailedTiming {
        DetailedTiming(
            pixelClockKHz: (Int(d[0]) | Int(d[1]) << 8) * 10,
            horizontalActive: Int(d[2]) | Int(d[4] & 0xF0) << 4,
            verticalActive: Int(d[5]) | Int(d[7] & 0xF0) << 4,
            horizontalBlanking: Int(d[3]) | Int(d[4] & 0x0F) << 8,
            verticalBlanking: Int(d[6]) | Int(d[7] & 0x0F) << 8,
            widthMM: Int(d[12]) | Int(d[14] & 0xF0) << 4,
            heightMM: Int(d[13]) | Int(d[14] & 0x0F) << 8
        )
    }

    public static func extensionName(_ tag: UInt8) -> String {
        switch tag {
        case 0x02: return "CTA-861"
        case 0x10: return "Video Timing Block"
        case 0x40: return "DI-EXT"
        case 0x50: return "LS-EXT"
        case 0x60: return "DPVL"
        case 0x70: return "DisplayID"
        case 0xF0: return "Block Map"
        default: return "Extension \(Hex.byte(tag))"
        }
    }
}
