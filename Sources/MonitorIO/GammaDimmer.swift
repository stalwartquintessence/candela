// Software brightness: scales the display's gamma transfer table, the same technique
// MonitorControl uses when hardware DDC is not available. It dims the picture, not the
// backlight, so it saves no power, but it works on any connection.
//
// Quartz restores the user's ColorSync gamma automatically when the process exits, so a crash
// can never leave a display stuck dimmed.
//
// macOS and other apps can replace a display's table while it is dimmed (a new color profile,
// wake from sleep, f.lux). Before every change the current table is compared with the one
// Candela set; if it was replaced, the replacement is the display's own table from then on
// (see DimmingState). Displays Candela never dimmed are never touched.

import CoreGraphics
import Foundation
import MonitorCore

public final class GammaDimmer {
    private var states: [CGDirectDisplayID: DimmingState] = [:]

    public init() {}

    /// Dim a display to `percent` (0 to 100). Returns false when the display has no gamma table.
    @discardableResult
    public func setBrightness(_ percent: Double, for id: CGDirectDisplayID) -> Bool {
        apply(factor: BrightnessMath.gammaFactor(forPercent: percent), to: id)
    }

    @discardableResult
    public func apply(factor: Double, to id: CGDirectDisplayID) -> Bool {
        let state = states[id]
        guard factor < 0.999 else {
            if state != nil { restore(id) }
            return true
        }
        guard let current = Self.read(id) else { return false }
        if let state, state.wasReplaced(byCurrent: current) {
            Log.app("gamma: display \(id): its table was replaced (color profile, wake or another app); dimming on top of the new one")
        }
        let original = DimmingState.original(current: current, state: state)
        guard Self.write(original.scaled(by: factor), to: id) else { return false }
        // Remember what the display reports back, so rounding is never mistaken for a change.
        states[id] = DimmingState(original: original, applied: Self.read(id) ?? original.scaled(by: factor))
        return true
    }

    /// Put one display back to its own table. A table that was replaced while dimmed is left as
    /// it is, because it already is the display's own.
    public func restore(_ id: CGDirectDisplayID) {
        guard let state = states.removeValue(forKey: id) else { return }
        guard let current = Self.read(id) else { return }
        if state.wasReplaced(byCurrent: current) {
            Log.app("gamma: display \(id): its table was replaced while dimmed; keeping the new one")
        } else {
            Self.write(state.original, to: id)
        }
    }

    /// Undim every display Candela dimmed. Other displays, and other apps' tables, stay as they are.
    public func restoreAll() {
        for id in Array(states.keys) { restore(id) }
    }

    /// The display is gone: forget it without writing anything.
    public func forget(_ id: CGDirectDisplayID) {
        states[id] = nil
    }

    /// macOS gave a dimmed display a new ID (after sleep or reconnection). Keep its state, so its
    /// dimmed table is not mistaken for its original.
    public func move(from old: CGDirectDisplayID, to new: CGDirectDisplayID) {
        guard old != new, let state = states.removeValue(forKey: old) else { return }
        states[new] = state
    }

    // MARK: Quartz

    private static func read(_ id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r
        var b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success, count > 0 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(r.prefix(n)), green: Array(g.prefix(n)), blue: Array(b.prefix(n)))
    }

    @discardableResult
    private static func write(_ table: GammaTable, to id: CGDirectDisplayID) -> Bool {
        let ok = CGSetDisplayTransferByTable(id, UInt32(table.red.count), table.red, table.green, table.blue) == .success
        if !ok { Log.error("gamma: CGSetDisplayTransferByTable failed for display \(id)") }
        return ok
    }
}
