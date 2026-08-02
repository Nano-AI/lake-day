# Deep-research prompt — data sources for Lake Day

Paste the block below into Gemini (Deep Research mode). It hunts for *consistent, programmatically-accessible* data to replace/augment Lake Day's current feeds — the crowding proxy above all.

Current Lake Day feeds (context for the prompt): King County ArcGIS `Swim_beach_temperature_view` (bacteria + algae closures + weekly water temp + coords), Open-Meteo forecast + air-quality, Apple MapKit drive-time ratio as a *proxy* for crowding. The crowding number is an estimate, not real occupancy — that is the biggest weakness.

---

## The prompt

You are a data-sourcing analyst. I'm building a **personal** iOS app ("Lake Day") that scores swim days for **King County, Washington lakes** — specifically: Lake Washington, Lake Sammamish, Green Lake, Angle Lake, Beaver Lake, Echo Lake, Fivemile Lake, Lake Meridian, Lake Wilderness, Pine Lake, and Rattlesnake Lake. It's not commercial; free or cheap and stable matters more than enterprise-grade.

I already have: bacteria/toxic-algae closures + weekly water temperature (King County ArcGIS beach feed), weather + air-quality (Open-Meteo), and a drive-time-based *proxy* for crowding (Apple MapKit). I want to know what **real, consistent, machine-readable** data exists online to improve each metric — and especially to replace the crowd proxy with something grounded.

Research and report on data sources in these areas, **most important first**:

**1. Crowding / busyness / occupancy (highest priority).** How busy is a given lake/beach right now and on a given future day/hour? Investigate, concretely:
   - Google "Popular Times" / Places "busyness" — is there any *official*, ToS-compliant API access? What exactly does Google Places API expose vs. not? What do third parties (BestTime.app, SerpApi, Outscraper, PopularTimes libraries) offer, at what price, and are they ToS-legal and durable?
   - Foot-traffic / mobility data vendors: Placer.ai, SafeGraph/Advan, Unacast, Veraset — coverage of parks/beaches, access model, cost, any free/academic tier.
   - Park-specific signals: King County Parks and Washington State Parks day-use/visitation stats; Recreation.gov / RIDB reservation data; any live parking-lot occupancy (ParkMobile, SpotHero, municipal sensors).
   - Proxy signals I could compute myself: King County Metro GTFS / transit proximity; Strava Metro or Strava heatmap; AllTrails popularity; WSDOT or park **webcams** usable for computer-vision headcounts (list actual camera URLs near these lakes if any).

**2. Water temperature** (upgrade from a weekly county sample to something fresher): USGS NWIS gauges on/near these specific lakes; NOAA; any real-time lake buoys (King County lake buoy pages); and **satellite lake-surface-temperature** products (Landsat/MODIS LST, USGS/Global Lake Temperature datasets) — resolution, latency, and whether these small lakes are actually resolvable.

**3. Cyanobacteria / toxic algae** beyond King County's beach feed: EPA CyAN (Cyanobacteria Assessment Network) satellite data, NOAA HAB products, WA Dept. of Ecology freshwater algae / toxin monitoring, King County toxin lab data — API/download availability and whether these lakes are covered.

**4. Bacteria / water quality, statewide fallback:** WA Dept. of Health BEACH program, EPA "How's My Waterway" / ATTAINS, Water Quality Portal — for lakes outside King County's program.

**5. Smoke / air quality cross-check:** AirNow API, PurpleAir API — vs. the Open-Meteo AQI I already use.

**6. Anything else genuinely useful and free:** UV index, lake water level / gage height (USGS), harmful-conditions or drowning-risk advisories, boating/wake activity.

**For every source you find, give me a row with:**
- Name + what metric it covers + which of my 11 lakes it actually covers
- Access method: REST/GeoJSON/CSV/scrape, and the **exact endpoint or URL** if one exists
- Auth: none / free key / paid — and **price** if paid
- **License / Terms of Service** — is programmatic access or scraping allowed? Flag anything that forbids it (esp. Google).
- Update cadence (real-time / hourly / daily / weekly) and typical latency
- Reliability & longevity (official gov feed vs. fragile scrape vs. discontinued)
- A concrete **example**: one real data point pulled for one of these lakes, with the request that got it

**Deliverables:**
1. A ranked recommendation table across all sources.
2. A short "**best path for crowding**" section: given it's a free personal app, what's the most realistic way to get real busyness data — and if the honest answer is "no good free source exists," say so plainly and rank the least-bad proxies.
3. A "**do not use**" list: sources that look promising but fail on ToS, cost, coverage, or reliability — with the reason.

Be skeptical and specific. Prefer official/government feeds. Verify endpoints resolve rather than assuming. Call out where I'd be violating a ToS.
