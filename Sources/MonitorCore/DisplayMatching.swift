// Pairing a CoreGraphics display with the IORegistry service that can talk DDC to it.
// macOS gives no public link between the two on Apple Silicon, so we compare the identity data
// both sides expose (vendor, product, serial, physical size) and assign greedily by score.
// The same approach as MonitorControl's Arm64DDC.ioregMatchScore, simplified to public data.

import Foundation

/// What CoreGraphics reports about an online display.
public struct DisplayFacts: Equatable, Sendable {
    public var displayID: UInt32
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var widthMM: Double
    public var heightMM: Double

    public init(displayID: UInt32, vendor: UInt32, model: UInt32, serial: UInt32, widthMM: Double, heightMM: Double) {
        self.displayID = displayID
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.widthMM = widthMM
        self.heightMM = heightMM
    }
}

/// What the IORegistry reports about a display service.
public struct ServiceFacts: Equatable, Sendable {
    public var index: Int
    public var vendor: UInt32?
    public var product: UInt32?
    public var serial: UInt32?
    public var widthCM: Int?
    public var heightCM: Int?

    public init(index: Int, vendor: UInt32?, product: UInt32?, serial: UInt32?, widthCM: Int?, heightCM: Int?) {
        self.index = index
        self.vendor = vendor
        self.product = product
        self.serial = serial
        self.widthCM = widthCM
        self.heightCM = heightCM
    }

    /// Build from an "EDID UUID" such as "220E3835-0000-0000-221C-0103803C2278", whose bytes are
    /// EDID bytes 8-11 (vendor, product), 4 zero bytes, then EDID bytes 16-23 (date, version,
    /// input, size, gamma).
    public init?(index: Int, edidUUID: String) {
        let hex = edidUUID.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return nil }
        var b: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let v = UInt8(hex[i ..< j], radix: 16) else { return nil }
            b.append(v)
            i = j
        }
        self.init(index: index,
                  vendor: UInt32(b[0]) << 8 | UInt32(b[1]),
                  product: UInt32(b[2]) | UInt32(b[3]) << 8,
                  serial: nil,
                  widthCM: Int(b[13]),
                  heightCM: Int(b[14]))
    }
}

public enum DisplayMatcher {
    /// Higher is better; 0 means "not this display".
    public static func score(_ display: DisplayFacts, _ service: ServiceFacts) -> Int {
        var score = 0
        if let v = service.vendor {
            guard v == display.vendor else { return 0 }
            score += 4
        }
        if let p = service.product {
            guard p == display.model else { return 0 }
            score += 4
        }
        if let s = service.serial, s != 0, display.serial != 0 {
            score += s == display.serial ? 2 : -2
        }
        if let w = service.widthCM, let h = service.heightCM, w > 0, h > 0, display.widthMM > 0 {
            let dw = abs(display.widthMM / 10 - Double(w))
            let dh = abs(display.heightMM / 10 - Double(h))
            if dw <= 1.5, dh <= 1.5 { score += 1 }
        }
        // A service without identity data can still be paired, but only as a last resort.
        if service.vendor == nil, service.product == nil { return max(score, 1) }
        return max(score, 0)
    }

    /// Assign services to displays, best scores first, each used at most once.
    /// Returns displayID -> service index.
    public static func assign(displays: [DisplayFacts], services: [ServiceFacts]) -> [UInt32: Int] {
        var candidates: [(score: Int, display: UInt32, service: Int, order: Int)] = []
        for (d, display) in displays.enumerated() {
            for service in services {
                let s = score(display, service)
                if s > 0 { candidates.append((s, display.displayID, service.index, d * 1000 + service.index)) }
            }
        }
        candidates.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        var result: [UInt32: Int] = [:]
        var usedServices = Set<Int>()
        for c in candidates where result[c.display] == nil && !usedServices.contains(c.service) {
            result[c.display] = c.service
            usedServices.insert(c.service)
        }
        return result
    }
}
