// Recognizes a shaken pointer, the gesture people use when they cannot find it, and decides what
// a shake does to the brightness of the display under it.

/// Finds quick back-and-forth strokes in pointer movement. Each axis is followed on its own, so a
/// sideways, an up-and-down or a diagonal shake all count. It works on the movement itself rather
/// than the pointer's position, so a shake against the edge of the screen counts too.
public struct PointerShake: Sendable {
    /// A stroke must cover at least this many points before the pointer turns back. Smaller
    /// wobbles are ordinary use.
    public static let minimumStroke = 50.0
    /// The most time between two turns, in seconds. Slower back and forth is ordinary use.
    public static let maximumTurnInterval = 0.3
    /// Turns in a row that make a shake: about three quick back-and-forths.
    public static let turnsNeeded = 5

    private var horizontal = Axis()
    private var vertical = Axis()

    public init() {}

    /// Adds one pointer movement of `dx`, `dy` points at `time` seconds. Returns true when this
    /// movement completes a shake; the next shake is then counted from scratch.
    public mutating func move(dx: Double, dy: Double, at time: Double) -> Bool {
        let sideways = horizontal.move(dx, at: time)
        let upAndDown = vertical.move(dy, at: time)
        guard sideways || upAndDown else { return false }
        reset()
        return true
    }

    /// Forgets the movement so far, for example after a click.
    public mutating func reset() {
        horizontal = Axis()
        vertical = Axis()
    }
}

/// Movement along one axis.
private struct Axis: Sendable {
    /// Where the pointer would be, adding up every movement.
    private var position = 0.0
    /// 1 or -1 while a stroke is under way, 0 before the first movement.
    private var direction = 0.0
    /// The furthest point of the current stroke.
    private var peak = 0.0
    /// Turns in a row so far, and when the last one was noticed.
    private var turns = 0
    private var lastTurn = 0.0

    mutating func move(_ delta: Double, at time: Double) -> Bool {
        guard delta != 0 else { return false }
        position += delta
        if direction == 0 {
            direction = delta > 0 ? 1 : -1
            peak = position
            return false
        }
        if (position - peak) * direction >= 0 {
            peak = position // still going the same way
            return false
        }
        guard (peak - position) * direction >= PointerShake.minimumStroke else { return false }

        // The pointer has come back far enough from the peak to count as a turn. Its time is when
        // it came back, not when it reached the peak, so pausing at the end of a stroke breaks
        // the run.
        let inRun = turns > 0 && time - lastTurn <= PointerShake.maximumTurnInterval
        turns = inRun ? turns + 1 : 1
        lastTurn = time
        direction = -direction
        peak = position
        return turns >= PointerShake.turnsNeeded
    }
}

/// What a shake does: a display dimmed to 20% or lower, where the pointer is hard to see, comes
/// back to 50%. Brighter displays keep the brightness they were set to, and a shake never dims.
public enum ShakeToBrighten {
    /// Displays at this brightness or lower respond to a shake.
    public static let threshold = 20.0
    /// The brightness they come back to.
    public static let level = 50.0

    /// The brightness (0 to 100) to set after a shake, or nil to leave the display as it is.
    /// Brightness is compared as the whole percent the window shows, so a monitor that reports
    /// 20.4% counts as 20%.
    public static func brightness(after current: Double) -> Double? {
        BrightnessMath.clamp(current).rounded() <= threshold ? level : nil
    }
}
