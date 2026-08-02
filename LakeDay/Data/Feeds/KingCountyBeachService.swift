import Foundation
import os

// MARK: - King County beach feed (PRIMARY)
//
// One client, one fetch, both protocols. The ArcGIS `Swim_beach_temperature_view`
// GeoJSON layer (DATA-FEEDS §1) carries — in a single call, ~40 features —
// bacteria status, closure reason (bacteria AND toxic algae), water temperature
// and coordinates for every monitored beach. So this type conforms to BOTH
// `BeachSafetyProviding` and `WaterTempProviding`, and a single cached fetch
// (bacteria TTL) serves them both across all lakes.
//
// Toxic algae has no API of its own (DATA-FEEDS §5): it rides this feed as
// `Reason_For_Closure == "Toxic Algae"`, mapped to a `.closed` advisory here.
// The removed `ToxicAlgaeService` / `WaterTempService` stubs are folded in.
//
// It is an `actor` so that the launch fan-out — 11 lakes × their beaches, all
// asking at once — coalesces into ONE in-flight network request rather than a
// thundering herd, then everyone reads the cached collection.
//
// Parsing is deliberately paranoid (ARCHITECTURE): this is an undocumented
// production feed. Every feature is walked through a lenient `JSONValue` tree —
// one malformed feature can never throw the whole parse. Unknown `Beach_Status`
// strings → `.unknown`; booleans arrive as strings ("TRUE"/"True"); numbers may
// be null; `_<epoch>`-suffixed duplicate fields are ignored (we only match bare
// field names). The pure `parse(_:)` / `mapStatus(...)` statics have no I/O so
// ParserTests can hit them directly.
actor KingCountyBeachService: BeachSafetyProviding, WaterTempProviding {

    private let session: URLSession
    private let cache: FeedCache
    private var inFlight: Task<[String: RawBeach], Error>?

    private static let logger = Logger(subsystem: "com.adi.LakeDay", category: "KingCountyBeach")
    private static let cacheKey = "kc-beach-collection"

    /// where=1=1, all fields, GeoJSON (DATA-FEEDS §1).
    private static let endpoint = URL(string:
        "https://services.arcgis.com/Ej0PsM5Aw677QF1W/arcgis/rest/services/" +
        "Swim_beach_temperature_view/FeatureServer/0/query?where=1=1&outFields=*&f=geojson")!

    init(session: URLSession = .shared,
         cache: FeedCache = FeedCache(namespace: "KingCountyBeach")) {
        self.session = session
        self.cache = cache
    }

    // MARK: BeachSafetyProviding

    func safety(for beach: Beach, in lake: Lake) async throws -> SafetyStatus {
        let records = try await records()
        guard let raw = records[beach.locator.uppercased()] else {
            Self.logger.notice("KC feed: unmatched locator \(beach.locator, privacy: .public) (\(beach.name, privacy: .public)) — skipping")
            return .unknown
        }
        return raw.safety(now: Date())
    }

    // MARK: WaterTempProviding
    //
    // Lake-level water temp = median of its beaches' readings (lake-level safety
    // is the worst-beach merge, done in FeedLoader.worst()).

    func waterTemp(for lake: Lake) async throws -> WaterTempReading? {
        let records = try await records()
        var readings: [WaterTempReading] = []
        for beach in lake.beaches {
            if let raw = records[beach.locator.uppercased()] {
                if let reading = raw.waterTemp { readings.append(reading) }
            } else {
                Self.logger.notice("KC feed: unmatched locator \(beach.locator, privacy: .public) (\(beach.name, privacy: .public)) — skipping")
            }
        }
        return Self.median(of: readings)
    }

    /// Median reading, paired with the freshest contributing sample time.
    static func median(of readings: [WaterTempReading]) -> WaterTempReading? {
        guard !readings.isEmpty else { return nil }
        let sorted = readings.sorted { $0.fahrenheit < $1.fahrenheit }
        let mid = sorted.count / 2
        let medianF = sorted.count % 2 == 1
            ? sorted[mid].fahrenheit
            : (sorted[mid - 1].fahrenheit + sorted[mid].fahrenheit) / 2
        let latest = readings.map(\.sampledAt).max() ?? readings[0].sampledAt
        return WaterTempReading(fahrenheit: medianF, sampledAt: latest)
    }

    // MARK: One cached fetch, coalesced

    /// Fresh cache → single in-flight fetch (shared by all callers) → parse →
    /// cache. On failure, falls back to the last cached collection if any.
    private func records() async throws -> [String: RawBeach] {
        if let fresh = await cache.fresh(for: Self.cacheKey, as: [String: RawBeach].self, ttl: CacheTTL.bacteria) {
            return fresh
        }
        if let existing = inFlight {
            return try await existing.value
        }
        let task = Task<[String: RawBeach], Error> { try await self.fetchAndParse() }
        inFlight = task
        do {
            let result = try await task.value
            inFlight = nil
            await cache.set(result, for: Self.cacheKey)
            return result
        } catch {
            inFlight = nil
            if let stale = await cache.entry(for: Self.cacheKey, as: [String: RawBeach].self) {
                Self.logger.notice("KC feed: fetch failed, serving cached collection \(Int(stale.age), privacy: .public)s old")
                return stale.value
            }
            throw error
        }
    }

    private func fetchAndParse() async throws -> [String: RawBeach] {
        let (data, response) = try await session.data(from: Self.endpoint)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw KingCountyBeachError.http(http.statusCode)
        }
        let parsed = Self.parse(data)
        guard !parsed.isEmpty else { throw KingCountyBeachError.noUsableData }
        return parsed
    }

    // MARK: - Pure parse (no I/O — ParserTests hit this directly)

    /// GeoJSON `Data` → `[UPPERCASE-locator: RawBeach]`. Never throws on shape
    /// drift: a feature missing `locator`, or any unparseable feature, is
    /// skipped. Returns `[:]` for non-JSON / wrong-shape input.
    static func parse(_ data: Data) -> [String: RawBeach] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(obj) = root,
              case let .array(features)? = obj["features"] else {
            return [:]
        }
        var out: [String: RawBeach] = [:]
        for feature in features {
            guard case let .object(f) = feature,
                  case let .object(props)? = f["properties"] else { continue }
            guard let raw = rawBeach(properties: props, geometry: f["geometry"]) else { continue }
            out[raw.locator.uppercased()] = raw
        }
        return out
    }

    private static func rawBeach(properties props: [String: JSONValue], geometry: JSONValue?) -> RawBeach? {
        // locator is the join key — no locator, no record.
        guard let locator = field(props, "locator")?.stringValue?.trimmedNonEmpty else { return nil }

        let (lat, lon) = coordinates(props: props, geometry: geometry)
        return RawBeach(
            locator: locator,
            beachName: field(props, "siteName", "Beach")?.stringValue?.trimmedNonEmpty,
            waterBody: field(props, "Water_Body")?.stringValue?.trimmedNonEmpty,
            statusRaw: field(props, "Beach_Status")?.stringValue?.trimmedNonEmpty,
            reasonForClosure: field(props, "Reason_For_Closure")?.stringValue?.trimmedNonEmpty,
            closureExplanation: field(props, "Closure_Explanation_For_Web")?.stringValue?.trimmedNonEmpty,
            waterTempF: field(props, "WaterTempF")?.doubleValue,
            sampledAt: date(fromEpoch: field(props, "SampleTimestamp")?.doubleValue),
            hasCurrentData: field(props, "Beach_Has_Current_Data")?.boolValue,
            lat: lat,
            lon: lon)
    }

    /// Prefer geometry `[lon, lat]`; fall back to `lat`/`lon` property fields.
    private static func coordinates(props: [String: JSONValue], geometry: JSONValue?) -> (Double?, Double?) {
        if case let .object(geo)? = geometry, case let .array(coords)? = geo["coordinates"], coords.count >= 2,
           let lon = coords[0].doubleValue, let lat = coords[1].doubleValue {
            return (lat, lon)
        }
        return (field(props, "lat")?.doubleValue, field(props, "lon")?.doubleValue)
    }

    /// Exact key match, then a case-insensitive fallback. Bare field names only,
    /// so `_<epoch>`-suffixed duplicate fields never match (DATA-FEEDS §1 caveat).
    private static func field(_ props: [String: JSONValue], _ keys: String...) -> JSONValue? {
        for key in keys { if let value = props[key] { return value } }
        let lower = Dictionary(props.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        for key in keys { if let value = lower[key.lowercased()] { return value } }
        return nil
    }

    /// Epoch milliseconds (or seconds) → Date, with a sanity window. `SampleTimestamp`
    /// is documented as ms; we tolerate seconds too. nil / 0 / absurd → nil.
    static func date(fromEpoch value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        guard seconds > 946_684_800, seconds < 4_102_444_800 else { return nil }   // 2000..2100
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Pure status mapping (ParserTests hit this directly)

    private static let staleThreshold: TimeInterval = 10 * 86_400   // 10 days

    /// Maps a beach's raw feed fields → SafetyStatus (DATA-FEEDS §1 / DESIGN
    /// safety table). `now` is injected for testability of the staleness rule.
    static func mapStatus(statusRaw: String?,
                          reason: String?,
                          explanation: String?,
                          sampledAt: Date?,
                          now: Date) -> SafetyStatus {
        let status = (statusRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch status {
        case "ok to swim (low bacteria)":
            // Staleness → caution: OK, but the sample is over 10 days old in season.
            if let sampledAt, isInSeason(now), now.timeIntervalSince(sampledAt) > staleThreshold {
                return SafetyStatus(level: .caution, reason: "Sample is over 10 days old", sampledAt: sampledAt)
            }
            return SafetyStatus(level: .open, reason: nil, sampledAt: sampledAt)

        case "stay out of the water":
            return SafetyStatus(level: .closed,
                                reason: closureReason(reason: reason, explanation: explanation),
                                sampledAt: sampledAt)

        case "no recent data", "not a currently monitored beach":
            return .unknown

        default:   // unrecognized Beach_Status string → never guess
            return .unknown
        }
    }

    /// Concise closure reason: a mapped head ("High bacteria" / "Toxic algae
    /// advisory") plus a trimmed explanation when it's short enough to read
    /// inline (it feeds the "Skip it — <reason>." verdict).
    static func closureReason(reason: String?, explanation: String?) -> String {
        let head: String
        switch reason?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "high bacteria": head = "High bacteria"
        case "toxic algae":   head = "Toxic algae advisory"
        default:
            if let r = reason?.trimmedNonEmpty { head = capitalizeFirst(r) }
            else { head = "Closed by King County" }
        }
        if let raw = explanation?.trimmedNonEmpty {
            let one = collapseWhitespace(raw)
            if one.count <= 140 { return "\(head) — \(one)" }
        }
        return head
    }

    /// Sampling season (DATA-FEEDS §1): mid-May through late September.
    static func isInSeason(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return false }
        switch month {
        case 6, 7, 8: return true
        case 5:       return day >= 15
        case 9:       return true
        default:      return false
        }
    }

    // MARK: Small string helpers

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .joined(separator: " ")
    }
}

// MARK: - Parsed record (cacheable, and the unit the parser tests inspect)

/// One beach's extracted fields. Codable & Sendable so the whole collection is
/// cached under one key. Staleness is computed at read time (via `safety(now:)`),
/// not baked in, so a cached collection stays correct as time passes.
struct RawBeach: Codable, Sendable, Hashable {
    let locator: String
    let beachName: String?
    let waterBody: String?
    let statusRaw: String?
    let reasonForClosure: String?
    let closureExplanation: String?
    let waterTempF: Double?
    let sampledAt: Date?
    let hasCurrentData: Bool?
    let lat: Double?
    let lon: Double?

    /// Advisory as of `now` (applies the stale-sample rule).
    func safety(now: Date) -> SafetyStatus {
        KingCountyBeachService.mapStatus(statusRaw: statusRaw,
                                         reason: reasonForClosure,
                                         explanation: closureExplanation,
                                         sampledAt: sampledAt,
                                         now: now)
    }

    /// Water reading only when both temperature and a sample time are present —
    /// staleness is always shown, so a reading without a timestamp is dropped.
    var waterTemp: WaterTempReading? {
        guard let f = waterTempF, f.isFinite, let t = sampledAt else { return nil }
        return WaterTempReading(fahrenheit: f, sampledAt: t)
    }
}

// MARK: - Lenient JSON value (drift-proof: any feature shape decodes or is skipped)

/// A minimal any-JSON tree used to walk the feed defensively. Coerces across
/// string/number/bool so "TRUE"/`true`/`1` all read as booleans and stringy
/// numbers still parse.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "true" : "false"
        default:             return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b):   return b ? 1 : 0
        default:             return nil
        }
    }

    /// Handles the feed's string booleans ("TRUE"/"True"/"false") and numerics.
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1":  return true
            case "false", "no", "0":  return false
            default:                  return nil
            }
        default: return nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Errors

enum KingCountyBeachError: Error, LocalizedError {
    case http(Int)
    case noUsableData

    var errorDescription: String? {
        switch self {
        case .http(let code): return "King County beach data returned HTTP \(code)."
        case .noUsableData:   return "King County beach data returned no usable features."
        }
    }
}
