import Foundation

/// One live "News & Alerts" entry for a lake — either an official NWS weather
/// alert (geographically exact for the lake's point) or a matched local news
/// story (Google News RSS). Display-only: never a RatingEngine input.
///
/// `Codable` so a lake's merged items cache as one `[NewsItem]` under the
/// FeedLoader's `news-<lakeId>` key; `Sendable`/`Hashable` so `LakeUIState`
/// stays a value type the ViewModel can fan out across a task group.
struct NewsItem: Identifiable, Hashable, Sendable, Codable {
    enum Kind: String, Codable, Sendable { case alert, news }

    /// Stable dedup key: the normalized URL when present, else the lowercased
    /// title. Alerts carry no URL, so they dedup on their event/headline text.
    let id: String
    let kind: Kind
    /// For news, the headline with the trailing `" - Source"` suffix stripped.
    let title: String
    /// `"NWS"` for alerts, or the news source (e.g. `"KIRO 7 News Seattle"`).
    let source: String
    let url: URL?
    let publishedAt: Date?
    /// NWS severity ("Extreme/Severe/Moderate/Minor/Unknown"); nil for news.
    let severity: String?

    /// Sort ordering: alerts before news, then newest first (undated last).
    /// Used by the merge step and any view that re-sorts a mixed list.
    static func orderedBefore(_ a: NewsItem, _ b: NewsItem) -> Bool {
        if a.kind != b.kind { return a.kind == .alert }   // alerts first
        switch (a.publishedAt, b.publishedAt) {
        case let (da?, db?): return da > db               // newest first
        case (_?, nil):      return true                  // dated before undated
        case (nil, _?):      return false
        case (nil, nil):     return false
        }
    }
}
