import Foundation

/// A water-temperature sample. Carries its own timestamp so the UI can always
/// show age ("buoy reading 3h ago" / "sampled Tue").
struct WaterTempReading: Codable, Hashable {
    let fahrenheit: Double
    let sampledAt: Date
}

/// A current-day air-quality reading (Open-Meteo, DATA-FEEDS §8). Wildfire
/// smoke is the real WA summer lake-day killer, so this is displayed on detail
/// and, at unhealthy levels, mentioned alongside the verdict — but it is NOT in
/// the score weights (RatingEngine stays pure over its four components).
struct AirQualityReading: Codable, Hashable, Sendable {
    let usAQI: Int
    /// Fine-particulate concentration µg/m³; nil when the feed omits it.
    let pm25: Double?
    let sampledAt: Date

    /// US-EPA AQI category word shown next to the number.
    var category: String {
        switch usAQI {
        case ..<0:       return "no reading"
        case 0...50:     return "Good"
        case 51...100:   return "Moderate"
        case 101...150:  return "Unhealthy for sensitive groups"
        case 151...200:  return "Unhealthy"
        case 201...300:  return "Very unhealthy"
        default:         return "Hazardous"
        }
    }

    /// Wildfire-smoke threshold (DATA-FEEDS §8): Unhealthy-for-Sensitive-Groups+.
    var isSmoky: Bool { usAQI >= 101 }

    /// One-line smoke note appended to the displayed verdict (DESIGN copy rules:
    /// plain verbs). Computed here — not in RatingEngine — so the engine stays
    /// pure; nil below the smoke threshold.
    var smokeNote: String? {
        guard isSmoky else { return nil }
        return "Smoky — air quality \(usAQI). Consider skipping exertion."
    }
}

/// One day of forecast, already reduced to the numbers the score needs.
/// `cloudCoverPercent` and `precipProbabilityPercent` represent the daytime
/// (10:00–18:00) window — the OpenMeteo layer does that reduction so the
/// RatingEngine can stay a pure function over plain daily numbers.
struct DayForecast: Codable, Hashable, Identifiable {
    let date: Date
    let highF: Double
    let lowF: Double
    let cloudCoverPercent: Double
    let windMph: Double
    let precipProbabilityPercent: Double
    let uvIndexMax: Double

    var id: Date { date }
}

/// Everything time-varying we know about a lake, merged by the ViewModel.
struct Conditions: Hashable {
    var waterTemp: WaterTempReading?
    var forecast: [DayForecast]
    var airQuality: AirQualityReading?

    init(waterTemp: WaterTempReading? = nil,
         forecast: [DayForecast] = [],
         airQuality: AirQualityReading? = nil) {
        self.waterTemp = waterTemp
        self.forecast = forecast
        self.airQuality = airQuality
    }

    /// Forecast entry for a given calendar day, if present.
    func forecast(on day: Date, calendar: Calendar = .current) -> DayForecast? {
        forecast.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// First (soonest) forecast day, treated as "today".
    var today: DayForecast? { forecast.first }
}

/// Crowd proxy. ALWAYS labeled an estimate (DESIGN.md) — it is derived from a
/// weekend/holiday/weather heuristic plus, for today only, a live drive-time
/// ratio. `value` is 0–1 where 1 means "packed".
enum CrowdLevel: String, Codable, Hashable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low:    return "Quiet"
        case .medium: return "Moderate"
        case .high:   return "Busy"
        }
    }
}

struct CrowdEstimate: Codable, Hashable {
    let level: CrowdLevel
    /// 0–1, higher = more crowded.
    let value: Double
    /// Always "estimate" — surfaced verbatim in the UI so the proxy is honest.
    let label: String
    /// Live drive time in minutes when scoring today with a known user
    /// location; nil for future days or when location is denied.
    let etaMinutes: Int?

    init(level: CrowdLevel, value: Double, label: String = "estimate", etaMinutes: Int? = nil) {
        self.level = level
        self.value = value
        self.label = label
        self.etaMinutes = etaMinutes
    }
}
