# Lake Day

Which lake, which day. Personal iOS app for Washington lake days: live swim-beach safety (bacteria + toxic algae closures), water temp, weather-scored "lake day" rating, crowd estimate, wildfire-smoke AQI — for 11 King County lakes / 30 monitored beaches.

Any other Washington lake can be added by search (MapKit). Added lakes score on the coordinate feeds — weather, air, drive time, crowds — but show water safety as "unknown", because the county bacteria program only samples King County beaches.

Docs: [IDEA.md](IDEA.md) (brief) · [ARCHITECTURE.md](ARCHITECTURE.md) · [DESIGN.md](DESIGN.md) · [DATA-FEEDS.md](DATA-FEEDS.md) (verified endpoints)

## Setup (one-time)

1. **Install Xcode** from the Mac App Store (needed to build/run; nothing else works without it). First launch: accept license, let it install iOS components. Then point the CLI at it:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   ```
2. **Generate the Xcode project** (project file is not checked in; [XcodeGen](https://github.com/yonaskolb/XcodeGen) builds it from `project.yml`):
   ```sh
   brew install xcodegen   # if not already installed
   cd ~/Documents/lake-day && xcodegen
   ```
3. **Open and run:**
   ```sh
   open LakeDay.xcodeproj
   ```
   Pick the LakeDay scheme → iPhone simulator → Run. For your phone: select your device, set your personal team under Signing & Capabilities (free Apple ID works; app re-signs weekly on free accounts).

## Tests

Product → Test in Xcode, or:
```sh
xcodebuild test -scheme LakeDay -destination 'platform=iOS Simulator,name=iPhone 17'
```
Covers the rating engine (score curves, safety hard-zero, caution cap) and feed parsers (county GeoJSON, air quality, malformed-input resilience).

## Data sources (all free, no keys)

| Data | Source | Cadence |
|---|---|---|
| Beach safety, closures, E. coli, water temp, coords | King County ArcGIS `Swim_beach_temperature_view` | weekly (Mon/Tue sampling, posted ~Wed), seasonal mid-May–Sept |
| 7-day forecast | Open-Meteo | hourly |
| Air quality / smoke | Open-Meteo air-quality API | hourly |
| Drive-time crowd proxy | Apple MapKit directions (on-device) | live, labeled estimate |
| News & weather alerts | NWS alerts API + Google News RSS (per lake) | live, cached 4h |

Sampling is weekly — the app always shows data age ("sampled Tue") rather than pretending freshness. Crowd levels are estimates, labeled as such. When a feed breaks, status degrades to "unknown", never a fake green.

## Rating

Safety first: an active closure (high bacteria or toxic algae) zeroes the score — gauge shows slashed, no number. Otherwise: sun + air temp 40%, water temp 25%, crowds 20%, wind 15%; caution states cap the score at 60. Weights live in one constants struct in `Scoring/RatingEngine.swift` — tune after real weekends.

## Toxic-algae snapshot

`nwtoxicalgae.org` sits behind F5 bot-defense, so the app can't scrape it. Instead `.github/workflows/algae-snapshot.yml` runs a real Chromium (Playwright, `tools/algae-scraper/`) daily at 8am PT and commits `docs/algae-snapshot.json`. The app reads that snapshot and folds statewide advisories into safety for any lake — the only algae signal beyond King County.

To turn it on after the first Action run: set `AlgaeAdvisoryService.defaultSnapshotURL` to this repo's raw URL for `docs/algae-snapshot.json`. Left `nil`, the feed is a clean no-op rather than a stream of failed fetches.

## License

MIT — see [LICENSE](LICENSE). Personal project, no warranty; safety data is republished from King County / NWS / Open-Meteo and is not a substitute for posted signage at the beach.
