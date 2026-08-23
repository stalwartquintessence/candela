// Finds external displays and the IORegistry services behind them.
//
// On Apple Silicon each framebuffer (AppleCLCD2 or IOMobileFramebufferShim) is followed in the
// IOService plane by the DCPAVServiceProxy that carries its I2C/DDC channel, so walking the plane
// in order pairs them (approach from MonitorControl's Arm64DDC, MIT). Raw EDIDs live elsewhere
// (IOPortTransportState* entries) and are paired with displays by identity instead of position.

import CoreGraphics
import Foundation
import IOKit
import MonitorCore

/// Registry data about one display pipeline.
public struct AVServiceInfo {
    public let index: Int
    public let edidUUID: String?
    public let productName: String?
    public let alphanumericSerial: String?
    public let vendor: UInt32?
    public let product: UInt32?
    public let serial: UInt32?
    public let transportUpstream: String?
    public let transportDownstream: String?
    /// "External" or "Embedded".
    public let location: String?
    /// IOAVService handle, only for external services.
    public let service: CFTypeRef?

    var facts: ServiceFacts {
        let uuidFacts = edidUUID.flatMap { ServiceFacts(index: index, edidUUID: $0) }
        return ServiceFacts(index: index,
                            vendor: vendor ?? uuidFacts?.vendor,
                            product: product ?? uuidFacts?.product,
                            serial: serial,
                            widthCM: uuidFacts?.widthCM,
                            heightCM: uuidFacts?.heightCM)
    }
}

/// Everything known about one online external display.
public struct ExternalDisplay {
    public let displayID: CGDirectDisplayID
    public let facts: DisplayFacts
    public let edid: EDID?
    public let avService: AVServiceInfo?
    public let isMain: Bool

    /// Stable identity used as the key for saved settings. Uses the alphanumeric serial when
    /// available because many monitors report a placeholder numeric serial (HP uses 0x01010101).
    public var settingsKey: String {
        let serial = avService?.alphanumericSerial ?? edid?.serialString ?? String(facts.serial)
        return "\(facts.vendor)-\(facts.model)-\(serial)"
    }

    public var name: String {
        avService?.productName ?? edid?.displayName ?? "Display \(displayID)"
    }

    /// True when macOS exposes an I2C channel (IOAVService) for this display.
    public var hasDDCService: Bool { avService?.service != nil }
}

public enum DisplayDiscovery {
    /// Active external displays with their matched registry data.
    public static func externalDisplays() -> [ExternalDisplay] {
        let ids = activeDisplayIDs().filter { CGDisplayIsBuiltin($0) == 0 }
        let facts = ids.map(displayFacts)
        let services = avServices().filter { $0.location == "External" }
        let edids = registryEDIDs()

        let serviceMatch = DisplayMatcher.assign(displays: facts, services: services.map(\.facts))
        let edidFacts = edids.enumerated().map { i, e in
            ServiceFacts(index: i, vendor: vendorNumber(e.manufacturerID), product: UInt32(e.productCode),
                         serial: e.serialNumber, widthCM: e.widthCM, heightCM: e.heightCM)
        }
        let edidMatch = DisplayMatcher.assign(displays: facts, services: edidFacts)
        let main = CGMainDisplayID()

        return facts.map { f in
            ExternalDisplay(displayID: f.displayID,
                            facts: f,
                            edid: edidMatch[f.displayID].map { edids[$0] },
                            avService: serviceMatch[f.displayID].flatMap { i in services.first { $0.index == i } },
                            isMain: f.displayID == main)
        }
    }

    public static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func displayFacts(_ id: CGDirectDisplayID) -> DisplayFacts {
        let size = CGDisplayScreenSize(id)
        return DisplayFacts(displayID: id, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                            serial: CGDisplaySerialNumber(id), widthMM: size.width, heightMM: size.height)
    }

    /// The 16-bit EISA vendor number for a three letter PNP ID (inverse of EDID.decodeManufacturer).
    static func vendorNumber(_ id: String) -> UInt32? {
        let letters = Array(id.utf8)
        guard letters.count == 3, letters.allSatisfy({ (65 ... 90).contains($0) }) else { return nil }
        return letters.reduce(UInt32(0)) { $0 << 5 | UInt32($1 - 64) }
    }

    // MARK: IORegistry

    /// Walk the IOService plane, pairing each framebuffer with the DCPAVServiceProxy after it.
    public static func avServices() -> [AVServiceInfo] {
        var results: [AVServiceInfo] = []
        var framebuffer: [String: Any]?
        forEachServiceEntry { entry, className in
            switch className {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                framebuffer = [:]
                framebuffer?["uuid"] = property(entry, "EDID UUID") as? String
                if let attrs = property(entry, "DisplayAttributes") as? [String: Any],
                   let product = attrs["ProductAttributes"] as? [String: Any] {
                    framebuffer?["product"] = product
                }
                if let transport = property(entry, "Transport") as? [String: Any] {
                    framebuffer?["transport"] = transport
                }
            case "DCPAVServiceProxy":
                let location = property(entry, "Location") as? String
                let product = framebuffer?["product"] as? [String: Any]
                let transport = framebuffer?["transport"] as? [String: Any]
                var service: CFTypeRef?
                if location == "External" {
                    service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                }
                results.append(AVServiceInfo(
                    index: results.count,
                    edidUUID: framebuffer?["uuid"] as? String,
                    productName: product?["ProductName"] as? String,
                    alphanumericSerial: product?["AlphanumericSerialNumber"] as? String,
                    vendor: (product?["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                    product: (product?["ProductID"] as? NSNumber)?.uint32Value,
                    serial: (product?["SerialNumber"] as? NSNumber)?.uint32Value,
                    transportUpstream: transport?["Upstream"] as? String,
                    transportDownstream: transport?["Downstream"] as? String,
                    location: location,
                    service: service))
            default:
                break
            }
        }
        return results
    }

    /// Raw EDIDs published by the display port transport entries.
    public static func registryEDIDs() -> [EDID] {
        var edids: [EDID] = []
        forEachServiceEntry { entry, className in
            guard className.hasPrefix("IOPortTransportState"),
                  let data = property(entry, "EDID") as? Data,
                  let edid = EDID(bytes: [UInt8](data)) else { return }
            if !edids.contains(where: { $0.bytes == edid.bytes }) { edids.append(edid) }
        }
        return edids
    }

    private static func forEachServiceEntry(_ body: (io_registry_entry_t, String) -> Void) {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            body(entry, className(of: entry))
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }

    private static func className(of entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(entry, &buffer)
        return String(cString: buffer)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
