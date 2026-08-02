#!/usr/bin/env python3
"""
Statewide toxic-algae snapshot scraper for Lake Day.

Why this exists: nwtoxicalgae.org (WA Dept of Ecology Freshwater Algae Program)
is the only statewide freshwater cyanotoxin source, but it's an ASP.NET WebForms
site behind F5 bot-defense — every scripted postback 302s to /error.html, so the
iOS app cannot scrape it directly. This job runs a REAL browser (Playwright /
Chromium), which solves the JS challenge, exports the statewide toxin data, and
writes a small JSON snapshot the app fetches over plain HTTPS.

Output schema (docs/algae-snapshot.json):
    {
      "generated": "2026-07-12T19:00:00Z",
      "source": "nwtoxicalgae.org",
      "advisories": [
        {"site": "...", "county": "...", "lat": null, "lon": null,
         "toxin": "Microcystin", "value": 12.4, "unit": "ug/L",
         "category": "danger", "date": "2026-07-05"}
      ]
    }

Run locally:   pip install -r requirements.txt && playwright install chromium
               python scrape.py --out ../../docs/algae-snapshot.json
Env: HEADLESS=0 to watch the browser (useful if F5 flags a headless/datacenter IP).
"""
import argparse, csv, datetime, io, json, os, re, sys

URL = "https://www.nwtoxicalgae.org/Data.aspx"
PFX = "#ctl00_ContentPlaceHolder1_"

# WA recreational guideline values (µg/L). At/above → closure-worthy ("danger");
# a detection below → "caution". Source: WA DOH recreational guidance.
GUIDELINES = {
    "microcystin": 8.0,
    "anatoxin": 1.0,
    "cylindrospermopsin": 15.0,
    "saxitoxin": 75.0,
}


def find_col(headers, *candidates):
    norm = [re.sub(r"[^a-z0-9]", "", h.lower()) for h in headers]
    for cand in candidates:
        c = re.sub(r"[^a-z0-9]", "", cand.lower())
        for i, h in enumerate(norm):
            if c and (c == h or c in h):
                return i
    return None


def parse_value(raw):
    """Return (float_value_or_None, is_detection). 'ND'/'' → non-detect."""
    if raw is None:
        return None, False
    s = raw.strip()
    if s == "" or s.upper() in ("ND", "NONE", "N/A", "NA", "NON-DETECT"):
        return None, False
    below = s.startswith("<")
    m = re.search(r"[-+]?\d*\.?\d+", s.replace(",", ""))
    if not m:
        return None, False
    v = float(m.group())
    return (0.0 if below else v), True


def category_for(toxin, value):
    """danger if at/above the toxin's guideline, else caution (any detection)."""
    key = next((k for k in GUIDELINES if k in (toxin or "").lower()), None)
    if key and value is not None and value >= GUIDELINES[key]:
        return "danger"
    return "caution"


def parse_date(raw):
    if not raw:
        return None
    s = raw.strip().split(" ")[0]
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%m-%d-%Y"):
        try:
            return datetime.datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def rows_to_advisories(text):
    reader = csv.reader(io.StringIO(text))
    rows = [r for r in reader if any(c.strip() for c in r)]
    if not rows:
        print("WARN: export returned no rows", file=sys.stderr)
        return []
    headers = rows[0]
    print("Detected columns:", headers, file=sys.stderr)
    ci = {
        "site": find_col(headers, "site name", "sitename", "site", "water body", "waterbody", "lake", "name"),
        "county": find_col(headers, "county"),
        "date": find_col(headers, "sample date", "collection date", "sampledate", "date"),
        "toxin": find_col(headers, "toxin", "analyte", "parameter"),
        "value": find_col(headers, "result value", "concentration", "result", "value"),
        "unit": find_col(headers, "unit", "units"),
        "lat": find_col(headers, "latitude", "lat"),
        "lon": find_col(headers, "longitude", "long", "lon"),
    }
    if ci["site"] is None or ci["toxin"] is None or ci["value"] is None:
        print("ERROR: could not locate site/toxin/value columns — headers were:", headers, file=sys.stderr)

    def get(row, key):
        i = ci[key]
        return row[i] if i is not None and i < len(row) else None

    def num(row, key):
        raw = get(row, key)
        try:
            return float(raw)
        except (TypeError, ValueError):
            return None

    # Keep the most recent, highest-severity detection per (site, toxin).
    best = {}
    for row in rows[1:]:
        value, detected = parse_value(get(row, "value"))
        if not detected:
            continue
        toxin = (get(row, "toxin") or "").strip()
        site = (get(row, "site") or "").strip()
        if not site:
            continue
        adv = {
            "site": site,
            "county": (get(row, "county") or "").strip() or None,
            "lat": num(row, "lat"),
            "lon": num(row, "lon"),
            "toxin": toxin or None,
            "value": value,
            "unit": (get(row, "unit") or "").strip() or "ug/L",
            "category": category_for(toxin, value),
            "date": parse_date(get(row, "date")),
        }
        k = (re.sub(r"[^a-z0-9]", "", site.lower()), toxin.lower())
        prev = best.get(k)
        rank = {"danger": 2, "caution": 1}
        if prev is None or (adv["date"] or "") > (prev["date"] or "") \
                or rank[adv["category"]] > rank[prev["category"]]:
            best[k] = adv
    return list(best.values())


def scrape(days, headless):
    from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

    end = datetime.date.today()
    start = end - datetime.timedelta(days=days)
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"],
        )
        ctx = browser.new_context(
            user_agent=("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
            accept_downloads=True,
        )
        page = ctx.new_page()
        page.goto(URL, wait_until="networkidle", timeout=60_000)
        # F5 challenge sometimes reloads once; give it a beat then re-check.
        page.wait_for_timeout(1_500)
        if "error" in page.url.lower():
            raise RuntimeError("Blocked by bot-defense even in a real browser (page → error).")

        page.fill(PFX + "c_StartDateTextBox", start.strftime("%m/%d/%Y"))
        page.fill(PFX + "c_EndDateTextBox", end.strftime("%m/%d/%Y"))

        try:
            with page.expect_download(timeout=45_000) as dl:
                page.click(PFX + "c_ExportToxinButton")
            path = dl.value.path()
            with open(path, "rb") as fh:
                data = fh.read()
        except PWTimeout:
            raise RuntimeError("Export click produced no download — the button id or "
                               "flow changed; run with HEADLESS=0 to inspect.")
        finally:
            browser.close()
    return data.decode("utf-8-sig", "replace"), start, end


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/algae-snapshot.json")
    ap.add_argument("--days", type=int, default=60, help="lookback window")
    args = ap.parse_args()

    headless = os.environ.get("HEADLESS", "1") != "0"
    text, start, end = scrape(args.days, headless)
    advisories = rows_to_advisories(text)

    snapshot = {
        "generated": datetime.datetime.now(datetime.timezone.utc)
            .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "nwtoxicalgae.org",
        "window": {"start": start.isoformat(), "end": end.isoformat()},
        "advisories": advisories,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as fh:
        json.dump(snapshot, fh, indent=2)
    print(f"Wrote {len(advisories)} advisories → {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
