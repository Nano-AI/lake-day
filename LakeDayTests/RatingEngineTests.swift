import XCTest
@testable import LakeDay

final class RatingEngineTests: XCTestCase {

    private let engine = RatingEngine()

    // MARK: Fixtures

    private func forecast(high: Double,
                          cloud: Double = 0,
                          wind: Double = 3,
                          precip: Double = 0) -> DayForecast {
        DayForecast(date: Date(),
                    highF: high,
                    lowF: high - 20,
                    cloudCoverPercent: cloud,
                    windMph: wind,
                    precipProbabilityPercent: precip,
                    uvIndexMax: 7)
    }

    private func crowd(_ value: Double) -> CrowdEstimate {
        CrowdEstimate(level: .low, value: value)
    }

    // MARK: Hard zero

    func testHardZeroOnClosed() {
        let safety = SafetyStatus(level: .closed, reason: "Toxic algae advisory", sampledAt: Date())
        let score = engine.score(safety: safety,
                                 waterTempF: 74,
                                 forecast: forecast(high: 85),
                                 crowd: crowd(0.2))
        XCTAssertNil(score.total)
        XCTAssertTrue(score.isClosed)
    }

    func testVerdictMentionsClosureReason() {
        let safety = SafetyStatus(level: .closed,
                                  reason: "Toxic algae advisory since Jul 2",
                                  sampledAt: Date())
        let score = engine.score(safety: safety,
                                 waterTempF: 74,
                                 forecast: forecast(high: 82),
                                 crowd: crowd(0.3))
        XCTAssertNil(score.total)
        XCTAssertTrue(score.verdict.contains("algae"),
                      "Verdict should name the closure reason, got: \(score.verdict)")
    }

    // MARK: Caution cap

    func testCautionCapsAt60() {
        let safety = SafetyStatus(level: .caution, reason: "Sample is stale", sampledAt: Date())
        // Otherwise near-perfect inputs.
        let score = engine.score(safety: safety,
                                 waterTempF: 75,
                                 forecast: forecast(high: 84, cloud: 0, wind: 2, precip: 0),
                                 crowd: crowd(0.1))
        XCTAssertNotNil(score.total)
        XCTAssertLessThanOrEqual(score.total!, 60)
    }

    // MARK: Water-temp curve boundaries

    func testWaterCurveBoundaries() {
        XCTAssertLessThanOrEqual(engine.waterScore(59), 0.2)   // cold-shock territory
        XCTAssertEqual(engine.waterScore(60), 0.2, accuracy: 0.001)
        XCTAssertEqual(engine.waterScore(65), 0.5, accuracy: 0.001)
        XCTAssertEqual(engine.waterScore(66), 0.5, accuracy: 0.001)
        XCTAssertEqual(engine.waterScore(72), 0.9, accuracy: 0.001)
        XCTAssertEqual(engine.waterScore(73), 1.0, accuracy: 0.001)
    }

    // MARK: Wind boundaries

    func testWindBoundaries() {
        XCTAssertEqual(engine.windScore(3), 1.0, accuracy: 0.001)   // calm
        XCTAssertEqual(engine.windScore(5), 1.0, accuracy: 0.001)   // edge of calm
        XCTAssertEqual(engine.windScore(18), 0.0, accuracy: 0.001)  // ceiling
        XCTAssertEqual(engine.windScore(11.5), 0.5, accuracy: 0.05) // midpoint
    }

    // MARK: Missing water renormalizes weights

    func testMissingWaterRenormalizesWeights() {
        let calmSunny = forecast(high: 84, cloud: 0, wind: 2, precip: 0) // sunAir 1.0, wind 1.0
        let empty = crowd(0.0)                                           // crowdScore 1.0

        let withoutWater = engine.score(safety: SafetyStatus(level: .open),
                                        waterTempF: nil,
                                        forecast: calmSunny,
                                        crowd: empty)
        XCTAssertNil(withoutWater.water.normalized, "Missing water must be excluded")
        // 0.40 + 0.20 + 0.15 renormalized over 0.75 → 1.0 → 100.
        XCTAssertEqual(withoutWater.total, 100)

        let withWater = engine.score(safety: SafetyStatus(level: .open),
                                     waterTempF: 75,
                                     forecast: calmSunny,
                                     crowd: empty)
        XCTAssertEqual(withWater.total, 100)
    }

    // MARK: End-to-end tiers

    func testPerfectDayScoresAbove85() {
        let score = engine.score(safety: SafetyStatus(level: .open),
                                 waterTempF: 76,
                                 forecast: forecast(high: 84, cloud: 0, wind: 2, precip: 0),
                                 crowd: crowd(0.1))
        XCTAssertNotNil(score.total)
        XCTAssertGreaterThan(score.total!, 85)
    }

    func testColdRainyWindyDayScoresBelow30() {
        let bad = forecast(high: 54, cloud: 90, wind: 20, precip: 90)
        let score = engine.score(safety: SafetyStatus(level: .open),
                                 waterTempF: 55,
                                 forecast: bad,
                                 crowd: crowd(0.2))
        XCTAssertNotNil(score.total)
        XCTAssertLessThan(score.total!, 30)
    }
}
