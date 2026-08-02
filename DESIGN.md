# Lake Day — Design Direction

Personal SwiftUI iOS app. One job: **which lake, which day.** Summer PNW outdoor vibe, glanceable safety.

## Grounding

Visual language borrowed from the instruments that produce the data: monitoring buoys, county advisory signboards, dive-watch readouts. Not generic iOS-blue cards.

## Palette

Based on **Pastel Nature** (SchemeColor): all 6 pale tones are used —
cream `#F2EDDC`, turquoise `#D3EBE9`, paper-blue `#BAD0DE`, Tasman green
`#CADECD`, light-neutral green `#DDE6CF`, neutral gray `#EEEEEE`. The scheme is
all-pale, so the load-bearing colors — `lakeInk` (text), `coldWater` (accent),
`sunDeck` (highlight) — are **derived** as deep members of the same hue family;
a pale ground can't carry text. **Rule: pastels are fills only; every text or
icon uses a dark token.** That is the structural cure for washed-out labels
(e.g. activity chips are ink-on-turquoise, never tint-on-tint).

| Token | Hex | Role |
|---|---|---|
| `lakeInk` | `#26424A` | primary text, dark-mode base (derived deep slate-teal) |
| `coldWater` | `#3A7082` | derived teal — nav tint, links, score (legible as text, 4.7:1 on cream) |
| `shallows` | `#D3EBE9` | pastel turquoise — fills, chips, card tint |
| `sunDeck` | `#5FA07B` | derived sage-green highlight — sun, score, "best day" (was honey) |
| `mist` | `#F2EDDC` | cream (Virgin Lace) — light-mode background |

Supporting pastels from the scheme fill surfaces: paper-blue `#BAD0DE`
(gauge track), neutral gray `#EEEEEE` (cards lift off cream), Tasman green
`#CADECD` (hairlines), light-neutral green `#DDE6CF` ("best day" cell fill).

Safety states are **conventional on purpose** (safety semantics beat style).
Harmonized toward the pastels but kept dark enough to read as small text (they
double as hazard icons and the smoky-air label); shape symbols carry the
color-blind floor:

| State | Hex | Meaning |
|---|---|---|
| open | `#3F7D61` | no advisory, recent sample OK |
| caution | `#A9742E` | advisory, stale sample (>10 days in season), or algae watch |
| closed | `#B15140` | active closure or toxic-algae advisory (soft terracotta) |
| unknown | `#74858A` | no data — never fake green |

Dark mode: surfaces from `lakeInk`, keeping the soft light-mode fills; safety
hues stay dark enough to read on both schemes (shape cue backs up the color).

## Typography (native, no bundled fonts)

- **Display:** SF Pro Rounded, Bold — lake names, verdict headline. Buoy-signage friendliness.
- **Body:** SF Pro Text, regular/medium — everything else.
- **Readings:** rounded + `.monospacedDigit()` — water temp, scores, wind. Dive-watch feel; numerals never jitter as data updates.

Scale: verdict headline 28pt rounded bold; lake card name 20pt rounded semibold; reading numerals 34pt rounded bold monospaced-digit; captions 13pt.

## Signature element: the Buoy Gauge

Circular lake-day score dial (0–100) banded like a mooring buoy — arc segments in `sunDeck` over a `shallows` track, `lakeInk` cap — with the water-temp numeral at center and score below. Mini version (no numeral) on list cards; full version on detail. This is the ONE bold element; everything around it stays quiet. When safety = closed, the gauge renders slate-gray with a slash — no score shown for unsafe water.

## Layout

**Lake list (home):** map header (collapsible, MapKit, pins colored by safety) over scrolling cards.

Card anatomy:
```
┌───────────────────────────────────────┐
│ Lake Sammamish            ◔ 78        │  name + mini buoy gauge
│ ● Open · water 68° · ~25 min drive    │  safety pill · temp · ETA
│ swim · paddle · beach                 │  activities, quiet caption
└───────────────────────────────────────┘
```

**Lake detail:** verdict sentence hero → full buoy gauge with component breakdown (sun+air / water / crowds / wind bars) → 7-day strip (best day highlighted `sunDeck`) → beaches list (bacteria status + "sampled Tue") → hazards → activities.

Verdict examples: "Saturday looks like a lake day — 82° air, 68° water." / "Skip it — algae advisory since Jul 2."

## Copy rules

- Plain verbs, sentence case. "Check again" not "Retry operation".
- Staleness always visible: "sampled Tue", "buoy reading 3h ago". Never hide data age.
- Crowd proxy always labeled "estimate".
- Errors: what broke + what to do. "Couldn't reach King County data. Showing Tuesday's samples."
- Empty/no-data: invitation, not apology. "No sampling this season yet — first samples usually mid-June."

## Motion & floor

One orchestrated moment: buoy gauge arc sweeps in on detail-view appear (spring, ~0.6s), respects Reduce Motion (crossfade instead). No scattered effects. Dynamic Type supported; safety pills also differ by label text, never color alone (color-blind floor).
