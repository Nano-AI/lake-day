import Foundation

/// Real 7-day forecast from Open-Meteo (no key, free). Decodes defensively —
/// every field optional — and reduces each day to the daytime numbers the
/// RatingEngine wants.
///
/// Cloud cover: we first ask for the daily `cloud_cover_mean`. Some Open-Meteo
/// deployments don't expose it as a daily variable; if it's absent we make a
/// second request for hourly `cloud_cover` and average the 10:00–17:00 window
/// per day (the "daytime" window the score cares about).
struct OpenMeteoService: ForecastProviding {

    let session: URLSession
    let forecastDays: Int
    private let host = "api.open-meteo.com"
    private let path = "/v1/forecast"

    init(session: URLSession = .shared, forecastDays: Int = 7) {
        self.session = session
        self.forecastDays = forecastDays
    }

    // MARK: ForecastProviding

    func forecast(for lake: Lake) async throws -> [DayForecast] {
        // Attempt A: daily block including cloud_cover_mean.
        if let response = try? await fetch(url: dailyURL(lat: lake.lat, lon: lake.lon, includeCloudMean: true)),
           response.error != true,
           let days = assembleFromDailyCloud(response), !days.isEmpty {
            return days
        }

        // Attempt B (fallback): daily without cloud + hourly cloud_cover, one call.
        let response = try await fetch(url: fallbackURL(lat: lake.lat, lon: lake.lon))
        if let reason = response.reason, response.error == true {
            throw OpenMeteoError.api(reason)
        }
        let hourlyCloud = hourlyDaytimeCloudByDay(response)
        guard let days = assemble(from: response, cloudByDay: hourlyCloud), !days.isEmpty else {
            throw OpenMeteoError.noUsableData
        }
        return days
    }

    // MARK: URLs

    private func dailyURL(lat: Double, lon: Double, includeCloudMean: Bool) -> URL {
        var daily = ["temperature_2m_max", "temperature_2m_min",
                     "wind_speed_10m_max", "precipitation_probability_max", "uv_index_max"]
        if includeCloudMean { daily.insert("cloud_cover_mean", at: 2) }
        return buildURL(lat: lat, lon: lon,
                        query: ["daily": daily.joined(separator: ",")])
    }

    private func fallbackURL(lat: Double, lon: Double) -> URL {
        let daily = ["temperature_2m_max", "temperature_2m_min",
                     "wind_speed_10m_max", "precipitation_probability_max", "uv_index_max"]
        return buildURL(lat: lat, lon: lon, query: [
            "daily": daily.joined(separator: ","),
            "hourly": "cloud_cover"
        ])
    }

    private func buildURL(lat: Double, lon: Double, query: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        var items = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays))
        ]
        for (key, value) in query.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        // Force-unwrap is safe: all components are set from constants above.
        return components.url!
    }

    // MARK: Networking

    private func fetch(url: URL) async throws -> Response {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenMeteoError.http(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: Assembly

    /// Build days when the daily block already carries `cloud_cover_mean`.
    private func assembleFromDailyCloud(_ response: Response) -> [DayForecast]? {
        guard let cloud = response.daily?.cloud_cover_mean,
              cloud.contains(where: { $0 != nil }) else { return nil }
        return assemble(from: response, cloudByDay: nil)
    }

    /// Turn parallel daily arrays into `DayForecast`s. `cloudByDay` (from the
    /// hourly fallback) is used when the daily cloud field is unavailable.
    private func assemble(from response: Response, cloudByDay: [String: Double]?) -> [DayForecast]? {
        guard let daily = response.daily, let times = daily.time else { return nil }
        let tz = timeZone(for: response)
        let dayParser = DateFormatter()
        dayParser.locale = Locale(identifier: "en_US_POSIX")
        dayParser.timeZone = tz
        dayParser.dateFormat = "yyyy-MM-dd"

        var results: [DayForecast] = []
        for (index, dayString) in times.enumerated() {
            guard let date = dayParser.date(from: dayString) else { continue }
            guard let high = value(daily.temperature_2m_max, index),
                  let low = value(daily.temperature_2m_min, index) else { continue }

            let cloud: Double
            if let dailyCloud = value(daily.cloud_cover_mean, index) {
                cloud = dailyCloud
            } else if let byDay = cloudByDay?[dayString] {
                cloud = byDay
            } else {
                cloud = 0   // unknown cloud → no penalty rather than a fake one
            }

            let wind = value(daily.wind_speed_10m_max, index) ?? 0
            let precip = value(daily.precipitation_probability_max, index) ?? 0
            let uv = value(daily.uv_index_max, index) ?? 0

            results.append(DayForecast(date: date,
                                       highF: high,
                                       lowF: low,
                                       cloudCoverPercent: clampPercent(cloud),
                                       windMph: max(0, wind),
                                       precipProbabilityPercent: clampPercent(precip),
                                       uvIndexMax: max(0, uv)))
        }
        return results
    }

    /// Average hourly `cloud_cover` over 10:00–17:59 local, keyed by "yyyy-MM-dd".
    private func hourlyDaytimeCloudByDay(_ response: Response) -> [String: Double] {
        guard let hourly = response.hourly,
              let times = hourly.time,
              let clouds = hourly.cloud_cover else { return [:] }
        let tz = timeZone(for: response)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = tz
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        var sums: [String: (total: Double, count: Int)] = [:]
        for (index, timeString) in times.enumerated() {
            guard index < clouds.count, let cloud = clouds[index],
                  let date = parser.date(from: timeString) else { continue }
            let hour = calendar.component(.hour, from: date)
            guard hour >= 10 && hour < 18 else { continue }
            let dayKey = String(timeString.prefix(10))   // "yyyy-MM-dd"
            let existing = sums[dayKey] ?? (0, 0)
            sums[dayKey] = (existing.total + cloud, existing.count + 1)
        }
        return sums.mapValues { $0.count > 0 ? $0.total / Double($0.count) : 0 }
    }

    // MARK: Helpers

    private func timeZone(for response: Response) -> TimeZone {
        if let offset = response.utc_offset_seconds, let tz = TimeZone(secondsFromGMT: offset) {
            return tz
        }
        return TimeZone.current
    }

    private func value(_ array: [Double?]?, _ index: Int) -> Double? {
        guard let array, index < array.count else { return nil }
        return array[index]
    }

    private func clampPercent(_ x: Double) -> Double { max(0, min(100, x)) }

    // MARK: Wire types (all optional — parse defensively)

    private struct Response: Decodable {
        let utc_offset_seconds: Int?
        let timezone: String?
        let daily: DailyBlock?
        let hourly: HourlyBlock?
        let error: Bool?
        let reason: String?
    }

    private struct DailyBlock: Decodable {
        let time: [String]?
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let cloud_cover_mean: [Double?]?
        let wind_speed_10m_max: [Double?]?
        let precipitation_probability_max: [Double?]?
        let uv_index_max: [Double?]?
    }

    private struct HourlyBlock: Decodable {
        let time: [String]?
        let cloud_cover: [Double?]?
    }
}

enum OpenMeteoError: Error, LocalizedError {
    case http(Int)
    case api(String)
    case noUsableData

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Weather service returned HTTP \(code)."
        case .api(let reason): return "Weather service error: \(reason)"
        case .noUsableData: return "Weather service returned no usable forecast."
        }
    }
}
