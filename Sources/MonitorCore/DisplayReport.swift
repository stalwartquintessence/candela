// A plain, ordered description of a display used by both the info window and `candelactl info`,
// so the two always show the same facts.

import Foundation

public struct DisplayReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public let rows: [Row]
        public var id: String { title }
        public init(_ title: String, _ rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public let title: String
    public let sections: [Section]

    /// Everything the report can show. All fields are optional so partial data still renders.
    public struct Input: Sendable {
        public var name: String
        public var displayID: UInt32?
        public var isMain: Bool = false
        public var resolution: String?
        public var refreshRate: Double?
        public var transportUpstream: String?
        public var transportDownstream: String?
        public var productName: String?
        public var alphanumericSerial: String?
        public var edid: EDID?
        public var ddcStatus: String
        public var ddcFraming: String?
        public var controlMethod: String
        public var capabilities: Capabilities?
        public var values: [UInt8: VCPValue] = [:]

        public init(name: String, ddcStatus: String, controlMethod: String) {
            self.name = name
            self.ddcStatus = ddcStatus
            self.controlMethod = controlMethod
        }
    }

    public init(title: String, sections: [Section]) {
        self.title = title
        self.sections = sections
    }

    public static func build(_ input: Input) -> DisplayReport {
        var sections: [Section] = []

        var general: [Row] = [Row("Name", input.name)]
        if let e = input.edid {
            general.append(Row("Manufacturer", "\(e.manufacturerID) (\(PNPVendors.name(for: e.manufacturerID)))"))
            general.append(Row("Product code", "\(e.productCode) (\(Hex.word(e.productCode)))"))
        }
        if let serial = input.alphanumericSerial ?? input.edid?.serialString {
            general.append(Row("Serial number", serial))
        } else if let n = input.edid?.serialNumber, n != 0 {
            general.append(Row("Serial number", "\(n)"))
        }
        if let e = input.edid {
            let date = e.isModelYear ? "Model year \(e.year)" : e.week.map { "Week \($0), \(e.year)" } ?? "\(e.year)"
            general.append(Row("Manufactured", date))
            if let d = e.diagonalInches {
                general.append(Row("Screen size", String(format: "%.1f\" (%d x %d cm)", d, e.widthCM, e.heightCM)))
            }
        }
        sections.append(Section("Display", general))

        var video: [Row] = []
        if let r = input.resolution { video.append(Row("Current mode", r)) }
        if let hz = input.refreshRate, hz > 0 { video.append(Row("Refresh rate", String(format: "%.2f Hz", hz))) }
        if let t = input.edid?.preferredTiming {
            video.append(Row("Native mode", String(format: "%d x %d @ %.2f Hz", t.horizontalActive, t.verticalActive, t.refreshRate)))
        }
        if let l = input.edid?.rangeLimits {
            video.append(Row("Supported refresh", "\(l.minVerticalHz) to \(l.maxVerticalHz) Hz"))
        }
        if let bits = input.edid?.bitsPerColor { video.append(Row("Color depth", "\(bits) bits per color")) }
        if let g = input.edid?.gamma { video.append(Row("Gamma", String(format: "%.2f", g))) }
        if !video.isEmpty { sections.append(Section("Video", video)) }

        var connection: [Row] = []
        if let id = input.displayID { connection.append(Row("Display ID", "\(id)\(input.isMain ? " (main)" : "")")) }
        if input.transportUpstream != nil || input.transportDownstream != nil {
            connection.append(Row("Transport", transportDescription(up: input.transportUpstream, down: input.transportDownstream)))
        }
        if let iface = input.edid?.videoInterface { connection.append(Row("EDID interface", iface)) }
        if !connection.isEmpty { sections.append(Section("Connection", connection)) }

        var ddc: [Row] = [Row("Status", input.ddcStatus), Row("Control method", input.controlMethod)]
        if let f = input.ddcFraming { ddc.append(Row("Framing", f)) }
        if let c = input.capabilities {
            if let model = c.model { ddc.append(Row("Reported model", model)) }
            if let type = c.type { ddc.append(Row("Type", type)) }
            if let v = c.mccsVersion { ddc.append(Row("MCCS version", v)) }
            ddc.append(Row("Features", "\(c.vcpCodes.count) supported"))
        }
        sections.append(Section("DDC/CI", ddc))

        if let c = input.capabilities, !c.vcpCodes.isEmpty {
            let rows = c.vcpCodes.map { code -> Row in
                var value = MCCS.name(of: code)
                if let v = input.values[code] {
                    if MCCS.kind(of: code) == .nonContinuous {
                        value += ": " + MCCS.valueName(code: code, value: v.current)
                    } else {
                        value += ": \(v.current) of \(v.maximum)"
                    }
                }
                if let allowed = c.vcp[code], !allowed.isEmpty {
                    value += " [" + allowed.map { MCCS.valueName(code: code, value: $0) }.joined(separator: ", ") + "]"
                }
                return Row(Hex.byte(code), value)
            }
            sections.append(Section("Supported Features", rows))
        }

        if let e = input.edid {
            var rows = [Row("Version", e.version),
                        Row("Checksum", e.checksumValid ? "valid" : "INVALID"),
                        Row("Extensions", e.extensionTags.isEmpty ? "\(e.extensionCount)" : e.extensionTags.map(EDID.extensionName).joined(separator: ", "))]
            if let name = e.displayName { rows.insert(Row("Name descriptor", name), at: 0) }
            sections.append(Section("EDID", rows))
        }

        return DisplayReport(title: input.name, sections: sections)
    }

    public static func transportDescription(up: String?, down: String?) -> String {
        switch (up, down) {
        case let (u?, d?) where u == d: return u
        case let (u?, d?):
            // Upstream DP with downstream HDMI is a DisplayPort to HDMI converter, for example the
            // built-in HDMI port of Apple Silicon MacBook Pro, Mac mini and Mac Studio.
            return "\(u) to \(d) (converter)"
        case let (u?, nil): return u
        case let (nil, d?): return d
        default: return "Unknown"
        }
    }

    /// Plain text rendering for the clipboard and the CLI.
    public var plainText: String {
        var lines = [title, String(repeating: "=", count: title.count)]
        for section in sections {
            lines.append("")
            lines.append(section.title)
            let width = section.rows.map(\.label.count).max() ?? 0
            for row in section.rows {
                lines.append("  " + row.label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + row.value)
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A short list of common PNP vendor IDs for friendlier display. Unknown IDs show as-is.
public enum PNPVendors {
    static let names: [String: String] = [
        "AAC": "Acer", "ACR": "Acer", "ACI": "Asus", "AUS": "Asus", "AOC": "AOC", "APP": "Apple",
        "BNQ": "BenQ", "DEL": "Dell", "EIZ": "Eizo", "ENC": "Eizo", "GSM": "LG", "GBT": "Gigabyte",
        "HPN": "HP", "HWP": "HP", "HKC": "HKC", "IVM": "Iiyama", "LEN": "Lenovo", "LGD": "LG Display",
        "MEI": "Panasonic", "MSI": "MSI", "NEC": "NEC", "PHL": "Philips", "SAM": "Samsung",
        "SNY": "Sony", "VSC": "ViewSonic", "XMI": "Xiaomi", "HSD": "HannStar", "SHP": "Sharp",
    ]

    public static func name(for id: String) -> String { names[id] ?? "unknown vendor" }
}
