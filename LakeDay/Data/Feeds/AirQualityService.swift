import Foundation

/// Open-Meteo Air Quality (DATA-FEEDS §8, no key, free). Fetches the current
/// day's hourly `pm2_5` + `us_aqi` for a lake's coordinates and reduces to the
/// single reading nearest to "now". Decodes defensively — every field optional,
/// nulls tolerated — and returns nil rather than throwing on empty data.
///
/// No internal cache: like OpenMeteoService and TrafficService, freshness and
/// stale-fallback are owned by FeedLoader (CacheTTL.airQuality = 3h).
struct AirQualityService: AirQualityProviding {

    let session: URLSession
    private let host = "air-quality-api.open-meteo.com"
    private let path = "/v1/air-quality"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: AirQualityProviding

    func airQuality(for lake: Lake) async throws -> AirQualityReading? {
        let url = buildURL(lat: lake.lat, lon: lake.lon)
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AirQualityError.http(http.statusCode)
        }
        return Self.parse(data, now: Date())
    }

    // MARK: URL

    private func buildURL(lat: Double, lon: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "pm2_5,us_aqi"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        // Force-unwrap is safe: all components are set from constants above.
        return components.url!
    }

    // MARK: - Pure parse (no I/O — ParserTests hit this directly)

    /// Picks the hourly entry with a non-null `us_aqi` closest to `now`. Returns
    /// nil for non-JSON, an API error payload, or no usable hour.
    static func parse(_ data: Data, now: Date = Date()) -> AirQualityReading? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.error != true,
              let hourly = response.hourly,
              let times = hourly.time else {
            return nil
        }
        let tz = response.utc_offset_seconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = tz
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var best: (date: Date, aqi: Int, pm: Double?)?
        for (index, timeString) in times.enumerated() {
            guard let date = parser.date(from: timeString),
                  let aqiValue = value(hourly.us_aqi, index), aqiValue.isFinite else { continue }
            let candidate = (date, Int(aqiValue.rounded()), value(hourly.pm2_5, index))
            if let current = best {
                if abs(date.timeIntervalSince(now)) < abs(current.date.timeIntervalSince(now)) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        guard let b = best else { return nil }
        return AirQualityReading(usAQI: b.aqi, pm25: b.pm, sampledAt: b.date)
    }

    private static func value(_ array: [Double?]?, _ index: Int) -> Double? {
        guard let array, index < array.count else { return nil }
        return array[index]
    }

    // MARK: Wire types (all optional — parse defensively)

    private struct Response: Decodable {
        let utc_offset_seconds: Int?
        let hourly: Hourly?
        let error: Bool?
        let reason: String?
    }

    private struct Hourly: Decodable {
        let time: [String]?
        let pm2_5: [Double?]?
        let us_aqi: [Double?]?
    }
}

enum AirQualityError: Error, LocalizedError {
    case http(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):   return "Air-quality service returned HTTP \(code)."
        case .api(let reason):  return "Air-quality service error: \(reason)"
        }
    }
}
