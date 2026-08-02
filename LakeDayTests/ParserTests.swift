import XCTest
@testable import LakeDay

/// Fixture-driven tests for the two feed parsers. Both parsers are pure static
/// `parse(Data)` functions with no I/O, so these hit them directly — no network,
/// no mocks. Fixtures are embedded strings modeled on the real feed shapes
/// (DATA-FEEDS §1, §8), including the drift the parsers must survive: string
/// booleans, null numbers, unknown status strings, malformed payloads.
final class ParserTests: XCTestCase {

    // MARK: Time anchors

    private static let cal = Calendar(identifier: .gregorian)

    /// Mid-season (sampling runs mid-May–late-Sept) so the stale-sample rule is live.
    private let inSeasonNow: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 15; c.hour = 12
        return cal.date(from: c)!
    }()

    /// Out of season — the stale rule must NOT downgrade an OK beach here.
    private let outOfSeasonNow: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 1; c.day = 15; c.hour = 12
        return cal.date(from: c)!
    }()

    private func epochMillis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private func daysBefore(_ n: Int, _ date: Date) -> Date { date.addingTimeInterval(-Double(n) * 86_400) }

    // MARK: - GeoJSON fixture (six features covering every mapping branch)

    /// Feature 2 uses Houghton Beach's real locator/coords (DATA-FEEDS §4:
    /// A422SB, 47.65962, -122.20627); the E. coli MPN values are illustrative.
    private func beachGeoJSON() -> Data {
        let recent = epochMillis(daysBefore(3, inSeasonNow))
        let stale  = epochMillis(daysBefore(20, inSeasonNow))
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-122.27526, 47.6359] },
              "properties": {
                "siteName": "Madison Park Beach", "Water_Body": "Lake Washington",
                "Beach_Status": "OK to swim (low bacteria)", "Reason_For_Closure": null,
                "Closure_Explanation_For_Web": null, "locator": "0852SB",
                "WaterTempF": 68.0, "WaterTempC": 20.0, "SampleTimestamp": \(recent),
                "Beach_Has_Current_Data": "True", "HighToday": "False",
                "Beach_Status_1720000000000": "stale duplicate ignore me"
              } },
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-122.20627, 47.65962] },
              "properties": {
                "siteName": "Houghton Beach", "Water_Body": "Lake Washington",
                "Beach_Status": "Stay out of the water", "Reason_For_Closure": "High Bacteria",
                "Closure_Explanation_For_Web": "Bacteria levels exceed the swimming standard.",
                "locator": "A422SB", "left_": 1200, "middle": 980, "right_": 1500,
                "Geomean30d": 410, "nSamplesHigh30d": 2, "WaterTempF": 66.2,
                "SampleTimestamp": \(recent), "Beach_Has_Current_Data": "TRUE", "HighToday": "TRUE"
              } },
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-122.32955, 47.68039] },
              "properties": {
                "siteName": "Green Lake - East Beach", "Water_Body": "Green Lake",
                "Beach_Status": "Stay out of the water", "Reason_For_Closure": "Toxic Algae",
                "Closure_Explanation_For_Web": "Toxic algae bloom advisory in effect.",
                "locator": "A734SB", "WaterTempF": 74.0, "SampleTimestamp": \(recent),
                "Beach_Has_Current_Data": "True"
              } },
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-122.00242, 47.58738] },
              "properties": {
                "siteName": "Beaver Lake Beach", "Water_Body": "Beaver Lake",
                "Beach_Status": "No recent data", "Reason_For_Closure": null,
                "locator": "A709SB", "WaterTempF": null, "SampleTimestamp": null,
                "Beach_Has_Current_Data": "False"
              } },
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-122.27143, 47.69593] },
              "properties": {
                "siteName": "Matthews Beach", "Water_Body": "Lake Washington",
                "Beach_Status": "OK to swim (low bacteria)", "Reason_For_Closure": null,
                "locator": "0818SB", "WaterTempF": 65.0, "SampleTimestamp": \(stale),
                "Beach_Has_Current_Data": "True"
              } },
            { "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-121.7662, 47.43391] },
              "properties": {
                "siteName": "Rattlesnake Lake Beach", "Water_Body": "Rattlesnake Lake",
                "Beach_Status": "Closed for maintenance", "locator": "A999SB",
                "WaterTempF": 58.0, "SampleTimestamp": \(recent), "Beach_Has_Current_Data": "True"
              } }
          ]
        }
        """
        return Data(json.utf8)
    }

    func testParsesAllFeaturesKeyedByUppercaseLocator() {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        XCTAssertEqual(records.count, 6)
        XCTAssertNotNil(records["0852SB"])
        XCTAssertNotNil(records["A422SB"])
        // Uppercasing means lookups are case-insensitive on the join side too.
        XCTAssertNotNil(records["a422sb".uppercased()])
    }

    func testOpenBeachMapsToOpenWithWaterReading() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["0852SB"])
        let safety = raw.safety(now: inSeasonNow)
        XCTAssertEqual(safety.level, .open)
        XCTAssertNil(safety.reason)
        XCTAssertNotNil(safety.sampledAt)

        let reading = try XCTUnwrap(raw.waterTemp)
        XCTAssertEqual(reading.fahrenheit, 68.0, accuracy: 0.001)
    }

    func testClosedHighBacteriaMapsToClosedWithReason() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["A422SB"])
        let safety = raw.safety(now: inSeasonNow)
        XCTAssertEqual(safety.level, .closed)
        let reason = try XCTUnwrap(safety.reason)
        XCTAssertTrue(reason.lowercased().contains("bacteria"), reason)
        XCTAssertTrue(reason.contains("exceed the swimming standard"), "explanation should be folded in: \(reason)")
        // Water temp is still available on a closed beach.
        XCTAssertEqual(try XCTUnwrap(raw.waterTemp).fahrenheit, 66.2, accuracy: 0.001)
    }

    func testClosedToxicAlgaeMapsToClosedWithAlgaeReason() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["A734SB"])
        let safety = raw.safety(now: inSeasonNow)
        XCTAssertEqual(safety.level, .closed)
        XCTAssertTrue(try XCTUnwrap(safety.reason).lowercased().contains("algae"))
    }

    func testNoRecentDataMapsToUnknown() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["A709SB"])
        XCTAssertEqual(raw.safety(now: inSeasonNow).level, .unknown)
        // Null temp + null timestamp → no reading, no crash.
        XCTAssertNil(raw.waterTemp)
    }

    func testUnrecognizedStatusMapsToUnknown() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["A999SB"])
        XCTAssertEqual(raw.safety(now: inSeasonNow).level, .unknown)
    }

    func testStaleOpenSampleDowngradesToCautionInSeason() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["0818SB"])   // OK status, 20-day-old sample
        let safety = raw.safety(now: inSeasonNow)
        XCTAssertEqual(safety.level, .caution)
        XCTAssertEqual(safety.reason, "Sample is over 10 days old")
    }

    func testStaleOpenSampleStaysOpenOutOfSeason() throws {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        let raw = try XCTUnwrap(records["0818SB"])
        XCTAssertEqual(raw.safety(now: outOfSeasonNow).level, .open)
    }

    func testStringBooleansParse() {
        let records = KingCountyBeachService.parse(beachGeoJSON())
        XCTAssertEqual(records["0852SB"]?.hasCurrentData, true)   // "True"
        XCTAssertEqual(records["A422SB"]?.hasCurrentData, true)   // "TRUE"
        XCTAssertEqual(records["A709SB"]?.hasCurrentData, false)  // "False"
    }

    // MARK: - Status mapping unit (independent of GeoJSON envelope)

    func testMapStatusBranchesDirectly() {
        let now = inSeasonNow
        XCTAssertEqual(
            KingCountyBeachService.mapStatus(statusRaw: "OK to swim (low bacteria)",
                                             reason: nil, explanation: nil, sampledAt: now, now: now).level,
            .open)
        XCTAssertEqual(
            KingCountyBeachService.mapStatus(statusRaw: "Not a currently monitored beach",
                                             reason: nil, explanation: nil, sampledAt: nil, now: now).level,
            .unknown)
        XCTAssertEqual(
            KingCountyBeachService.mapStatus(statusRaw: "  something totally new  ",
                                             reason: nil, explanation: nil, sampledAt: nil, now: now).level,
            .unknown)
        XCTAssertEqual(
            KingCountyBeachService.mapStatus(statusRaw: nil,
                                             reason: nil, explanation: nil, sampledAt: nil, now: now).level,
            .unknown)
    }

    // MARK: - Lake-level median water temp

    func testMedianWaterTemp() throws {
        let t0 = inSeasonNow
        let readings = [
            WaterTempReading(fahrenheit: 64, sampledAt: daysBefore(5, t0)),
            WaterTempReading(fahrenheit: 68, sampledAt: t0),
            WaterTempReading(fahrenheit: 72, sampledAt: daysBefore(2, t0))
        ]
        let median = try XCTUnwrap(KingCountyBeachService.median(of: readings))
        XCTAssertEqual(median.fahrenheit, 68, accuracy: 0.001)
        XCTAssertEqual(median.sampledAt, t0)   // freshest contributing sample
        XCTAssertNil(KingCountyBeachService.median(of: []))
    }

    // MARK: - Malformed / missing-field GeoJSON (never crash, degrade to empty)

    func testMalformedGeoJSONReturnsEmpty() {
        XCTAssertTrue(KingCountyBeachService.parse(Data("not json at all".utf8)).isEmpty)
        XCTAssertTrue(KingCountyBeachService.parse(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(KingCountyBeachService.parse(Data("[]".utf8)).isEmpty)
        XCTAssertTrue(KingCountyBeachService.parse(Data(#"{"features": {"nope": 1}}"#.utf8)).isEmpty)
        XCTAssertTrue(KingCountyBeachService.parse(Data("".utf8)).isEmpty)
    }

    func testFeaturesMissingLocatorAreSkippedNotCrashed() {
        let json = #"""
        { "type": "FeatureCollection", "features": [
          { "type": "Feature", "properties": { "Beach_Status": "OK to swim (low bacteria)" } },
          { "type": "Feature" },
          { "type": "Feature", "properties": { "locator": "GOOD1SB", "Beach_Status": "OK to swim (low bacteria)" } }
        ] }
        """#
        let records = KingCountyBeachService.parse(Data(json.utf8))
        XCTAssertEqual(records.count, 1)          // only the one with a locator survives
        XCTAssertNotNil(records["GOOD1SB"])
        XCTAssertNil(records["GOOD1SB"]?.waterTemp)   // no temp/timestamp → nil, no crash
    }

    // MARK: - Open-Meteo air quality (DATA-FEEDS §8)

    private func aqiJSON() -> Data {
        Data(#"""
        {
          "utc_offset_seconds": -25200,
          "timezone": "America/Los_Angeles",
          "hourly": {
            "time": ["2026-07-15T10:00","2026-07-15T11:00","2026-07-15T12:00","2026-07-15T13:00"],
            "pm2_5": [8.6, 9.1, 47.5, 50.0],
            "us_aqi": [36, 38, 132, null]
          }
        }
        """#.utf8)
    }

    /// Build a Date matching a wall-clock hour in the fixture's timezone (GMT-7).
    private func pacific(hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: -25200)!
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 15; c.hour = hour
        return cal.date(from: c)!
    }

    func testAirQualityPicksSmokyNoonReading() throws {
        let reading = try XCTUnwrap(AirQualityService.parse(aqiJSON(), now: pacific(hour: 12)))
        XCTAssertEqual(reading.usAQI, 132)
        XCTAssertEqual(try XCTUnwrap(reading.pm25), 47.5, accuracy: 0.001)
        XCTAssertEqual(reading.category, "Unhealthy for sensitive groups")
        XCTAssertTrue(reading.isSmoky)
        XCTAssertEqual(reading.smokeNote, "Smoky — air quality 132. Consider skipping exertion.")
    }

    func testAirQualityPicksCleanMorningReadingAndSkipsNulls() throws {
        let reading = try XCTUnwrap(AirQualityService.parse(aqiJSON(), now: pacific(hour: 10)))
        XCTAssertEqual(reading.usAQI, 36)
        XCTAssertEqual(reading.category, "Good")
        XCTAssertFalse(reading.isSmoky)
        XCTAssertNil(reading.smokeNote)
    }

    func testAirQualityMalformedReturnsNil() {
        XCTAssertNil(AirQualityService.parse(Data("not json".utf8)))
        XCTAssertNil(AirQualityService.parse(Data("{}".utf8)))
        XCTAssertNil(AirQualityService.parse(Data(#"{"error": true, "reason": "bad request"}"#.utf8)))
        // Hourly present but every us_aqi null → no usable hour.
        let allNull = #"{"hourly": {"time": ["2026-07-15T12:00"], "us_aqi": [null], "pm2_5": [null]}}"#
        XCTAssertNil(AirQualityService.parse(Data(allNull.utf8)))
    }

    func testAirQualityCategoryBands() {
        func cat(_ aqi: Int) -> String {
            AirQualityReading(usAQI: aqi, pm25: nil, sampledAt: Date()).category
        }
        XCTAssertEqual(cat(25), "Good")
        XCTAssertEqual(cat(75), "Moderate")
        XCTAssertEqual(cat(120), "Unhealthy for sensitive groups")
        XCTAssertEqual(cat(180), "Unhealthy")
        XCTAssertEqual(cat(250), "Very unhealthy")
        XCTAssertEqual(cat(400), "Hazardous")
    }
}
