# Algae snapshot scraper

Publishes `docs/algae-snapshot.json` — a small statewide toxic-algae advisory
feed the Lake Day app folds into lake safety for **any** lake (the only algae
signal beyond King County).

## Why a separate job (not in the app)

The source, [nwtoxicalgae.org](https://www.nwtoxicalgae.org/) (WA Dept of Ecology
Freshwater Algae Program), is the only statewide freshwater cyanotoxin database.
But it's an ASP.NET WebForms site behind **F5 bot-defense**: every scripted
postback — even with valid `__VIEWSTATE`/`__EVENTVALIDATION`, session cookie, and
browser headers — 302s to `/error.html`. The `TS01…` cookie needs a JavaScript
challenge solved first. An iOS app can't ship a headless browser, so scraping
must happen **offline**, in a real Chromium, which solves the challenge. The app
then fetches the resulting JSON over plain HTTPS — no WAF involved.

## Run it

**In CI (recommended):** `.github/workflows/algae-snapshot.yml` runs daily
(08:00 PT) and on manual dispatch. It installs Chromium, scrapes, and commits
`docs/algae-snapshot.json` when it changes. GitHub then serves it at:

```
https://raw.githubusercontent.com/<you>/lake-day/main/docs/algae-snapshot.json
```

**Locally:**

```bash
cd tools/algae-scraper
pip install -r requirements.txt
python -m playwright install chromium
python scrape.py --out ../../docs/algae-snapshot.json --days 60
# Watch the browser if F5 blocks headless (e.g. a flagged datacenter IP):
HEADLESS=0 python scrape.py --out ../../docs/algae-snapshot.json
```

## Wire the app

Set the published URL in `LakeDay/Data/Feeds/AlgaeAdvisoryService.swift`:

```swift
static let defaultSnapshotURL: URL? =
    URL(string: "https://raw.githubusercontent.com/<you>/lake-day/main/docs/algae-snapshot.json")
```

Until then it's a clean no-op (nil → no fetch). Once set, any lake within 5 km of
a recent advisory — or whose name matches one — shows `Caution`/`Closed` with the
toxin in the reason, instead of `unknown`.

## Snapshot schema

```json
{
  "generated": "2026-07-12T19:00:00Z",
  "source": "nwtoxicalgae.org",
  "window": {"start": "2026-05-13", "end": "2026-07-12"},
  "advisories": [
    {"site": "Anderson Lake", "county": "Jefferson", "lat": null, "lon": null,
     "toxin": "Anatoxin-a", "value": 2.3, "unit": "ug/L",
     "category": "danger", "date": "2026-07-05"}
  ]
}
```

`category`: `danger` (at/above the WA recreational guideline for that toxin →
maps to `Closed`) or `caution` (a detection below guideline → `Caution`). Only
detections are included; non-detects are dropped.

## Caveats (honest)

- **Coverage is partial** — only lakes participating in Ecology's program are
  sampled; absence of an advisory is *not* proof a lake is safe. The app keeps
  showing `unknown`, never fake-green, when there's no matching advisory.
- **Coordinates are often absent** in the export, so matching falls back to lake
  name overlap. Proximity matching kicks in when the export includes lat/lon.
- **F5 may flag GitHub's datacenter IPs.** If the CI run hits `/error.html`, run
  the job locally (residential IP) or on a self-hosted runner. `HEADLESS=0`
  helps diagnose.
- **The export format can change** (it last changed 6/26/2018). `scrape.py`
  detects columns by fuzzy header match and logs the headers it found; check the
  first CI run's logs and adjust `find_col` candidates if needed.
