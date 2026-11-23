import Testing
@testable import MonitorCore

@Suite("Indicator placement")
struct IndicatorPlacementTests {
    // A 1512 point wide screen and the 300 point indicator.
    let width = 300.0
    let screenMinX = 0.0
    let screenMaxX = 1512.0

    @Test func centersUnderTheIcon() {
        let x = IndicatorPlacement.minX(width: width, iconMidX: 1000, screenMinX: screenMinX, screenMaxX: screenMaxX)
        #expect(x == 850)
    }

    @Test func staysInsideTheRightEdge() {
        // An icon close to the clock would push the indicator past the edge.
        let x = IndicatorPlacement.minX(width: width, iconMidX: 1450, screenMinX: screenMinX, screenMaxX: screenMaxX)
        #expect(x == screenMaxX - IndicatorPlacement.margin - width)
    }

    @Test func staysInsideTheLeftEdge() {
        let x = IndicatorPlacement.minX(width: width, iconMidX: 40, screenMinX: screenMinX, screenMaxX: screenMaxX)
        #expect(x == IndicatorPlacement.margin)
    }

    @Test func worksOnAScreenThatDoesNotStartAtZero() {
        // A display to the left of the main one has negative coordinates.
        let x = IndicatorPlacement.minX(width: width, iconMidX: -500, screenMinX: -1920, screenMaxX: 0)
        #expect(x == -650)
    }

    @Test func sitsAtTheTopRightWithoutAnIcon() {
        let x = IndicatorPlacement.minX(width: width, iconMidX: nil, screenMinX: screenMinX, screenMaxX: screenMaxX)
        #expect(x == screenMaxX - IndicatorPlacement.margin - width)
    }

    @Test func keepsTheLeftMarginOnAScreenTooNarrow() {
        let x = IndicatorPlacement.minX(width: width, iconMidX: 100, screenMinX: 0, screenMaxX: 250)
        #expect(x == IndicatorPlacement.margin)
    }

    @Test func findsTheIconOnAnotherScreenFromTheRightEdge() {
        // Measured 200 points from the right edge of the built-in display, the icon sits 200
        // points from the right edge of an external display at x 1512 to 3432 too.
        #expect(IndicatorPlacement.iconMidX(distanceFromRightEdge: 200, screenMaxX: 3432) == 3232)
    }
}
