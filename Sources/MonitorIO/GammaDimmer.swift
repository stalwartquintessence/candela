// Software brightness: scales the display's gamma transfer table, the same technique
// MonitorControl uses when hardware DDC is not available. It dims the picture, not the
// backlight, so it saves no power, but it works on any connection.
//
// Quartz restores the user's ColorSync gamma automatically when the process exits, so a crash
// can never leave a display stuck dimmed.

import CoreGraphics
import Foundation
import MonitorCore

public final class GammaDimmer {
    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    private var originals: [CGDirectDisplayID: Table] = [:]
    /// Displays currently dimmed, with their gamma multiplier.
    public private(set) var factors: [CGDirectDisplayID: Double] = [:]

    public init() {}

    /// Dim a display to `percent` (0 to 100). Returns false when the display has no gamma table.
    @discardableResult
    public func setBrightness(_ percent: Double, for id: CGDirectDisplayID) -> Bool {
        apply(factor: BrightnessMath.gammaFactor(forPercent: percent), to: id)
    }

    @discardableResult
    public func apply(factor: Double, to id: CGDirectDisplayID) -> Bool {
        guard factor < 0.999 else {
            restore(id)
            return true
        }
        guard let table = original(for: id) else { return false }
        let r = BrightnessMath.scale(table.red, by: factor)
        let g = BrightnessMath.scale(table.green, by: factor)
        let b = BrightnessMath.scale(table.blue, by: factor)
        let ok = CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b) == .success
        if ok { factors[id] = factor } else { Log.error("gamma: CGSetDisplayTransferByTable failed for display \(id)") }
        return ok
    }

    /// Put one display back to its unmodified table.
    public func restore(_ id: CGDirectDisplayID) {
        guard factors.removeValue(forKey: id) != nil, let t = originals[id] else { return }
        CGSetDisplayTransferByTable(id, UInt32(t.red.count), t.red, t.green, t.blue)
    }

    /// Restore every display to its ColorSync profile and forget cached tables.
    public func restoreAll() {
        factors.removeAll()
        originals.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    private func original(for id: CGDirectDisplayID) -> Table? {
        if let t = originals[id] { return t }
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = r
        var b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success, count > 0 else { return nil }
        let table = Table(red: Array(r.prefix(Int(count))), green: Array(g.prefix(Int(count))), blue: Array(b.prefix(Int(count))))
        originals[id] = table
        return table
    }
}
