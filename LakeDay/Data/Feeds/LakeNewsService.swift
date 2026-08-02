import Foundation

/// Live "News & Alerts" per lake from two verified, key-free sources
/// (DATA-FEEDS §10):
///   1. NWS active alerts — `api.weather.gov/alerts/active?point=LAT,LON`,
///      official GeoJSON, geographically exact (the API filters to the point),
///      REQUIRES a `User-Agent` header or it 403s.
///   2. Google News RSS search — a published RSS feed (consuming RSS ≠ DOM
///      scraping), ToS-grey but accepted; parsed with Foundation's `XMLParser`.
///
/// STATELESS like `AirQualityService`: freshness and stale-fallback are owned by
/// FeedLoader (`CacheTTL.news = 4h`). Both sources are fetched concurrently; if
/// one fails the other still returns. Parsing is deliberately defensive — these
/// are undocumented / drifting feeds, so a malformed payload degrades to `[]`,
/// never a crash. The pure `parseAlerts`/`parseNews` statics have no I/O so the
/// tests hit them directly.
struct LakeNewsService: NewsProviding {

    let session: URLSession
    private static let userAgent = "LakeDay/1.0 (personal app)"
    private static let mergeCap = 6
    /// How far back a news item can be dated and still show. Wide on purpose: a
    /// toxic-algae or drowning story stays relevant for months, and a tight
    /// window made quiet lakes look broken (nothing to show → section hidden).
    static let recencyDays = 180

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: NewsProviding

    func news(for lake: Lake) async throws -> [NewsItem] {
        let now = Date()
        // Fetch both sources concurrently. Each wrapped so one failure can't
        // sink the other — a dead RSS feed still leaves the NWS alert visible.
        async let alertsTask = fetchAlerts(for: lake, now: now)
        async let newsTask = fetchNews(for: lake, now: now)
        let alerts = await alertsTask
        let news = await newsTask
        return Self.merge(alerts: alerts, news: news)
    }

    // MARK: - NWS alerts fetch

    private func fetchAlerts(for lake: Lake, now: Date) async -> [NewsItem] {
        guard let url = Self.alertsURL(lat: lake.lat, lon: lake.lon) else { return [] }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              Self.isOK(response) else { return [] }
        return Self.parseAlerts(data, now: now)
    }

    static func alertsURL(lat: Double, lon: Double) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.weather.gov"
        components.path = "/alerts/active"
        components.queryItems = [URLQueryItem(name: "point", value: "\(lat),\(lon)")]
        return components.url
    }

    // MARK: - Google News RSS fetch

    private func fetchNews(for lake: Lake, now: Date) async -> [NewsItem] {
        guard let url = Self.newsURL(for: lake) else { return [] }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              Self.isOK(response) else { return [] }
        return Self.parseNews(data, now: now,
                              lakeName: lake.name,
                              regionHints: Self.relevanceHints(for: lake))
    }

    /// `"<lake name>" (<primary city> OR Washington) (algae OR toxic OR ...)`.
    /// Percent-encoded via URLComponents. The quoted lake name scopes the query;
    /// the OR'd location and keyword clusters surface local safety stories.
    static func newsURL(for lake: Lake) -> URL? {
        let city = primaryCity(for: lake)
        let location = city.isEmpty ? "Washington" : "(\(city) OR Washington)"
        let keywords = "(algae OR toxic OR bacteria OR closed OR closure OR advisory OR reopen OR drowning OR rescue OR \"water quality\" OR \"water temperature\" OR unsafe OR warning OR swim OR swimming OR beach OR heat OR smoke OR wildfire OR boating)"
        let query = "\"\(lake.name)\" \(location) \(keywords)"

        var components = URLComponents()
        components.scheme = "https"
        components.host = "news.google.com"
        components.path = "/rss/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        return components.url
    }

    /// First token of the region ("Seattle / Eastside" → "Seattle").
    static func primaryCity(for lake: Lake) -> String {
        lake.region
            .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "&" })
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Region tokens plus the statewide markers, used to keep only WA stories.
    /// De-duped case-insensitively, order preserved.
    static func relevanceHints(for lake: Lake) -> [String] {
        var hints = lake.region
            .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "&" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        hints.append(contentsOf: ["Washington", "Seattle", "King County"])

        var seen = Set<String>()
        return hints.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Pure alert parse (no I/O — tests hit this directly)

    /// NWS GeoJSON `Data` → `[NewsItem]`. All fields optional, nulls tolerated.
    /// A feature with no usable `event` AND no `headline` is skipped. Non-JSON /
    /// `{}` / malformed → `[]`.
    static func parseAlerts(_ data: Data, now: Date) -> [NewsItem] {
        guard let root = try? JSONDecoder().decode(AlertsResponse.self, from: data),
              let features = root.features else {
            return []
        }
        var out: [NewsItem] = []
        for feature in features {
            guard let props = feature.properties else { continue }
            let event = props.event?.trimmedNonEmpty
            let headline = props.headline?.trimmedNonEmpty
            guard let title = event ?? headline else { continue }   // no usable text → skip
            let date = parseISO8601(props.effective) ?? parseISO8601(props.onset)
            out.append(NewsItem(id: makeID(url: nil, title: title),
                                kind: .alert,
                                title: title,
                                source: "NWS",
                                url: nil,
                                publishedAt: date,
                                severity: props.severity?.trimmedNonEmpty))
        }
        return out
    }

    // MARK: - Pure news parse (no I/O — tests hit this directly)

    /// RSS XML `Data` → filtered `[NewsItem]`. Parsed synchronously via
    /// `XMLParser`. Malformed XML → `[]`. For each `<item>`: split the title on
    /// the LAST `" - "` (headline + source), parse the RFC822 `pubDate`, then
    /// keep it only when it (a) names the lake, (b) is within the last 30 days
    /// of `now`, and (c) mentions a WA region hint — killing "Green Lake,
    /// Wisconsin" false positives. De-duped by normalized title.
    static func parseNews(_ data: Data, now: Date, lakeName: String, regionHints: [String]) -> [NewsItem] {
        let delegate = RSSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }   // fatal XML error → degrade to empty

        var seenTitles = Set<String>()
        var out: [NewsItem] = []
        for raw in delegate.items {
            guard let rawTitle = raw.title?.trimmedNonEmpty else { continue }
            let (headline, sourceFromTitle) = splitTitle(rawTitle)
            let descriptionText = raw.description ?? ""

            // (a) names the lake
            guard titleMatchesLake(rawTitle, lakeName: lakeName) else { continue }
            // (b) within the last 30 days (undated → can't confirm → drop)
            guard let date = parseRFC822(raw.pubDate) else { continue }
            let age = now.timeIntervalSince(date)
            guard age <= TimeInterval(Self.recencyDays) * 86_400, age >= -2 * 86_400 else { continue }
            // (c) mentions a WA region hint (in title OR description)
            guard mentionsRegion(rawTitle + " " + descriptionText, hints: regionHints) else { continue }

            // Dedup by normalized headline.
            let key = headline.lowercased()
            guard seenTitles.insert(key).inserted else { continue }

            let source = raw.sourceName?.trimmedNonEmpty ?? sourceFromTitle ?? "News"
            let url = raw.link?.trimmedNonEmpty.flatMap { URL(string: $0) }
            out.append(NewsItem(id: makeID(url: url, title: headline),
                                kind: .news,
                                title: headline,
                                source: source,
                                url: url,
                                publishedAt: date,
                                severity: nil))
        }
        return out
    }

    // MARK: - Merge (alerts first, news newest-first, dedup by id, cap 6)

    static func merge(alerts: [NewsItem], news: [NewsItem], cap: Int = mergeCap) -> [NewsItem] {
        let ordered = (alerts + news).sorted(by: NewsItem.orderedBefore)
        var seen = Set<String>()
        var out: [NewsItem] = []
        for item in ordered {
            guard seen.insert(item.id).inserted else { continue }   // dedup across both
            out.append(item)
            if out.count >= cap { break }
        }
        return out
    }

    // MARK: - String / date helpers

    /// Dedup key: normalized URL when present, else lowercased title.
    static func makeID(url: URL?, title: String) -> String {
        if let url {
            return url.absoluteString.lowercased()
        }
        return title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split a Google News title on the LAST `" - "` → (headline, source).
    /// Tolerates headlines that themselves contain `" - "`. If there is no
    /// separator (or either side is empty) the whole title is the headline.
    static func splitTitle(_ title: String) -> (headline: String, source: String?) {
        if let range = title.range(of: " - ", options: .backwards) {
            let headline = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let source = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !headline.isEmpty && !source.isEmpty {
                return (headline, source)
            }
        }
        return (title.trimmingCharacters(in: .whitespaces), nil)
    }

    /// True when `title` names the lake, case-insensitively, tolerating the lake
    /// name with or without the word "Lake" ("Lake Sammamish" ~ "Sammamish").
    static func titleMatchesLake(_ title: String, lakeName: String) -> Bool {
        let lowerTitle = title.lowercased()
        let fullName = lakeName.lowercased().trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty, lowerTitle.contains(fullName) { return true }
        // Fall back to the distinctive core (name minus the word "lake").
        let core = fullName
            .split(whereSeparator: { $0 == " " })
            .filter { $0 != "lake" }
            .joined(separator: " ")
        return core.count >= 4 && lowerTitle.contains(core)
    }

    /// True when `text` mentions any region hint. Longer hints match as a
    /// case-insensitive substring; the 2-letter state code "WA" matches only as
    /// a standalone token, so "water"/"warning" never count as Washington.
    static func mentionsRegion(_ text: String, hints: [String]) -> Bool {
        for hint in hints where hint.count >= 2 {
            if hint.uppercased() == "WA" { continue }   // handled below as a token
            if text.range(of: hint, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }
        return containsStateAbbrev(text)
    }

    /// Standalone uppercase "WA" (state abbreviation), case-sensitive.
    static func containsStateAbbrev(_ text: String, code: String = "WA") -> Bool {
        let token = Substring(code)
        return text.split(whereSeparator: { !$0.isLetter }).contains(token)
    }

    /// RFC822 pubDate → Date (`"Tue, 19 May 2026 07:00:00 GMT"`).
    static func parseRFC822(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }

    /// ISO8601 timestamp → Date (`"2026-07-12T02:01:00-04:00"`), tolerating
    /// fractional seconds.
    static func parseISO8601(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    // MARK: - Network helper

    private static func isOK(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - NWS wire types (all optional — parse defensively)

    private struct AlertsResponse: Decodable {
        let features: [AlertFeature]?
    }

    private struct AlertFeature: Decodable {
        let properties: AlertProperties?
    }

    private struct AlertProperties: Decodable {
        let event: String?
        let severity: String?
        let headline: String?
        let effective: String?
        let onset: String?
        let ends: String?
        let expires: String?
        let senderName: String?
    }
}

// MARK: - RSS delegate (synchronous XMLParser walk)

/// Collects `<item>` fields from a Google News RSS feed. Channel-level `<title>`
/// / `<image>` etc. are ignored because their end events fire while `current`
/// is nil. Buffer is reset on every element start so text never bleeds across
/// tags. Used only synchronously inside `parseNews` on the calling thread.
private final class RSSParserDelegate: NSObject, XMLParserDelegate {

    struct RawItem {
        var title: String?
        var link: String?
        var pubDate: String?
        var description: String?
        var sourceName: String?
        var sourceURL: String?
    }

    private(set) var items: [RawItem] = []
    private var current: RawItem?
    private var buffer = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        buffer = ""
        switch elementName.lowercased() {
        case "item":
            current = RawItem()
        case "source":
            current?.sourceURL = attributeDict["url"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { buffer += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard current != nil else { return }   // ignore channel-level elements
        switch elementName.lowercased() {
        case "title":       if current?.title == nil { current?.title = text }
        case "link":        if current?.link == nil { current?.link = text }
        case "pubdate":     current?.pubDate = text
        case "description": current?.description = text
        case "source":      current?.sourceName = text
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default:
            break
        }
    }
}

// MARK: - Small string helper (local; mirrors the KC service's trimmer)

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
