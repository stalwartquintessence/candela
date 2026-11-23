// Where the brightness indicator appears on a screen.

/// macOS 26 centers its brightness indicator under the menu bar icon it comes from, Control
/// Center's, and keeps it a little way inside the screen's edges. Candela's indicator comes from
/// Candela's own icon in the same way, and sits at the top right without one.
public enum IndicatorPlacement {
    /// Closest the indicator comes to either side of the screen. It also sits this far below the
    /// menu bar.
    public static let margin = 8.0

    /// The left edge of an indicator `width` wide on a screen whose visible area runs from
    /// `screenMinX` to `screenMaxX`. `iconMidX` is the center of the menu bar icon it comes from,
    /// or nil when there is no icon.
    public static func minX(width: Double, iconMidX: Double?, screenMinX: Double, screenMaxX: Double) -> Double {
        let lowest = screenMinX + margin
        let highest = screenMaxX - margin - width
        guard let iconMidX else { return max(highest, lowest) }
        return max(min(iconMidX - width / 2, highest), lowest)
    }

    /// The center of a menu bar icon on a screen whose right edge is `screenMaxX`, given how far
    /// the icon sits from the right edge of the screen it was measured on. Every display's menu
    /// bar shows the same icons in the same places, counted from the right.
    public static func iconMidX(distanceFromRightEdge: Double, screenMaxX: Double) -> Double {
        screenMaxX - distanceFromRightEdge
    }
}
