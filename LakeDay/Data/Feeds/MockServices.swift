import Foundation
import CoreLocation

// MARK: - Mocks for SwiftUI previews
//
// Deterministic, richly varied data covering every safety state:
//   lake-washington → open, warm & sunny, 66° water, smoky air (AQI 132)
//   lake-sammamish  → caution (stale sample), 63° water, clean air
//   green-lake      → closed (toxic-algae advisory), no score
//   angle-lake      → unknown (no bacteria data), no water reading
//
// All keyed off `lake.id`, so the same instances drive every preview.

enum MockServices {

    // A fixed reference day so previews (and their verdict weekday text) are stable.
    static let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 11   // Saturday
        c.hour = 9
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    // MARK: Sample lakes (self-contained; no bundle dependency)

    static let washington = Lake(
        id: "lake-washington", name: "Lake Washington",
        lat: 47.6205, lon: -122.2585, region: "Seattle / Eastside",
        beaches: [
            Beach(name: "Madison Park Beach", lat: 47.6359, lon: -122.27526, locator: "0852SB"),
            Beach(name: "Matthews Beach", lat: 47.69593, lon: -122.27143, locator: "0818SB")
        ],
        hazards: ["Cold below the warm surface layer, even in August",
                  "Busy boat and floatplane lanes — stay inside the swim buoys"],
        activities: ["swim", "paddle", "boat", "beach"],
        usgsSiteId: nil, kcBuoyId: "washington", popularity: 0.9)

    static let sammamish = Lake(
        id: "lake-sammamish", name: "Lake Sammamish",
        lat: 47.5893, lon: -122.0821, region: "Issaquah / Redmond",
        beaches: [
            Beach(name: "Idylwood Beach", lat: 47.64164, lon: -122.09982, locator: "0602SB"),
            Beach(name: "Lake Sammamish SP – Tibbets Beach", lat: 47.55684, lon: -122.07032, locator: "0615SB")
        ],
        hazards: ["Cold below the surface layer even in August",
                  "Milfoil weed beds near shore in late summer"],
        activities: ["swim", "paddle", "boat", "beach"],
        usgsSiteId: nil, kcBuoyId: "sammamish", popularity: 0.7)

    static let greenLake = Lake(
        id: "green-lake", name: "Green Lake",
        lat: 47.6806, lon: -122.3345, region: "Seattle",
        beaches: [
            Beach(name: "Green Lake - East Beach", lat: 47.68039, lon: -122.32955, locator: "A734SB"),
            Beach(name: "Green Lake - West Beach", lat: 47.68217, lon: -122.33933, locator: "A734WSB")
        ],
        hazards: ["History of summer toxic-algae blooms — check the advisory before you swim",
                  "Packs out on the first warm weekend of the year"],
        activities: ["swim", "paddle", "walk", "beach"],
        usgsSiteId: nil, kcBuoyId: nil, popularity: 1.0)

    static let angle = Lake(
        id: "angle-lake", name: "Angle Lake",
        lat: 47.4225, lon: -122.2967, region: "SeaTac",
        beaches: [
            Beach(name: "Angle Lake Beach", lat: 47.4275, lon: -122.2933, locator: "A732SB")
        ],
        hazards: ["Cold water below the surface even midsummer",
                  "Small lake — busy with boats and jet skis on weekends"],
        activities: ["swim", "paddle", "boat", "beach"],
        usgsSiteId: nil, kcBuoyId: nil, popularity: 0.5)

    static let lakes: [Lake] = [washington, sammamish, greenLake, angle]

    // MARK: Service instances (named `...Service` so they don't collide with the
    // synchronous data functions `safety/waterTemp/forecast/crowd` below).

    static let beachSafetyService = MockBeachSafetyService()
    static let waterTempService = MockWaterTempService()
    static let forecastService = MockForecastService()
    static let trafficService = MockTrafficService()
    static let airQualityService = MockAirQualityService()
    static let newsService = MockNewsService()
    static let algaeService = MockAlgaeService()

    // MARK: Synchronous data (shared by the async services and by previews)

    private static let cal = Calendar(identifier: .gregorian)
    private static func daysAgo(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: -n, to: referenceDate) ?? referenceDate
    }

    static func safety(for lake: Lake) -> SafetyStatus {
        switch lake.id {
        case "lake-washington":
            return SafetyStatus(level: .open, reason: nil, sampledAt: daysAgo(3))
        case "lake-sammamish":
            return SafetyStatus(level: .caution, reason: "Sample is 12 days old", sampledAt: daysAgo(12))
        case "green-lake":
            return SafetyStatus(level: .closed, reason: "Toxic algae advisory since Jul 2", sampledAt: daysAgo(2))
        default:
            return .unknown
        }
    }

    static func waterTemp(for lake: Lake) -> WaterTempReading? {
        switch lake.id {
        case "lake-washington": return WaterTempReading(fahrenheit: 66, sampledAt: daysAgo(3))
        case "lake-sammamish":  return WaterTempReading(fahrenheit: 63, sampledAt: daysAgo(4))
        case "green-lake":      return WaterTempReading(fahrenheit: 74, sampledAt: daysAgo(2))
        default:                return nil   // angle-lake: no reading
        }
    }

    static func forecast(for lake: Lake) -> [DayForecast] {
        let start = referenceDate
        switch lake.id {
        case "lake-washington":
            return makeForecast(from: start,
                                highs: [84, 82, 85, 80, 78, 83, 86],
                                lows:  [60, 59, 61, 58, 57, 60, 62],
                                cloud: [10, 20, 5, 30, 40, 15, 5],
                                wind:  [4, 6, 3, 8, 10, 5, 4],
                                precip:[0, 5, 0, 15, 25, 5, 0],
                                uv:    [8, 7, 9, 6, 5, 8, 9])
        case "lake-sammamish":
            return makeForecast(from: start,
                                highs: [76, 74, 78, 72, 70, 77, 79],
                                lows:  [56, 55, 57, 54, 53, 56, 58],
                                cloud: [40, 55, 30, 60, 70, 35, 25],
                                wind:  [7, 9, 6, 11, 12, 8, 6],
                                precip:[10, 20, 5, 35, 45, 10, 5],
                                uv:    [6, 5, 7, 4, 4, 6, 7])
        case "green-lake":
            return makeForecast(from: start,
                                highs: [83, 81, 86, 79, 77, 82, 85],
                                lows:  [61, 60, 62, 59, 58, 61, 63],
                                cloud: [15, 25, 10, 35, 45, 20, 10],
                                wind:  [5, 7, 4, 9, 10, 6, 5],
                                precip:[5, 10, 0, 20, 30, 5, 0],
                                uv:    [7, 7, 8, 6, 5, 7, 8])
        default: // angle-lake — cooler, cloudier, wetter
            return makeForecast(from: start,
                                highs: [70, 68, 72, 66, 64, 71, 73],
                                lows:  [54, 53, 55, 52, 51, 54, 56],
                                cloud: [60, 70, 50, 80, 85, 55, 45],
                                wind:  [10, 12, 9, 14, 16, 11, 8],
                                precip:[25, 40, 15, 55, 65, 20, 10],
                                uv:    [4, 3, 5, 3, 2, 4, 5])
        }
    }

    static func crowd(for lake: Lake) -> CrowdEstimate {
        switch lake.id {
        case "lake-washington": return CrowdEstimate(level: .high, value: 0.78, etaMinutes: 22)
        case "lake-sammamish":  return CrowdEstimate(level: .medium, value: 0.5, etaMinutes: 28)
        case "green-lake":      return CrowdEstimate(level: .high, value: 0.82, etaMinutes: 12)
        default:                return CrowdEstimate(level: .low, value: 0.22, etaMinutes: 35)
        }
    }

    static func airQuality(for lake: Lake) -> AirQualityReading? {
        switch lake.id {
        case "lake-washington": return AirQualityReading(usAQI: 132, pm25: 47.5, sampledAt: referenceDate) // smoky
        case "lake-sammamish":  return AirQualityReading(usAQI: 42, pm25: 9.8, sampledAt: referenceDate)   // Good
        case "green-lake":      return AirQualityReading(usAQI: 88, pm25: 28.0, sampledAt: referenceDate)  // Moderate
        default:                return AirQualityReading(usAQI: 30, pm25: 6.4, sampledAt: referenceDate)   // Good
        }
    }

    /// Deterministic sample news so the detail section renders in previews.
    /// Green Lake gets one alert + one story; Lake Washington one story. Dates
    /// are `referenceDate`-relative so previews stay stable.
    static func news(for lake: Lake) -> [NewsItem] {
        switch lake.id {
        case "green-lake":
            return [
                NewsItem(id: "mock-nws-green-heat", kind: .alert,
                         title: "Heat Advisory", source: "NWS", url: nil,
                         publishedAt: daysAgo(0), severity: "Moderate"),
                NewsItem(id: "https://www.kiro7.com/mock/green-lake-algae", kind: .news,
                         title: "Toxic algae found in Seattle’s Green Lake",
                         source: "KIRO 7 News Seattle",
                         url: URL(string: "https://www.kiro7.com/mock/green-lake-algae"),
                         publishedAt: daysAgo(4), severity: nil)
            ]
        case "lake-washington":
            return [
                NewsItem(id: "https://www.king5.com/mock/lake-washington-rescue", kind: .news,
                         title: "Teen in critical condition after jumping into Lake Washington",
                         source: "KING5.com",
                         url: URL(string: "https://www.king5.com/mock/lake-washington-rescue"),
                         publishedAt: daysAgo(6), severity: nil)
            ]
        default:
            return []
        }
    }
}

// MARK: - Forecast building helper

private func makeForecast(from start: Date,
                          highs: [Double],
                          lows: [Double],
                          cloud: [Double],
                          wind: [Double],
                          precip: [Double],
                          uv: [Double]) -> [DayForecast] {
    let calendar = Calendar(identifier: .gregorian)
    var days: [DayForecast] = []
    for i in 0..<highs.count {
        guard let date = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: start)) else { continue }
        days.append(DayForecast(date: date,
                                highF: highs[i], lowF: lows[i],
                                cloudCoverPercent: cloud[i], windMph: wind[i],
                                precipProbabilityPercent: precip[i], uvIndexMax: uv[i]))
    }
    return days
}

// MARK: - Mock services

struct MockBeachSafetyService: BeachSafetyProviding {
    func safety(for beach: Beach, in lake: Lake) async throws -> SafetyStatus {
        MockServices.safety(for: lake)
    }
}

struct MockWaterTempService: WaterTempProviding {
    func waterTemp(for lake: Lake) async throws -> WaterTempReading? {
        MockServices.waterTemp(for: lake)
    }
}

struct MockForecastService: ForecastProviding {
    func forecast(for lake: Lake) async throws -> [DayForecast] {
        MockServices.forecast(for: lake)
    }
}

struct MockTrafficService: TrafficProviding {
    func crowdEstimate(for lake: Lake,
                       from userLocation: CLLocationCoordinate2D?,
                       forecast: DayForecast?,
                       on date: Date) async throws -> CrowdEstimate {
        MockServices.crowd(for: lake)
    }
}

struct MockAirQualityService: AirQualityProviding {
    func airQuality(for lake: Lake) async throws -> AirQualityReading? {
        MockServices.airQuality(for: lake)
    }
}

struct MockNewsService: NewsProviding {
    func news(for lake: Lake) async throws -> [NewsItem] {
        MockServices.news(for: lake)
    }
}

struct MockAlgaeService: AlgaeAdvisoryProviding {
    func advisory(for lake: Lake) async throws -> SafetyStatus? { nil }
}
