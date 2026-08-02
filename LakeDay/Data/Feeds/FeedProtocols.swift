import Foundation
import CoreLocation

/// Each feed hides behind one of these. County formats change without notice,
/// so a conforming type must degrade (throw or return `.unknown` / nil) rather
/// than crash or fabricate data. The ViewModel is the only thing that merges
/// results into UI state.

/// Bacteria closures / advisories, keyed per beach.
protocol BeachSafetyProviding: Sendable {
    func safety(for beach: Beach, in lake: Lake) async throws -> SafetyStatus
}

/// Latest water-temperature sample for a lake. nil = no reading available.
protocol WaterTempProviding: Sendable {
    func waterTemp(for lake: Lake) async throws -> WaterTempReading?
}

/// Seven-day daytime-reduced forecast for a lake.
protocol ForecastProviding: Sendable {
    func forecast(for lake: Lake) async throws -> [DayForecast]
}

/// Current-day air quality (US AQI + PM2.5) for a lake — the wildfire-smoke
/// signal (DATA-FEEDS §8). nil = no reading available.
protocol AirQualityProviding: Sendable {
    func airQuality(for lake: Lake) async throws -> AirQualityReading?
}

/// Live "News & Alerts" for a lake — official NWS weather alerts merged with
/// matched local news stories (DATA-FEEDS §10). Display-only, never a score
/// input. Returns `[]` (never throws to the caller in practice) when both
/// sources are empty or unreachable.
protocol NewsProviding: Sendable {
    func news(for lake: Lake) async throws -> [NewsItem]
}

/// Statewide toxic-algae advisory affecting a lake (DATA-FEEDS §5). Sourced from
/// a small JSON snapshot published by an offline scraper (the WebForms source is
/// bot-walled). Returns the matching advisory, or nil when none / unreachable —
/// never fabricates safety. Folded into lake safety alongside beach bacteria.
protocol AlgaeAdvisoryProviding: Sendable {
    func advisory(for lake: Lake) async throws -> SafetyStatus?
}

/// Crowd proxy for a lake on a given day. `forecast` (if known) lets the
/// heuristic couple crowding to weather; `userLocation` enables the live
/// drive-time ratio for today only.
protocol TrafficProviding: Sendable {
    func crowdEstimate(for lake: Lake,
                       from userLocation: CLLocationCoordinate2D?,
                       forecast: DayForecast?,
                       on date: Date) async throws -> CrowdEstimate
}
