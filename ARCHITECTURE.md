# Lake Day — Architecture

SwiftUI, iOS 17+, no backend. All feeds fetched on-device. Free Apple account (no WeatherKit — Open-Meteo instead). Generated Xcode project via XcodeGen (`project.yml`).

## Decisions (from grill session, see memory)

- Personal tool, WA lakes only, curated bundled lake list.
- Feeds isolated behind one parser type each — county formats change without notice; a broken feed degrades to "unknown", never crashes, never fakes data.
- Staleness is first-class: every reading carries its timestamp; UI always shows age.
- Traffic = proxy, labeled estimate: MapKit `MKDirections` traffic ETA vs `expectedTravelTime` baseline ratio (today) + weekend/holiday/weather heuristic (future days). No Google scraping.

## Layout

```
lake-day/
├── project.yml                     # XcodeGen → LakeDay.xcodeproj
├── DESIGN.md / ARCHITECTURE.md
└── LakeDay/
    ├── App/
    │   └── LakeDayApp.swift
    ├── Models/
    │   ├── Lake.swift              # id, name, coords, region, beaches[], hazards[], activities[], usgsSiteId?, buoyId?
    │   ├── Beach.swift             # name, coords, kcSiteName (feed join key)
    │   ├── SafetyStatus.swift      # open/caution/closed/unknown + reason + sampledAt
    │   ├── Conditions.swift        # waterTemp(reading+age), forecast days
    │   └── LakeScore.swift         # total + components (sunAir, water, crowds, wind) + verdict text
    ├── Data/
    │   ├── lakes.json              # bundled curated lake list (schema below)
    │   ├── LakeStore.swift         # loads bundle json, exposes [Lake]
    │   ├── FeedCache.swift         # actor; per-feed TTL memory+disk cache
    │   └── Feeds/
    │       ├── KingCountyBeachService.swift   # ArcGIS GeoJSON: status+closure reason (bacteria AND algae)+E.coli+water temp+coords, one call (DATA-FEEDS.md §1)
    │       ├── OpenMeteoService.swift         # 7-day forecast (DATA-FEEDS.md §7)
    │       ├── AirQualityService.swift        # Open-Meteo AQI/pm2.5 — wildfire smoke (DATA-FEEDS.md §8)
    │       ├── TrafficService.swift           # MapKit ETA proxy + heuristic
    │       └── LakeNewsService.swift          # NWS alerts + Google News RSS, XMLParser (DATA-FEEDS.md §10)
    # ToxicAlgaeService + USGS WaterTempService REMOVED post-research: no algae API exists
    # (KC feed carries algae closures); no USGS temp gauge on any v1 lake (KC feed carries WaterTempF)
    ├── Scoring/
    │   └── RatingEngine.swift      # pure function, unit-tested
    ├── ViewModels/
    │   └── LakesViewModel.swift    # @Observable; fan-out fetch, per-lake state
    └── Views/
        ├── Theme.swift             # DESIGN.md tokens: colors, type styles
        ├── Home/  LakeListView, LakeMapHeader, LakeCard, SafetyPill
        └── Detail/ LakeDetailView, BuoyGauge, ComponentBars, DayStrip, BeachRow, NewsSection
└── LakeDayTests/
    ├── RatingEngineTests.swift
    └── ParserTests.swift           # fixture JSON per feed
```

## lakes.json schema

```json
{
  "lakes": [{
    "id": "lake-sammamish",
    "name": "Lake Sammamish",
    "lat": 47.5893, "lon": -122.0821,
    "usgsSiteId": null,
    "kcBuoyId": "sammamish",
    "popularity": 0.7,
    "beaches": [{ "name": "Idylwood Beach", "lat": 47.6497, "lon": -122.1076, "kcSiteName": "Idylwood Park" }],
    "hazards": ["Cold below the surface layer even in August", "Heavy boat traffic on weekends — stay inside swim lines"],
    "activities": ["swim", "paddle", "boat", "beach"]
  }]
}
```

Join key is the county `locator` code (e.g. `0852SB`) — stable, verified for all 30 monitored beaches in DATA-FEEDS.md §4. (`kcSiteName` superseded post-research.) Parsers log unmatched locators, never crash.

AQI: displayed metric on detail view + verdict mentions smoke at us_aqi ≥ 101. NOT in score weights v1 (user-approved formula stays; revisit after real weekends).

News & Alerts: `NewsProviding` (`LakeNewsService`) merges NWS weather alerts with matched local news (Google News RSS) per lake — a live detail-only strip, cached 4h, NOT a score input (DATA-FEEDS.md §10). One malformed/undocumented feed degrades to empty, never crashes; region + 30-day filtering kills out-of-state false positives.

## RatingEngine spec

Pure: `(SafetyStatus, waterTempF?, DayForecast, CrowdEstimate) -> LakeScore?`

1. **Hard zero:** safety == closed (bacteria closure or toxic-algae advisory) → returns nil score with reason; UI shows slashed gray gauge, no number.
2. Components, each normalized 0–1 then weighted:
   - **Sun+air 40%:** air-temp curve (peak 80–88°F, taper outside 68–95), minus cloud-cover and precip-probability penalties over the 10:00–18:00 window.
   - **Water temp 25%:** <60°F → ≤0.2 (cold-shock territory), 60–65 → 0.2–0.5, 66–72 → 0.5–0.9, ≥73 → 1.0. Missing → component excluded, weights renormalized, UI marks "no reading".
   - **Crowds 20%:** (weekend/holiday base + weather-goodness coupling, "nice Saturday = packed") × per-lake `popularity` weight (hand-set 0–1; Green Lake ≈ 1, remote lakes ≈ 0.35 — no free real busyness feed exists, verified) ± live MapKit ETA ratio when scoring today. Always labeled estimate.
   - **Wind 15%:** ≤5 mph → 1.0, taper to 0 at 18 mph.
3. Caution status caps total at 60 and prepends reason to verdict.
4. Verdict sentence generated from dominant component (DESIGN.md copy rules).

Weights in one constants struct — tuning after real weekends is expected.

## Concurrency & failure

- async/await; `FeedCache` is an actor. TTLs: bacteria 6h, algae 6h, water temp 1h, forecast 3h, air quality 3h, news 4h, ETA 15min.
- Each feed: `Result`-style per-lake outcome; failure → `.unknown` + last-cached with age label. App never blocks on one slow feed (task group, per-feed timeout 10s).
- No feed writes state directly; ViewModel merges.

## Build

- XcodeGen: `brew install xcodegen && xcodegen` → open `LakeDay.xcodeproj`.
- Target iOS 17.0, Swift 5.9, `NSLocationWhenInUseUsageDescription` for distance/ETA.
- No third-party dependencies. None.
