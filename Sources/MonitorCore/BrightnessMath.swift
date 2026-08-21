// Pure math for brightness steps, raw DDC conversion and software (gamma) dimming.

public enum BrightnessMath {
    /// macOS uses 16 steps per full range, 64 with Option+Shift.
    public static let coarseSteps = 16.0
    public static let fineSteps = 64.0

    /// Next level (0 to 100) after a brightness key press, snapped to the step grid like macOS.
    public static func step(from level: Double, up: Bool, fine: Bool) -> Double {
        let size = 100.0 / (fine ? fineSteps : coarseSteps)
        let index = (clamp(level) / size).rounded() + (up ? 1 : -1)
        return clamp(index * size)
    }

    public static func clamp(_ level: Double) -> Double { min(100, max(0, level)) }

    /// Percent (0 to 100) to the display's raw range (0 to max).
    public static func raw(fromPercent percent: Double, maximum: UInt16) -> UInt16 {
        guard maximum > 0 else { return 0 }
        return UInt16((clamp(percent) / 100 * Double(maximum)).rounded())
    }

    /// Raw value to percent (0 to 100).
    public static func percent(fromRaw raw: UInt16, maximum: UInt16) -> Double {
        guard maximum > 0 else { return 0 }
        return clamp(Double(raw) / Double(maximum) * 100)
    }

    /// Lowest gamma multiplier software dimming will use, so 0% never produces a black screen
    /// the user cannot see to recover from.
    public static let minimumGammaFactor = 0.08

    /// Gamma multiplier for a software brightness level.
    public static func gammaFactor(forPercent percent: Double) -> Double {
        minimumGammaFactor + (1 - minimumGammaFactor) * clamp(percent) / 100
    }

    /// Scale a gamma transfer table, keeping values in 0 to 1.
    public static func scale(_ table: [Float], by factor: Double) -> [Float] {
        let f = Float(max(0, min(1, factor)))
        return table.map { min(1, max(0, $0 * f)) }
    }
}
