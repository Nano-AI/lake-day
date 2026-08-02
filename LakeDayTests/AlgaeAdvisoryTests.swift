import XCTest
@testable import LakeDay

/// Pure parse + match for the statewide algae snapshot (no I/O). Mirrors the
/// offline scraper's JSON schema.
final class AlgaeAdvisoryTests: XCTestCase {

    private func lake(_ name: String, lat: Double, lon: Double) -> Lake {
        Lake(id: "t-\(name)", name: name, lat: lat, lon: lon, region: "WA",
             beaches: [], hazards: [], activities: [],
             usgsSiteId: nil, kcBuoyId: nil, popularity: nil)
    }

    private let json = Data("""
    {
      "generated": "2026-07-12T19:00:00Z",
      "advisories": [
        {"site": "Lake Chelan", "county": "Chelan", "toxin": "Saxitoxin",
         "value": 90, "unit": "ug/L", "category": "danger", "date": "2026-07-05"},
        {"site": "Anderson Lake", "county": "Jefferson", "lat": 48.01, "lon": -122.86,
         "toxin": "Microcystin", "value": 4.0, "unit": "ug/L", "category": "caution", "date": "2026-07-04"}
      ]
    }
    """.utf8)

    func testParsesAllAdvisories() {
        XCTAssertEqual(AlgaeAdvisoryService.parse(json).count, 2)
    }

    func testMatchesByNameAndMapsDangerToClosed() {
        let advisories = AlgaeAdvisoryService.parse(json)
        // Chelan advisory has no coords → must match on name overlap.
        let status = AlgaeAdvisoryService.match(advisories, to: lake("Lake Chelan", lat: 47.84, lon: -120.02))
        XCTAssertEqual(status?.level, .closed)
        XCTAssertEqual(status?.reason, "Toxic algae advisory — Saxitoxin")
    }

    func testMatchesByProximityAndMapsCautionToCaution() {
        let advisories = AlgaeAdvisoryService.parse(json)
        // ~1.3 km from the Anderson Lake advisory coords; different name.
        let status = AlgaeAdvisoryService.match(advisories, to: lake("Some Pond", lat: 48.02, lon: -122.85))
        XCTAssertEqual(status?.level, .caution)
        XCTAssertEqual(status?.reason, "Toxic algae advisory — Microcystin")
    }

    func testNoMatchReturnsNil() {
        let advisories = AlgaeAdvisoryService.parse(json)
        // Far from Anderson's coords, and no name overlap with either advisory.
        XCTAssertNil(AlgaeAdvisoryService.match(advisories, to: lake("Green Lake", lat: 47.68, lon: -122.33)))
    }

    func testEmptyOrJunkDataDegradesToEmpty() {
        XCTAssertEqual(AlgaeAdvisoryService.parse(Data("not json".utf8)).count, 0)
    }
}
