import XCTest
@testable import LakeDay

/// Fixture-driven tests for the two News & Alerts parsers (DATA-FEEDS §10).
/// Both `parseAlerts` / `parseNews` are pure static functions with no I/O, so
/// these hit them directly — no network. Fixtures are modeled on the REAL feed
/// shapes captured live: an NWS Heat Advisory feature (from
/// `api.weather.gov/alerts/active`) and Google News RSS `<item>`s (from the
/// `"Green Lake" Seattle algae` search), including the drift they must survive:
/// null fields, missing event/headline, out-of-state false positives, stale
/// items, headlines containing " - ", and malformed payloads.
final class NewsParserTests: XCTestCase {

    // MARK: Fixed clock (GMT) so the recency window is deterministic

    private func gmt(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }
    private lazy var now: Date = gmt(2026, 7, 15)

    private let greenLake = Lake(id: "green-lake", name: "Green Lake",
                                 lat: 47.6806, lon: -122.3345, region: "Seattle",
                                 beaches: [], hazards: [], activities: [],
                                 usgsSiteId: nil, kcBuoyId: nil, popularity: 1.0)

    // MARK: - NWS alerts fixture

    /// Feature 1: real Heat Advisory shape (event + severity + ISO8601 dates).
    /// Feature 2: no `event`, but a `headline` → headline used as title.
    /// Feature 3: no `event` AND no `headline` → skipped.
    /// Feature 4: null `properties` → skipped, no crash.
    private func alertsJSON() -> Data {
        Data("""
        {
          "@context": {"@version": "1.1"},
          "type": "FeatureCollection",
          "features": [
            { "id": "urn:oid:1", "type": "Feature", "geometry": null,
              "properties": {
                "event": "Heat Advisory", "severity": "Moderate",
                "headline": "Heat Advisory issued July 12 at 2:01AM PDT until July 12 at 8:00PM PDT by NWS Seattle WA",
                "effective": "2026-07-12T02:01:00-07:00",
                "onset": "2026-07-12T12:00:00-07:00",
                "ends": "2026-07-12T20:00:00-07:00",
                "expires": "2026-07-12T20:00:00-07:00",
                "senderName": "NWS Seattle WA" } },
            { "id": "urn:oid:2", "type": "Feature", "geometry": null,
              "properties": {
                "event": null, "severity": "Severe",
                "headline": "Flood Warning issued for the Snoqualmie River",
                "effective": "2026-07-14T09:00:00+00:00", "onset": null,
                "ends": null, "expires": "2026-07-16T09:00:00+00:00",
                "senderName": "NWS" } },
            { "id": "urn:oid:3", "type": "Feature", "geometry": null,
              "properties": {
                "event": null, "severity": "Unknown", "headline": null,
                "effective": null, "senderName": "NWS" } },
            { "id": "urn:oid:4", "type": "Feature", "geometry": null,
              "properties": null }
          ]
        }
        """.utf8)
    }

    func testParsesAlertFeatureWithEventSeverityAndDate() throws {
        let alerts = LakeNewsService.parseAlerts(alertsJSON(), now: now)
        let first = try XCTUnwrap(alerts.first)
        XCTAssertEqual(first.kind, .alert)
        XCTAssertEqual(first.title, "Heat Advisory")     // event preferred over headline
        XCTAssertEqual(first.source, "NWS")
        XCTAssertNil(first.url)
        XCTAssertEqual(first.severity, "Moderate")
        // 2026-07-12T02:01:00-07:00 == 2026-07-12T09:01:00Z
        XCTAssertEqual(first.publishedAt, gmt(2026, 7, 12, 9, 1))
    }

    func testAlertFallsBackToHeadlineWhenEventMissing() {
        let alerts = LakeNewsService.parseAlerts(alertsJSON(), now: now)
        XCTAssertEqual(alerts.count, 2)   // features 3 (no text) and 4 (null props) skipped
        XCTAssertEqual(alerts[1].title, "Flood Warning issued for the Snoqualmie River")
    }

    func testAlertsMalformedOrEmptyReturnEmpty() {
        XCTAssertTrue(LakeNewsService.parseAlerts(Data("not json".utf8), now: now).isEmpty)
        XCTAssertTrue(LakeNewsService.parseAlerts(Data("{}".utf8), now: now).isEmpty)
        XCTAssertTrue(LakeNewsService.parseAlerts(Data(#"{"features": []}"#.utf8), now: now).isEmpty)
        XCTAssertTrue(LakeNewsService.parseAlerts(Data(#"{"features": null}"#.utf8), now: now).isEmpty)
        XCTAssertTrue(LakeNewsService.parseAlerts(Data("".utf8), now: now).isEmpty)
    }

    // MARK: - Google News RSS fixture

    /// Item 1: fresh WA Green Lake story (mentions Seattle)        → KEEP
    /// Item 2: "Green Lake, Wisconsin" story (no WA hint)          → DROP
    /// Item 3: WA Green Lake story dated beyond the recency window  → DROP
    /// Item 4: WA story whose headline itself contains " - "       → KEEP, split on LAST
    /// Item 5: duplicate of item 1 by title (different url/source) → DROP (dedup)
    private func rssXML() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
        <title>"Green Lake" - Google News</title>
        <link>https://news.google.com/</link>
        <description>Google News</description>
        <image><title>Google News</title><url>https://x/y.png</url><link>https://news.google.com/</link></image>
        <item>
          <title>Toxic algae found in Seattle's Green Lake - KIRO 7 News Seattle</title>
          <link>https://news.google.com/rss/articles/AAA?oc=5</link>
          <guid isPermaLink="false">AAA</guid>
          <pubDate>Sat, 11 Jul 2026 07:00:00 GMT</pubDate>
          <description>&lt;a href="x"&gt;Toxic algae found in Seattle's Green Lake&lt;/a&gt; &lt;font&gt;KIRO 7 News Seattle&lt;/font&gt;</description>
          <source url="https://www.kiro7.com">KIRO 7 News Seattle</source>
        </item>
        <item>
          <title>Green Lake algae bloom closes beaches in Wisconsin - WISN Milwaukee</title>
          <link>https://news.google.com/rss/articles/BBB?oc=5</link>
          <pubDate>Sun, 12 Jul 2026 07:00:00 GMT</pubDate>
          <description>&lt;font&gt;WISN Milwaukee&lt;/font&gt;</description>
          <source url="https://www.wisn.com">WISN Milwaukee</source>
        </item>
        <item>
          <title>Old toxic algae warning at Green Lake in Seattle - The Seattle Times</title>
          <link>https://news.google.com/rss/articles/CCC?oc=5</link>
          <pubDate>Mon, 01 Dec 2025 07:00:00 GMT</pubDate>
          <description>&lt;font&gt;Seattle&lt;/font&gt;</description>
          <source url="https://www.seattletimes.com">The Seattle Times</source>
        </item>
        <item>
          <title>Stay out - toxic algae at Green Lake, King County says - MyNorthwest.com</title>
          <link>https://news.google.com/rss/articles/DDD?oc=5</link>
          <pubDate>Fri, 10 Jul 2026 07:00:00 GMT</pubDate>
          <description>King County health warning</description>
          <source url="https://mynorthwest.com">MyNorthwest.com</source>
        </item>
        <item>
          <title>Toxic algae found in Seattle's Green Lake - FOX 13 Seattle</title>
          <link>https://news.google.com/rss/articles/EEE?oc=5</link>
          <pubDate>Sat, 11 Jul 2026 09:00:00 GMT</pubDate>
          <description>&lt;font&gt;Seattle&lt;/font&gt;</description>
          <source url="https://www.fox13seattle.com">FOX 13 Seattle</source>
        </item>
        </channel></rss>
        """.utf8)
    }

    private func parsedNews() -> [NewsItem] {
        LakeNewsService.parseNews(rssXML(), now: now,
                                  lakeName: "Green Lake",
                                  regionHints: LakeNewsService.relevanceHints(for: greenLake))
    }

    func testParsesNewsAndStripsSourceSuffix() throws {
        let news = parsedNews()
        let item = try XCTUnwrap(news.first { $0.title.hasPrefix("Toxic algae found") })
        XCTAssertEqual(item.title, "Toxic algae found in Seattle's Green Lake")   // " - KIRO..." stripped
        XCTAssertEqual(item.source, "KIRO 7 News Seattle")
        XCTAssertEqual(item.kind, .news)
        XCTAssertNil(item.severity)
        XCTAssertEqual(item.url?.absoluteString, "https://news.google.com/rss/articles/AAA?oc=5")
        // RFC822 pubDate parsed: Sat, 11 Jul 2026 07:00:00 GMT
        XCTAssertEqual(item.publishedAt, gmt(2026, 7, 11, 7))
    }

    func testSplitsOnLastDashSoInnerDashStaysInHeadline() throws {
        let news = parsedNews()
        let item = try XCTUnwrap(news.first { $0.title.hasPrefix("Stay out") })
        XCTAssertEqual(item.title, "Stay out - toxic algae at Green Lake, King County says")
        XCTAssertEqual(item.source, "MyNorthwest.com")
    }

    func testFiltersOutOfStateAndStaleAndDeduplicates() {
        let news = parsedNews()
        XCTAssertEqual(news.count, 2)   // KIRO + MyNorthwest survive
        XCTAssertFalse(news.contains { $0.title.contains("Wisconsin") })      // wrong region
        XCTAssertFalse(news.contains { $0.title.contains("Old toxic") })      // beyond recency window
        XCTAssertEqual(news.filter { $0.title == "Toxic algae found in Seattle's Green Lake" }.count, 1) // dedup
    }

    func testNewsMalformedXMLReturnsEmpty() {
        let hints = LakeNewsService.relevanceHints(for: greenLake)
        XCTAssertTrue(LakeNewsService.parseNews(Data("<rss><broken>".utf8), now: now,
                                                lakeName: "Green Lake", regionHints: hints).isEmpty)
        XCTAssertTrue(LakeNewsService.parseNews(Data("not xml at all".utf8), now: now,
                                                lakeName: "Green Lake", regionHints: hints).isEmpty)
        XCTAssertTrue(LakeNewsService.parseNews(Data("".utf8), now: now,
                                                lakeName: "Green Lake", regionHints: hints).isEmpty)
    }

    // MARK: - Title split / relevance helpers

    func testSplitTitleHandlesHeadlineContainingDash() {
        XCTAssertEqual(LakeNewsService.splitTitle("A - B - C").headline, "A - B")
        XCTAssertEqual(LakeNewsService.splitTitle("A - B - C").source, "C")
        XCTAssertNil(LakeNewsService.splitTitle("No separator here").source)
    }

    func testLakeNameMatchToleratesLakeWord() {
        XCTAssertTrue(LakeNewsService.titleMatchesLake("Algae at Green Lake today", lakeName: "Green Lake"))
        XCTAssertTrue(LakeNewsService.titleMatchesLake("Rescue on Lake Washington", lakeName: "Lake Washington"))
        XCTAssertTrue(LakeNewsService.titleMatchesLake("Sammamish beach reopens", lakeName: "Lake Sammamish"))
        XCTAssertFalse(LakeNewsService.titleMatchesLake("Seattle heat wave", lakeName: "Lake Washington"))
    }

    func testRegionHintDoesNotFalseMatchWaSubstring() {
        // "water"/"warning"/"Wisconsin" must NOT count as the WA state code.
        XCTAssertFalse(LakeNewsService.mentionsRegion("Green Lake, Wisconsin water warning", hints: ["WA"]))
        XCTAssertTrue(LakeNewsService.mentionsRegion("Beach near Renton, WA closed", hints: ["WA"]))
        XCTAssertTrue(LakeNewsService.mentionsRegion("Advisory in Seattle",
                                                     hints: LakeNewsService.relevanceHints(for: greenLake)))
    }

    // MARK: - Merge / order

    private func alert(_ id: String, _ title: String, day: Int) -> NewsItem {
        NewsItem(id: id, kind: .alert, title: title, source: "NWS", url: nil,
                 publishedAt: gmt(2026, 7, day), severity: "Moderate")
    }
    private func story(_ id: String, day: Int) -> NewsItem {
        NewsItem(id: id, kind: .news, title: id, source: "S",
                 url: URL(string: "https://x/\(id)"), publishedAt: gmt(2026, 7, day), severity: nil)
    }

    func testMergeAlertsFirstNewsNewestFirstCappedAtSix() {
        let merged = LakeNewsService.merge(
            alerts: [alert("a1", "Heat Advisory", day: 14), alert("a2", "Air Quality Alert", day: 15)],
            news: [story("n1", day: 1), story("n2", day: 12), story("n3", day: 5),
                   story("n4", day: 8), story("n5", day: 3), story("n6", day: 2), story("n7", day: 4)])
        XCTAssertEqual(merged.count, 6)                       // cap
        XCTAssertEqual(merged[0].kind, .alert)
        XCTAssertEqual(merged[1].kind, .alert)
        XCTAssertEqual(merged[0].title, "Air Quality Alert")  // newest alert first
        XCTAssertEqual(merged[2].id, "n2")                    // newest news after alerts
        XCTAssertEqual(merged[3].id, "n4")
    }

    func testMergeDeduplicatesAcrossSourcesById() {
        let merged = LakeNewsService.merge(
            alerts: [alert("dup", "Heat Advisory", day: 10)],
            news: [NewsItem(id: "dup", kind: .news, title: "same id", source: "S",
                            url: nil, publishedAt: gmt(2026, 7, 1), severity: nil)])
        XCTAssertEqual(merged.count, 1)
    }
}
