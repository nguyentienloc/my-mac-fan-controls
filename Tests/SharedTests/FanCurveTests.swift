import Testing
@testable import Shared

struct FanCurveTests {
    let balanced = FanCurve(points: [
        CurvePoint(temp: 55, percent: 0),
        CurvePoint(temp: 65, percent: 35),
        CurvePoint(temp: 75, percent: 65),
        CurvePoint(temp: 85, percent: 100),
    ])

    @Test func belowFirstPointReturnsNil() {
        #expect(balanced.percent(at: 54.9) == nil)
    }

    @Test func atFirstPointReturnsFirstPercent() {
        #expect(balanced.percent(at: 55) == 0)
    }

    @Test func interpolatesBetweenPoints() {
        #expect(balanced.percent(at: 60) == 17.5)
        #expect(balanced.percent(at: 70) == 50)
    }

    @Test func aboveLastPointHoldsLastPercent() {
        #expect(balanced.percent(at: 99) == 100)
    }

    @Test func emptyCurveReturnsNil() {
        #expect(FanCurve(points: []).percent(at: 70) == nil)
    }

    @Test func validCurvePasses() {
        #expect(balanced.validate() == nil)
    }

    @Test func rejectsTooFewPoints() {
        #expect(FanCurve(points: [CurvePoint(temp: 50, percent: 0)]).validate() == .tooFewPoints)
    }

    @Test func rejectsTempOutOfRange() {
        let curve = FanCurve(points: [CurvePoint(temp: 15, percent: 0), CurvePoint(temp: 60, percent: 50)])
        #expect(curve.validate() == .tempOutOfRange)
    }

    @Test func rejectsPercentOutOfRange() {
        let curve = FanCurve(points: [CurvePoint(temp: 50, percent: 0), CurvePoint(temp: 60, percent: 120)])
        #expect(curve.validate() == .percentOutOfRange)
    }

    @Test func rejectsNonIncreasingTemp() {
        let curve = FanCurve(points: [CurvePoint(temp: 60, percent: 0), CurvePoint(temp: 60, percent: 50)])
        #expect(curve.validate() == .tempNotIncreasing)
    }

    @Test func rejectsDecreasingPercent() {
        let curve = FanCurve(points: [CurvePoint(temp: 50, percent: 60), CurvePoint(temp: 70, percent: 40)])
        #expect(curve.validate() == .percentDecreasing)
    }

    @Test func validationMessagesAreVietnamese() {
        #expect(FanCurve.ValidationError.tooFewPoints.message == "Cần ít nhất 2 điểm")
    }
}
