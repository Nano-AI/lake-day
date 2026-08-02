# Lake Day — Verified Data Feeds

Research verified live 2026-07-11. No API keys required on any endpoint.

## 1. King County beach status (PRIMARY — one call does bacteria + closures + water temp + coords)

ArcGIS FeatureServer `Swim_beach_temperature_view` — the live layer behind the county's public beach map.

- **GeoJSON, all beaches:** `https://services.arcgis.com/Ej0PsM5Aw677QF1W/arcgis/rest/services/Swim_beach_temperature_view/FeatureServer/0/query?where=1=1&outFields=*&f=geojson`
- One feature per beach (~40; filter `Beach_Has_Current_Data == "True"` → 30 monitored). Latest sample only, no history.
- Updated weekly after Mon/Tue sampling (posted ~Wed). Seasonal: mid-May–late-Sept.

Key fields:

| Field | Meaning |
|---|---|
| `siteName` / `Beach` | full / short beach name |
| `Water_Body` | lake name |
| `Beach_Status` | `OK to swim (low bacteria)` / `Stay out of the water` / `No recent data` / `Not a currently monitored beach` |
| `Reason_For_Closure` | `High Bacteria` / `Toxic Algae` / null |
| `Closure_Explanation_For_Web` | free text |
| `locator` | site code — stable join key (e.g. `0852SB`) |
| `left_`,`middle`,`right_` | 3 E. coli samples MPN/100mL |
| `Geomean30d`, `nSamplesHigh30d`, `HighToday` | trend fields |
| `WaterTempC`,`WaterTempF` | water temp at sampling |
| `SampleTimestamp` | epoch ms |
| `lat`,`lon` | coords (also geometry) |

Caveats: undocumented production feed — parse defensively, ignore `_<epoch>`-suffixed duplicate fields, treat unknown `Beach_Status` strings as `.unknown`. `HighToday`/`Beach_Has_Current_Data` are strings "TRUE"/"True".

## 2. History (charts, later): Socrata `mbzm-4r9y`

`https://data.kingcounty.gov/resource/mbzm-4r9y.json?locator=0852SB&$order=date DESC&$limit=10`
Fields: `beach, jurisdiction, locator, date, day, time, samplea/b/c, geomean30d, nsampleshigh30d, hightoday, watertempc, watertempf`. 2019→present, numbers as strings. No coords, no status — join to feed 1 by `locator`. (Old asset `tc7s-d6aj` is a dead href — do not use.)

## 3. Buoy profiles — SKIP for v1

`green2.kingcounty.gov/lake-buoy/DataScrape.aspx?type=Profile&buoy=Washington&year=2026&month=7` works but returns HTML tables, provisional data. Feed 1's `WaterTempF` suffices. Revisit only if depth profiles wanted.

## 4. Monitored beaches (30, verified — use for lakes.json)

`locator` = join key. 11 lakes, 30 beaches: Washington (17 beaches), Sammamish (3), Green Lake (2), one each: Angle, Beaver, Echo, Fivemile, Meridian, Wilderness, Pine, Rattlesnake.

| Beach | Lake | Lat | Lon | Locator |
|---|---|---|---|---|
| Angle Lake Beach | Angle Lake | 47.4275 | -122.2933 | A732SB |
| Beaver Lake Beach | Beaver Lake | 47.58738 | -122.00242 | A709SB |
| Echo Lake Beach | Echo Lake | 47.77299 | -122.34007 | A764SB |
| Enatai Beach | Lake Washington | 47.57883 | -122.19703 | ENATAISB |
| Fivemile Lake Beach | Fivemile Lake | 47.27141 | -122.28513 | A735SB |
| Gene Coulon Memorial Beach | Lake Washington | 47.50463 | -122.20293 | 0828SB |
| Green Lake - East Beach | Green Lake | 47.68039 | -122.32955 | A734SB |
| Green Lake - West Beach | Green Lake | 47.68217 | -122.33933 | A734WSB |
| Groveland Beach | Lake Washington | 47.55132 | -122.23442 | GROVELDSB |
| Houghton Beach | Lake Washington | 47.65962 | -122.20627 | A422SB |
| Idylwood Beach | Lake Sammamish | 47.64164 | -122.09982 | 0602SB |
| Juanita Beach | Lake Washington | 47.70421 | -122.21463 | 0806SB |
| Kennydale Beach | Lake Washington | 47.5232 | -122.2078 | KNYDALESB |
| Lake Meridian Beach | Lake Meridian | 47.35875 | -122.14556 | A728SB |
| Lake Sammamish SP – Tibbets Beach | Lake Sammamish | 47.55684 | -122.07032 | 0615SB |
| Lake Wilderness Beach | Lake Wilderness | 47.37695 | -122.03859 | O717SB |
| Luther Burbank Beach | Lake Washington | 47.58804 | -122.22302 | SD017SB |
| Madison Park Beach | Lake Washington | 47.6359 | -122.27526 | 0852SB |
| Madrona Beach | Lake Washington | 47.60896 | -122.28137 | SD007SB |
| Magnuson Beach | Lake Washington | 47.68062 | -122.2454 | 0826SB |
| Matthews Beach | Lake Washington | 47.69593 | -122.27143 | 0818SB |
| Meydenbauer Bay Beach | Lake Washington | 47.61123 | -122.21176 | 0834SB |
| Mount Baker Beach | Lake Washington | 47.58354 | -122.28612 | 0820SB |
| Newcastle Beach | Lake Washington | 47.56561 | -122.19148 | 083930SB |
| Pine Lake Beach | Pine Lake | 47.58737 | -122.03977 | E708SB |
| Pritchard Island Beach | Lake Washington | 47.52996 | -122.26188 | 4903SB |
| Rattlesnake Lake Beach | Rattlesnake Lake | 47.43391 | -121.7662 | A999SB |
| Sammamish Landing Beach | Lake Sammamish | 47.64865 | -122.08846 | SAMMLANDINGSB |
| Seward Park – Andrews Bay Beach | Lake Washington | 47.55154 | -122.25652 | 0813SB |
| Waverly Beach | Lake Washington | 47.687066 | -122.21724 | WAVRLYPSB |

Not currently monitored (filter out): Duck Island Launch, Magnuson Off-Leash, Marina Park, Medina Beach, NE 130th Pl, OO Denny, Yarrow Bay, Cottage Lake, Lake Jeane. Algae-only site: Lake Marcel (47.695496, -121.917686).

## 5. Toxic algae

### 5a. King County beaches — free, via feed 1
Algae status per beach = feed 1's `Reason_For_Closure == "Toxic Algae"`. Covers all bundled KC lakes at no extra cost.

### 5b. Statewide (search-added lakes) — offline scraper → JSON snapshot
nwtoxicalgae.org (WA Ecology) is the only statewide freshwater cyanotoxin DB, but it's ASP.NET WebForms behind **F5 bot-defense**: every *scripted* postback — even with valid `__VIEWSTATE`/`__EVENTVALIDATION`, session cookie, and browser headers — 302s to `/error.html` (the `TS01…` cookie needs a JS challenge). No ArcGIS service, zero data.wa.gov datasets, no other county exposes a KC-style feed (verified 2026-07-12).

**Solution (implemented):** `tools/algae-scraper/` runs real Chromium (Playwright, scheduled GitHub Action) → solves the challenge → exports the statewide toxin CSV → publishes `docs/algae-snapshot.json`. The app's `AlgaeAdvisoryService` fetches that JSON over plain HTTPS and folds "toxic algae near this lake" into safety (proximity ≤ 5 km, else lake-name overlap) for **any** lake — the only algae signal beyond KC. Enable by setting `AlgaeAdvisoryService.defaultSnapshotURL`. Coverage is partial (only program-sampled lakes); absence ≠ safe, so it never fake-greens.

## 6. USGS NWIS — dropped for v1

Endpoint works (`waterservices.usgs.gov/nwis/iv/?format=json&sites={id}&parameterCd=00010`, WaterML-JSON, 15-min updates) BUT: Lake Washington has no temp gauge, Lake Sammamish reports elevation only, same story for other swim lakes. Only Cedar River at Renton (12119000, live 19.3°C) as weak proxy.

**v1 decision:** water temp = feed 1's `WaterTempF` (weekly, sampled with bacteria; staleness always shown). USGS = future enrichment.

## 7. Open-Meteo — verified param names (canonical, underscore style)

```
https://api.open-meteo.com/v1/forecast?latitude=47.6&longitude=-122.3
  &hourly=temperature_2m,cloud_cover,wind_speed_10m,precipitation_probability,uv_index
  &daily=sunrise,sunset,uv_index_max
  &current=temperature_2m,cloud_cover,wind_speed_10m
  &temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America/Los_Angeles
```

- Arrays parallel to `hourly.time[]` / `daily.time[]` (index-aligned).
- Verified live for Seattle. Refreshed hourly, ~10k calls/day free, no key.
- Marine API returns null over lakes — NOT a water-temp source.

## 8. Open-Meteo Air Quality — ADD to v1 (wildfire smoke)

```
https://air-quality-api.open-meteo.com/v1/air-quality?latitude=..&longitude=..&hourly=pm2_5,us_aqi
```
Verified live (Seattle pm2_5 8.6 µg/m³, us_aqi 36). Smoke = real WA summer lake-day killer. Show AQI on detail view; verdict mentions smoke when us_aqi ≥ 101 (Unhealthy for Sensitive Groups+).

## 9. Hazards — curate manually (confirmed: no structured source)

Hand-write per lake in lakes.json. Auto-signal available: cold-shock flag when water temp < 70°F alongside big air-water gap (matches DOH messaging).

## 10. News & Alerts — NWS alerts + Google News RSS (ADD to v1, display-only)

Live per-lake "News & Alerts" strip. Two key-free sources, fetched concurrently
and merged (alerts first, then news newest-first, dedup by id, cap 6). Both
verified live 2026-07-12. **Display-only — never a RatingEngine input.** Parsed
by the pure statics `LakeNewsService.parseAlerts` / `parseNews`.

### 10a. NWS active alerts (official, geographically exact)

```
https://api.weather.gov/alerts/active?point=LAT,LON
```

- GeoJSON `FeatureCollection`. The API filters to the point, so every returned
  feature applies to the lake — always keep them (no client-side geo filtering).
- **REQUIRES a `User-Agent` header** (`"LakeDay/1.0 (personal app)"`) or it 403s.
  (`curl` sends its own UA, so it appears to work bare — the app must set one.)
- `features[].properties`: `event` ("Heat Advisory"), `severity`
  ("Extreme/Severe/Moderate/Minor/Unknown"), `headline`, `description`,
  `effective`/`onset`/`ends`/`expires` (ISO8601 with offset, e.g.
  `2026-07-12T02:01:00-07:00`), `senderName`. Real sample seen:
  `event="Heat Advisory", severity="Moderate", effective="…T02:01:00-07:00",
  senderName="NWS …"`. Some features are `messageType`/`status`=`Test` (kept —
  harmless) and geometry can be `null`.
- Map: `event ?? headline` → title, `effective ?? onset` → date, `severity`
  carried. Feature with no `event` AND no `headline` is skipped. WA often has
  **zero** active alerts (`features: []`) — normal, degrade to empty.

### 10b. Google News RSS search (ToS-grey, accepted)

```
https://news.google.com/rss/search?q=QUERY&hl=en-US&gl=US&ceid=US:en
```

Query built per lake: `"<lake name>" (<primary region city> OR Washington)
(algae OR toxic OR bacteria OR closed OR closure OR advisory OR drowning OR
"water quality" OR unsafe OR warning)`, percent-encoded via URLComponents.

- XML RSS 2.0. Each `<item>`: `<title>` = `"Headline - Source Name"`, `<link>`
  (a `news.google.com/rss/articles/…?oc=5` redirect), `<pubDate>` (RFC822, e.g.
  `Tue, 19 May 2026 07:00:00 GMT`), `<source url="…">Source Name</source>`,
  `<description>` (escaped HTML). Parsed with Foundation's **`XMLParser`**
  (consuming a published RSS feed ≠ DOM scraping) driven synchronously by a
  delegate. Malformed XML → `[]`.
- Title split on the **LAST** `" - "` → headline + source (tolerates headlines
  that themselves contain `" - "`). Source preferred from the `<source>` tag.
- **ToS caveat:** the feed's copyright restricts use to personal feed readers.
  This is a personal app; consuming the published RSS is an accepted grey-area
  decision (see project memory), implemented cleanly (no scraping, no key).
- **False-positive mitigation** (the `"Green Lake, Wisconsin"` problem): an item
  is kept only when it (1) names the lake (case-insensitive, tolerating the name
  with/without the word "Lake"), (2) has a parseable pubDate within the last 180
  days (`recencyDays`; wide so notable stories don't vanish and quiet lakes
  aren't blank), and (3) mentions a WA region hint (region token, "Washington",
  "Seattle", "King County", or the standalone state code "WA") in title or
  description. The "WA" code matches only as a whole token, so "water" /
  "warning" never masquerade as Washington. Deduped by normalized title.
