// VESA Monitor Control Command Set (MCCS 2.2) feature codes and value names.

public enum VCPKind: Sendable {
    /// A range from 0 to the display reported maximum (brightness, contrast, volume, gains).
    case continuous
    /// A choice from a list of values (input source, color preset, power mode).
    case nonContinuous
    /// Write-only action (restore defaults).
    case action
    /// Read-only information (usage time, firmware level).
    case readOnly
}

public struct VCPFeature: Sendable, Equatable {
    public let code: UInt8
    public let name: String
    public let kind: VCPKind
}

public enum MCCS {
    // Codes the app has dedicated UI for.
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    public static let colorPreset: UInt8 = 0x14
    public static let redGain: UInt8 = 0x16
    public static let greenGain: UInt8 = 0x18
    public static let blueGain: UInt8 = 0x1A
    public static let inputSource: UInt8 = 0x60
    public static let volume: UInt8 = 0x62
    public static let sharpness: UInt8 = 0x87
    public static let saturation: UInt8 = 0x8A
    public static let mute: UInt8 = 0x8D
    public static let powerMode: UInt8 = 0xD6
    public static let pictureMode: UInt8 = 0xDC

    /// Sliders shown in the menu below Brightness, in order. Each appears only when the monitor
    /// reports it (volume only on monitors with speakers).
    public static let menuSliders: [UInt8] = [contrast, saturation, volume]
    /// The monitor's own preset modes, shown as pickers.
    public static let menuPickers: [UInt8] = [pictureMode, colorPreset]

    /// Features read during the initial check when the monitor answers but sends no capability string.
    public static let probedFeatures: [UInt8] = [brightness] + menuSliders + menuPickers

    /// Features offered when the monitor never answers but the user has chosen to send DDC/CI
    /// anyway. Only ones nearly every DDC capable monitor implements; volume is never assumed.
    public static let commonFeatures: [UInt8] = [brightness, contrast, colorPreset]

    public static let features: [UInt8: VCPFeature] = {
        let list: [(UInt8, String, VCPKind)] = [
            (0x02, "New Control Value", .readOnly),
            (0x04, "Restore Factory Defaults", .action),
            (0x05, "Restore Factory Brightness/Contrast", .action),
            (0x06, "Restore Factory Geometry", .action),
            (0x08, "Restore Factory Color", .action),
            (0x0B, "Color Temperature Increment", .readOnly),
            (0x0C, "Color Temperature Request", .continuous),
            (0x0E, "Clock", .continuous),
            (0x10, "Brightness", .continuous),
            (0x11, "Flesh Tone Enhancement", .nonContinuous),
            (0x12, "Contrast", .continuous),
            (0x13, "Backlight Control", .continuous),
            (0x14, "Color Preset", .nonContinuous),
            (0x16, "Red Gain", .continuous),
            (0x18, "Green Gain", .continuous),
            (0x1A, "Blue Gain", .continuous),
            (0x1E, "Auto Setup", .nonContinuous),
            (0x20, "Horizontal Position", .continuous),
            (0x30, "Vertical Position", .continuous),
            (0x52, "Active Control", .readOnly),
            (0x54, "Performance Preservation", .nonContinuous),
            (0x59, "Saturation: Red", .continuous),
            (0x5A, "Saturation: Yellow", .continuous),
            (0x5B, "Saturation: Green", .continuous),
            (0x5C, "Saturation: Cyan", .continuous),
            (0x5D, "Saturation: Blue", .continuous),
            (0x5E, "Saturation: Magenta", .continuous),
            (0x60, "Input Source", .nonContinuous),
            (0x62, "Volume", .continuous),
            (0x6C, "Black Level: Red", .continuous),
            (0x6E, "Black Level: Green", .continuous),
            (0x70, "Black Level: Blue", .continuous),
            (0x72, "Gamma", .nonContinuous),
            (0x86, "Display Scaling", .nonContinuous),
            (0x87, "Sharpness", .continuous),
            (0x8A, "Saturation", .continuous),
            (0x8D, "Audio Mute / Screen Blank", .nonContinuous),
            (0xAA, "Screen Orientation", .readOnly),
            (0xAC, "Horizontal Frequency", .readOnly),
            (0xAE, "Vertical Frequency", .readOnly),
            (0xB2, "Sub-Pixel Layout", .readOnly),
            (0xB6, "Display Technology", .readOnly),
            (0xC0, "Display Usage Time", .readOnly),
            (0xC6, "Application Enable Key", .readOnly),
            (0xC8, "Display Controller", .readOnly),
            (0xC9, "Firmware Level", .readOnly),
            (0xCA, "OSD / Button Control", .nonContinuous),
            (0xCC, "OSD Language", .nonContinuous),
            (0xD6, "Power Mode", .nonContinuous),
            (0xDC, "Picture Mode", .nonContinuous),
            (0xDF, "VCP Version", .readOnly),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.0, VCPFeature(code: $0.0, name: $0.1, kind: $0.2)) })
    }()

    public static func name(of code: UInt8) -> String {
        if let f = features[code] { return f.name }
        if code >= 0xE0 { return "Manufacturer Specific \(Hex.byte(code))" }
        return "Feature \(Hex.byte(code))"
    }

    public static func kind(of code: UInt8) -> VCPKind? { features[code]?.kind }

    /// Whether a non-continuous feature currently has the value `choice`. The value lives in the
    /// low byte; some monitors put other data in the high byte.
    public static func isSameChoice(_ current: UInt16?, _ choice: UInt16) -> Bool {
        guard let current else { return false }
        return current & 0xFF == choice & 0xFF
    }

    /// Human readable name for a value of a non-continuous feature.
    public static func valueName(code: UInt8, value: UInt16) -> String {
        switch code {
        case inputSource: return inputSourceName(value)
        case colorPreset: return colorPresetName(value)
        case powerMode: return powerModeName(value)
        case pictureMode: return pictureModeName(value)
        case mute: return value == 1 ? "Muted" : value == 2 ? "Unmuted" : "Value \(value)"
        default: return "Value \(Hex.byte(UInt8(truncatingIfNeeded: value)))"
        }
    }

    public static func inputSourceName(_ value: UInt16) -> String {
        switch value & 0xFF {
        case 0x01: return "VGA 1"
        case 0x02: return "VGA 2"
        case 0x03: return "DVI 1"
        case 0x04: return "DVI 2"
        case 0x05: return "Composite 1"
        case 0x06: return "Composite 2"
        case 0x07: return "S-Video 1"
        case 0x08: return "S-Video 2"
        case 0x09: return "Tuner 1"
        case 0x0A: return "Tuner 2"
        case 0x0B: return "Tuner 3"
        case 0x0C: return "Component 1"
        case 0x0D: return "Component 2"
        case 0x0E: return "Component 3"
        case 0x0F: return "DisplayPort 1"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI 1"
        case 0x12: return "HDMI 2"
        // Not in MCCS, but this is what most vendors use for USB-C.
        case 0x1B: return "USB-C (vendor 0x1B)"
        default: return "Input \(Hex.byte(UInt8(value & 0xFF)))"
        }
    }

    public static func colorPresetName(_ value: UInt16) -> String {
        switch value & 0xFF {
        case 0x01: return "sRGB"
        case 0x02: return "Native"
        case 0x03: return "4000 K"
        case 0x04: return "5000 K"
        case 0x05: return "6500 K"
        case 0x06: return "7500 K"
        case 0x07: return "8200 K"
        case 0x08: return "9300 K"
        case 0x09: return "10000 K"
        case 0x0A: return "11500 K"
        case 0x0B: return "User 1"
        case 0x0C: return "User 2"
        case 0x0D: return "User 3"
        default: return "Preset \(Hex.byte(UInt8(value & 0xFF)))"
        }
    }

    public static func powerModeName(_ value: UInt16) -> String {
        switch value & 0xFF {
        case 0x01: return "On"
        case 0x02: return "Standby"
        case 0x03: return "Suspend"
        case 0x04: return "Off (DPM)"
        case 0x05: return "Off"
        default: return "Mode \(Hex.byte(UInt8(value & 0xFF)))"
        }
    }

    /// MCCS "Display Application" values (VCP 0xDC). Monitors often show their own names for
    /// these in the on-screen menu, and many use only a few of them.
    public static func pictureModeName(_ value: UInt16) -> String {
        switch value & 0xFF {
        case 0x00: return "Standard"
        case 0x01: return "Productivity"
        case 0x02: return "Mixed"
        case 0x03: return "Movie"
        case 0x04: return "User"
        case 0x05: return "Games"
        case 0x06: return "Sports"
        case 0x07: return "Professional"
        case 0x08: return "Standard (medium power)"
        case 0x09: return "Standard (low power)"
        case 0x0A: return "Demonstration"
        case 0xF0: return "Dynamic Contrast"
        default: return "Mode \(Hex.byte(UInt8(value & 0xFF)))"
        }
    }

    /// Values offered for a picker when the capabilities string does not list them.
    public static func defaultValues(for code: UInt8) -> [UInt16] {
        switch code {
        case inputSource: return [0x0F, 0x10, 0x11, 0x12, 0x1B]
        case colorPreset: return [0x01, 0x02, 0x04, 0x05, 0x06, 0x08, 0x0B]
        case pictureMode: return [0x00, 0x01, 0x03, 0x05, 0x04]
        default: return []
        }
    }
}
