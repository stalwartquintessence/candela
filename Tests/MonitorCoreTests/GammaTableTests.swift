import Foundation
import Testing
@testable import MonitorCore

@Suite("Gamma tables")
struct GammaTableTests {
    /// A linear ramp, like an uncalibrated display's table.
    private func ramp(_ count: Int = 256, scale: Float = 1) -> GammaTable {
        let values = (0 ..< count).map { Float($0) / Float(count - 1) * scale }
        return GammaTable(red: values, green: values, blue: values)
    }

    /// A different profile: a gamma curve with a warmer blue channel.
    private func otherProfile() -> GammaTable {
        let curve = (0 ..< 256).map { Float(pow(Double($0) / 255, 1.1)) }
        return GammaTable(red: curve, green: curve, blue: curve.map { $0 * 0.9 })
    }

    @Test func scalingMultipliesEveryChannelAndStaysInRange() {
        let half = ramp().scaled(by: 0.5)
        #expect(half.red.last == 0.5)
        #expect(half.green[128] == ramp().green[128] * 0.5)
        #expect(half.blue.first == 0)
        #expect(ramp().scaled(by: 2) == ramp())
        #expect(ramp().scaled(by: -1).red.allSatisfy { $0 == 0 })
    }

    @Test func matchingAllowsHardwareRounding() {
        var rounded = ramp()
        rounded.red[10] += 0.00005
        #expect(ramp().matches(rounded))
        rounded.red[10] += 0.01
        #expect(!ramp().matches(rounded))
        #expect(!ramp(256).matches(ramp(1024)))
        #expect(!ramp().matches(otherProfile()))
    }

    @Test func firstDimmingUsesTheCurrentTable() {
        #expect(DimmingState.original(current: ramp(), state: nil) == ramp())
    }

    @Test func whileCandelasTableIsShownTheOriginalStands() {
        let state = DimmingState(original: ramp(), applied: ramp().scaled(by: 0.6))
        let current = ramp().scaled(by: 0.6)
        #expect(!state.wasReplaced(byCurrent: current))
        #expect(DimmingState.original(current: current, state: state) == ramp())
    }

    @Test func aReplacedTableBecomesTheNewOriginal() {
        // The color profile changed while dimmed: ColorSync replaced Candela's table.
        let state = DimmingState(original: ramp(), applied: ramp().scaled(by: 0.6))
        #expect(state.wasReplaced(byCurrent: otherProfile()))
        #expect(DimmingState.original(current: otherProfile(), state: state) == otherProfile())
        // Waking from sleep puts the undimmed original back: also a replacement, same result.
        #expect(DimmingState.original(current: ramp(), state: state) == ramp())
    }

    @Test func dimmingIsNeverAppliedTwice() {
        // Re-applying the same level reads Candela's own dimmed table; it must not be taken as
        // the original, or each re-apply would dim further.
        let state = DimmingState(original: ramp(), applied: ramp().scaled(by: 0.6))
        let original = DimmingState.original(current: ramp().scaled(by: 0.6), state: state)
        #expect(original.scaled(by: 0.6) == ramp().scaled(by: 0.6))
    }
}
