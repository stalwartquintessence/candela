import Testing
@testable import MonitorCore

/// A pointer moved back and forth the way a hand does it, in small steps like the movement events
/// macOS sends.
private final class Pointer {
    var detector = PointerShake()
    var time = 0.0
    private var sign = 1.0

    /// Moves `strokes` times back and forth, `length` points each way, each stroke taking
    /// `duration` seconds. Returns true if a movement completed a shake.
    func shake(strokes: Int, length: Double = 120, duration: Double = 0.12,
                        along axis: (x: Double, y: Double) = (1, 0)) -> Bool {
        var shaken = false
        let steps = 6
        for _ in 0 ..< strokes {
            for _ in 0 ..< steps {
                time += duration / Double(steps)
                let distance = sign * length / Double(steps)
                if detector.move(dx: distance * axis.x, dy: distance * axis.y, at: time) { shaken = true }
            }
            sign = -sign
        }
        return shaken
    }

    /// Moves in a straight line, then comes back `back` points, as when overshooting a button.
    func move(_ length: Double, back: Double, duration: Double = 0.2) -> Bool {
        var shaken = false
        for (distance, steps) in [(length, 12), (-back, 3)] {
            for _ in 0 ..< steps {
                time += duration / 12
                if detector.move(dx: distance / Double(steps), dy: 0, at: time) { shaken = true }
            }
        }
        return shaken
    }

    func wait(_ seconds: Double) { time += seconds }
}

@Suite("Pointer shake")
struct PointerShakeTests {
    @Test func quickSidewaysShakeIsRecognized() {
        let pointer = Pointer()
        #expect(pointer.shake(strokes: 6))
    }

    @Test func upAndDownAndDiagonalShakesCount() {
        let upAndDown = Pointer()
        #expect(upAndDown.shake(strokes: 6, along: (0, 1)))
        let diagonal = Pointer()
        #expect(diagonal.shake(strokes: 6, along: (0.7, -0.7)))
    }

    @Test func fewerTurnsAreNotAShake() {
        // Five strokes turn four times; the fifth turn comes only with a sixth stroke.
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 5))
        #expect(pointer.shake(strokes: 1))
    }

    @Test func slowBackAndForthIsNotAShake() {
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 20, length: 300, duration: 0.5))
    }

    @Test func smallWobblesAreNotAShake() {
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 20, length: 40, duration: 0.08))
    }

    @Test func pausingStartsOver() {
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 4))
        pointer.wait(1)
        #expect(!pointer.shake(strokes: 4))
    }

    @Test func pausingAtTheEndOfAStrokeBreaksTheRun() {
        // Four quick turns, a rest at the far end, then one move back: not a fifth quick turn.
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 5))
        pointer.wait(1)
        #expect(!pointer.shake(strokes: 1))
    }

    @Test func resetStartsOver() {
        let pointer = Pointer()
        #expect(!pointer.shake(strokes: 4))
        pointer.detector.reset()
        #expect(!pointer.shake(strokes: 4))
    }

    @Test func eachShakeIsCountedFromScratch() {
        let pointer = Pointer()
        #expect(pointer.shake(strokes: 6))
        #expect(!pointer.shake(strokes: 4))
        #expect(pointer.shake(strokes: 2))
    }

    @Test func ordinaryMovementIsNotAShake() {
        // Quick moves to one target after another, overshooting a little and resting on each.
        let pointer = Pointer()
        for _ in 0 ..< 10 {
            #expect(!pointer.move(400, back: 30))
            pointer.wait(0.4)
            #expect(!pointer.move(-250, back: 20))
            pointer.wait(0.4)
        }
    }

    @Test func noMovementChangesNothing() {
        var detector = PointerShake()
        for step in 0 ..< 100 {
            let shaken = detector.move(dx: 0, dy: 0, at: Double(step) / 60)
            #expect(!shaken)
        }
    }
}

@Suite("Shake to brighten")
struct ShakeToBrightenTests {
    @Test func dimDisplayComesBackToHalf() {
        #expect(ShakeToBrighten.brightness(after: 0) == 50)
        #expect(ShakeToBrighten.brightness(after: 12.5) == 50)
        #expect(ShakeToBrighten.brightness(after: 49) == 50)
    }

    @Test func neverDims() {
        #expect(ShakeToBrighten.brightness(after: 50) == nil)
        #expect(ShakeToBrighten.brightness(after: 75) == nil)
        #expect(ShakeToBrighten.brightness(after: 100) == nil)
    }

    @Test func comparesTheWholePercentTheWindowShows() {
        #expect(ShakeToBrighten.brightness(after: 49.8) == nil)
        #expect(ShakeToBrighten.brightness(after: 49.4) == 50)
    }
}
