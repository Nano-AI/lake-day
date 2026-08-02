import Foundation
import CoreLocation
import MapKit

/// Crowd proxy — never a real headcount, always labeled "estimate".
///
/// For *today* with a known location we compute a live congestion ratio
/// (traffic-aware `expectedTravelTime` ÷ a distance-based free-flow estimate)
/// via `MKDirections`, and fold it into a weekend / US-holiday / weather-
/// goodness heuristic ("nice Saturday = packed"). For future days, or when
/// location is denied, it's the heuristic alone.
struct TrafficService: TrafficProviding {

    /// Blended free-flow driving speed used for the congestion baseline.
    let freeflowMph: Double
    private var calendar: Calendar

    init(freeflowMph: Double = 50, calendar: Calendar = .current) {
        self.freeflowMph = freeflowMph
        self.calendar = calendar
    }

    func crowdEstimate(for lake: Lake,
                       from userLocation: CLLocationCoordinate2D?,
                       forecast: DayForecast?,
                       on date: Date) async throws -> CrowdEstimate {

        let goodness = forecast.map(weatherGoodness(_:)) ?? 0.5

        // Day + weather "demand": how many people want a beach today.
        let demand = calendarBase(for: date) + goodness * 0.35

        // Scale demand by *this* lake's pull. A nice Saturday packs Green Lake but
        // only fills a remote lake partway — same demand, different destination.
        var value = demand * popularityFactor(lake.popularityWeight)

        // Live congestion — today only, and only if we have the user's location.
        // Route-based, so already lake-specific; added on top of the scaled demand.
        var etaMinutes: Int?
        if let userLocation, calendar.isDateInToday(date) {
            if let live = try? await liveCongestion(from: userLocation, to: lake.coordinate) {
                value += min(max(live.ratio - 1, 0), 0.6) * 0.30
                etaMinutes = live.etaMinutes
            }
        }

        value = clamp01(value)
        return CrowdEstimate(level: level(for: value), value: value, etaMinutes: etaMinutes)
    }

    // MARK: Live congestion via MKDirections

    private struct LiveCongestion {
        let ratio: Double        // ≥ 1.0; higher = more congested
        let etaMinutes: Int
    }

    private func liveCongestion(from source: CLLocationCoordinate2D,
                                to destination: CLLocationCoordinate2D) async throws -> LiveCongestion {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.departureDate = Date()   // makes expectedTravelTime traffic-aware

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first, route.distance > 0 else {
            throw TrafficError.noRoute
        }

        let mps = freeflowMph * 0.44704
        let freeflowSeconds = route.distance / mps
        let ratio = freeflowSeconds > 0 ? route.expectedTravelTime / freeflowSeconds : 1
        return LiveCongestion(ratio: max(1, ratio),
                              etaMinutes: Int((route.expectedTravelTime / 60).rounded()))
    }

    // MARK: Heuristic pieces

    /// Baseline crowding before weather/traffic: quiet weekdays, busy weekends,
    /// busiest on summer holidays.
    private func calendarBase(for date: Date) -> Double {
        if isLikelyUSHoliday(date) { return 0.55 }
        if calendar.isDateInWeekend(date) { return 0.45 }
        return 0.20
    }

    /// How inviting the weather is for a beach trip (0–1). Weighted toward
    /// warmth, then dryness, then clear skies.
    private func weatherGoodness(_ f: DayForecast) -> Double {
        let warm = clamp01((f.highF - 62) / (82 - 62))
        let dry = clamp01(1 - f.precipProbabilityPercent / 100)
        let clear = clamp01(1 - (f.cloudCoverPercent / 100))
        return clamp01(warm * 0.6 + dry * 0.25 + clear * 0.15)
    }

    /// Maps a lake's 0–1 popularity to a demand multiplier. A marquee lake (1.0)
    /// amplifies demand ~1.2×; a quiet one (0.0) dampens it to ~0.6×; the neutral
    /// default (0.6) lands near 1.0, so unweighted lakes behave as before.
    private func popularityFactor(_ popularity: Double) -> Double {
        0.6 + clamp01(popularity) * 0.6
    }

    private func level(for value: Double) -> CrowdLevel {
        switch value {
        case ..<0.34: return .low
        case ..<0.67: return .medium
        default:      return .high
        }
    }

    /// A small set of summer-relevant US holidays (the ones that actually pack
    /// a WA lake). Not a full federal calendar.
    private func isLikelyUSHoliday(_ date: Date) -> Bool {
        let c = calendar.dateComponents([.month, .day, .weekday, .weekdayOrdinal], from: date)
        guard let month = c.month, let day = c.day else { return false }

        switch (month, day) {
        case (6, 19): return true          // Juneteenth
        case (7, 4):  return true          // Independence Day
        default: break
        }
        // Memorial Day: last Monday of May.
        if month == 5, c.weekday == 2, isLastWeekdayOfMonth(date) { return true }
        // Labor Day: first Monday of September.
        if month == 9, c.weekday == 2, c.weekdayOrdinal == 1 { return true }
        return false
    }

    private func isLastWeekdayOfMonth(_ date: Date) -> Bool {
        guard let next = calendar.date(byAdding: .day, value: 7, to: date) else { return false }
        return calendar.component(.month, from: next) != calendar.component(.month, from: date)
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
}

enum TrafficError: Error {
    case noRoute
}
