// Software dimming state: the pure decisions behind MonitorIO's GammaDimmer.

/// A display's gamma transfer table: one curve per color channel, values from 0 to 1.
public struct GammaTable: Equatable, Sendable {
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]

    public init(red: [Float], green: [Float], blue: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The table with every value multiplied by `factor` (0 to 1).
    public func scaled(by factor: Double) -> GammaTable {
        GammaTable(red: BrightnessMath.scale(red, by: factor),
                   green: BrightnessMath.scale(green, by: factor),
                   blue: BrightnessMath.scale(blue, by: factor))
    }

    /// Whether two tables are the same, allowing for rounding when the display stores a table.
    public func matches(_ other: GammaTable, tolerance: Float = 1e-4) -> Bool {
        Self.matches(red, other.red, tolerance) && Self.matches(green, other.green, tolerance)
            && Self.matches(blue, other.blue, tolerance)
    }

    private static func matches(_ a: [Float], _ b: [Float], _ tolerance: Float) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }
}

/// What Candela remembers about a display it dims.
public struct DimmingState: Equatable, Sendable {
    /// The display's own table, from before Candela dimmed it: what 100% puts back.
    public var original: GammaTable
    /// The table Candela set, as the display reported it back.
    public var applied: GammaTable

    public init(original: GammaTable, applied: GammaTable) {
        self.original = original
        self.applied = applied
    }

    /// True when the display no longer shows Candela's table: macOS or another app replaced it,
    /// for example with a new color profile or after wake.
    public func wasReplaced(byCurrent current: GammaTable) -> Bool {
        !current.matches(applied)
    }

    /// The table to treat as the display's own, given what the display shows now. While it
    /// still shows Candela's table, the remembered original stands. Once something replaced it,
    /// the replacement is the display's own table, and restoring the old one would undo it.
    public static func original(current: GammaTable, state: DimmingState?) -> GammaTable {
        guard let state, !state.wasReplaced(byCurrent: current) else { return current }
        return state.original
    }

    /// True when Candela's table was replaced and the replacement has stopped changing: it is the
    /// same table as at the previous look. During a display change macOS can fade the picture
    /// through the gamma table, and a table caught mid-fade must not become the original.
    public func hasSettledReplacement(current: GammaTable, previous: GammaTable?) -> Bool {
        guard let previous, wasReplaced(byCurrent: current) else { return false }
        return current.matches(previous)
    }
}
