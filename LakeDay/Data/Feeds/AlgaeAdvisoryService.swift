import Foundation
import CoreLocation

/// Statewide toxic-algae advisories (DATA-FEEDS §5). The authoritative source
/// (nwtoxicalgae.org) is an ASP.NET WebForms site behind F5 bot-defense — every
/// scripted postback 302s to an error page, so it cannot be scraped from the
/// app. Instead an offline job (see `tools/algae-scraper/`) runs a real browser,
/// exports the statewide toxin CSV, and publishes a small JSON snapshot; this
/// service reads that snapshot and folds "toxic algae near this lake" into
/// safety for ANY lake — the only algae signal available beyond King County.
///
/// Degrades to nil (never fabricates green) when the snapshot is unset,
/// unreachable, or has no advisory matching the lake. One fetch is shared across
/// all lakes in a refresh via `SnapshotCache`.
struct AlgaeAdvisoryService: AlgaeAdvisoryProviding {

    let snapshotURL: URL?
    let session: URLSession
    private let cache: SnapshotCache

    /// The published snapshot URL. Set this to your hosted JSON (e.g. the
    /// GitHub raw URL the `algae-scraper` Action writes to). Left nil until then,
    /// so the feed is a clean no-op rather than a stream of failed fetches.
    static let defaultSnapshotURL: URL? = nil   // TODO: e.g. URL(string: "https://raw.githubusercontent.com/<you>/lake-day/main/docs/algae-snapshot.json")

    init(snapshotURL: URL? = AlgaeAdvisoryService.defaultSnapshotURL,
         session: URLSession = .shared) {
        self.snapshotURL = snapshotURL
        self.session = session
        self.cache = SnapshotCache()
    }

    // MARK: AlgaeAdvisoryProviding

    func advisory(for lake: Lake) async throws -> SafetyStatus? {
        guard let snapshotURL else { return nil }
        let advisories = try await cache.advisories(url: snapshotURL, session: session)
        return Self.match(advisories, to: lake)
    }

    // MARK: - Pure match (no I/O — unit-testable)

    /// The highest-severity advisory affecting `lake`, or nil. Matches by
    /// proximity when the advisory has coordinates, else by lake-name overlap.
    static func match(_ advisories: [AlgaeAdvisory], to lake: Lake) -> SafetyStatus? {
        let hits = advisories.filter { $0.matches(lake: lake) }
        guard let top = hits.max(by: { $0.severityRank < $1.severityRank }) else { return nil }
        let level: SafetyLevel = top.severityRank >= AlgaeAdvisory.dangerRank ? .closed : .caution
        return SafetyStatus(level: level, reason: top.reasonText, sampledAt: top.date)
    }

    // MARK: - Pure parse (no I/O — unit-testable)

    static func parse(_ data: Data) -> [AlgaeAdvisory] {
        (try? JSONDecoder().decode(Snapshot.self, from: data))?.advisories ?? []
    }

    private struct Snapshot: Decodable {
        let advisories: [AlgaeAdvisory]
    }
}

// MARK: - Advisory model

/// One recent toxic-algae advisory from the published snapshot. Every field is
/// optional so a format change degrades gracefully rather than dropping the feed.
struct AlgaeAdvisory: Decodable, Hashable, Sendable {
    let site: String?
    let waterBody: String?
    let county: String?
    let lat: Double?
    let lon: Double?
    let toxin: String?
    let category: String?      // e.g. "danger" / "warning" / "caution" / "detected"
    let dateString: String?

    enum CodingKeys: String, CodingKey {
        case site, waterBody, county, lat, lon, toxin, category
        case dateString = "date"
    }

    static let dangerRank = 3

    /// danger → 3, warning/caution/advisory → 2, any listed bloom → 1, none → 0.
    var severityRank: Int {
        let c = (category ?? "").lowercased()
        if c.contains("danger") { return Self.dangerRank }
        if c.contains("warn") || c.contains("caution") || c.contains("advisor") { return 2 }
        return 1   // present in the snapshot at all ⇒ at least a caution-worthy detection
    }

    var date: Date? {
        guard let dateString else { return nil }
        return Self.isoDay.date(from: dateString)
    }

    var reasonText: String {
        var text = "Toxic algae advisory"
        if let toxin, !toxin.isEmpty { text += " — \(toxin)" }
        return text
    }

    /// Does this advisory apply to `lake`? Proximity within 5 km when the
    /// advisory is geolocated; otherwise a conservative name overlap.
    func matches(lake: Lake) -> Bool {
        if let lat, let lon {
            let here = CLLocation(latitude: lat, longitude: lon)
            if here.distance(from: lake.location) <= 5_000 { return true }
        }
        let target = Self.normalize(lake.name)
        guard target.count >= 4 else { return false }
        for candidate in [site, waterBody].compactMap({ $0 }) {
            let norm = Self.normalize(candidate)
            if norm.count >= 4, norm.contains(target) || target.contains(norm) { return true }
        }
        return false
    }

    /// Lowercase, drop the generic water words and punctuation, so
    /// "Lake Chelan" and "Chelan Lake" both reduce to "chelan".
    private static func normalize(_ s: String) -> String {
        let dropped = ["lake", "pond", "reservoir", "lagoon", "slough"]
        var out = s.lowercased()
        for word in dropped { out = out.replacingOccurrences(of: word, with: " ") }
        return out.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined()
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Shared snapshot cache

/// Fetches the statewide snapshot once per TTL and shares it across all lakes in
/// a refresh. Serves the last good copy if a later fetch fails.
private actor SnapshotCache {
    private var cached: (at: Date, list: [AlgaeAdvisory])?
    private let ttl: TimeInterval = 3_600   // 1h — the snapshot updates a few times a day

    func advisories(url: URL, session: URLSession) async throws -> [AlgaeAdvisory] {
        if let cached, Date().timeIntervalSince(cached.at) < ttl { return cached.list }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if let cached { return cached.list }
                throw AlgaeError.http(http.statusCode)
            }
            let list = AlgaeAdvisoryService.parse(data)
            cached = (Date(), list)
            return list
        } catch {
            if let cached { return cached.list }   // offline: last good snapshot
            throw error
        }
    }
}

enum AlgaeError: Error, LocalizedError {
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .http(let code): return "Algae snapshot returned HTTP \(code)."
        }
    }
}
