import Foundation

/// Pure scoring. No I/O, no dates-from-now, no globals — everything comes in
/// through `score(...)` so the whole thing is trivially unit-testable.
///
/// `(SafetyStatus, waterTempF?, DayForecast, CrowdEstimate) -> LakeScore`
///
/// Note on the return type: ARCHITECTURE.md sketches this as `-> LakeScore?`,
/// but we always return a `LakeScore` and express "unsafe / no score" as
/// `total == nil`. That keeps the verdict and component breakdown available
/// for the closed state (the UI still shows the slashed gauge + reason).
struct RatingEngine {

    // MARK: Tunable constants (one place — expect tuning after real weekends)

    struct Constants {
        // Nominal component weights. Sum to 1.0.
        static let sunAirWeight = 0.40
        static let waterWeight  = 0.25
        static let crowdsWeight = 0.20
        static let windWeight   = 0.15

        // Air-temp curve (°F): flat 1.0 across the peak, linear taper to 0 at
        // the outer edges.
        static let airPeakLow  = 80.0
        static let airPeakHigh = 88.0
        static let airFloor    = 68.0   // and below → 0
        static let airCeil     = 95.0   // and above → 0

        // Sun+air penalties: fraction of the daytime window under cloud / with
        // rain chance, scaled by these maxima and subtracted from the air score.
        static let cloudPenaltyMax  = 0.35
        static let precipPenaltyMax = 0.50

        // Wind (mph): calm → 1.0, taper to 0 at the ceiling.
        static let windCalm = 5.0
        static let windCeil = 18.0

        // Caution caps the total here and prepends the reason to the verdict.
        static let cautionCap = 60
    }

    // MARK: Entry point

    func score(safety: SafetyStatus,
               waterTempF: Double?,
               forecast: DayForecast,
               crowd: CrowdEstimate) -> LakeScore {

        // 1. Hard zero: closed water is never scored.
        if safety.level == .closed {
            return closedScore(safety: safety, forecast: forecast)
        }

        // 2. Normalize each component to 0–1.
        let sunAirNorm = sunAirScore(forecast: forecast)
        let waterNorm  = waterTempF.map(waterScore(_:))   // nil when no reading
        let crowdsNorm = crowdScore(crowd)
        let windNorm   = windScore(forecast.windMph)

        // 3. Renormalize weights over the *available* components. Water is the
        //    only one that can be missing; when it is, its 0.25 is redistributed
        //    proportionally across the other three so the total still spans 0–100.
        var available: [(ComponentKind, Double, Double)] = [
            (.sunAir, sunAirNorm, Constants.sunAirWeight),
            (.crowds, crowdsNorm, Constants.crowdsWeight),
            (.wind,   windNorm,   Constants.windWeight)
        ]
        if let waterNorm {
            available.append((.water, waterNorm, Constants.waterWeight))
        }
        let weightSum = available.reduce(0) { $0 + $1.2 }

        var total01 = 0.0
        var effective: [ComponentKind: (norm: Double, weight: Double, contrib: Double)] = [:]
        for (kind, norm, nominalWeight) in available {
            let w = weightSum > 0 ? nominalWeight / weightSum : 0
            let contrib = norm * w
            total01 += contrib
            effective[kind] = (norm, w, contrib)
        }

        var total = Int((total01 * 100).rounded())

        // 4. Caution caps the total.
        if safety.level == .caution {
            total = min(total, Constants.cautionCap)
        }
        total = max(0, min(100, total))

        let components = buildComponents(effective: effective)
        let verdict = makeVerdict(total: total,
                                  safety: safety,
                                  forecast: forecast,
                                  waterTempF: waterTempF,
                                  components: components)

        return LakeScore(total: total,
                         sunAir: components.sunAir,
                         water: components.water,
                         crowds: components.crowds,
                         wind: components.wind,
                         verdict: verdict,
                         isClosed: false,
                         closureReason: nil)
    }

    // MARK: Component curves (each returns 0–1)

    /// Air-temp comfort with cloud + precip penalties subtracted.
    func sunAirScore(forecast: DayForecast) -> Double {
        let air = airTempScore(forecast.highF)
        let cloudPenalty  = (forecast.cloudCoverPercent / 100.0) * Constants.cloudPenaltyMax
        let precipPenalty = (forecast.precipProbabilityPercent / 100.0) * Constants.precipPenaltyMax
        return clamp01(air - cloudPenalty - precipPenalty)
    }

    /// Flat across 80–88°F, linear ramp up from 68 and down to 95.
    func airTempScore(_ tempF: Double) -> Double {
        if tempF <= Constants.airFloor || tempF >= Constants.airCeil { return 0 }
        if tempF >= Constants.airPeakLow && tempF <= Constants.airPeakHigh { return 1 }
        if tempF < Constants.airPeakLow {
            return clamp01((tempF - Constants.airFloor) / (Constants.airPeakLow - Constants.airFloor))
        }
        // tempF > peakHigh
        return clamp01((Constants.airCeil - tempF) / (Constants.airCeil - Constants.airPeakHigh))
    }

    /// Water comfort. Boundaries match ARCHITECTURE.md and the unit tests:
    /// <60 → ≤0.2 (cold-shock), 60–65 → 0.2–0.5, 66–72 → 0.5–0.9, ≥73 → 1.0.
    func waterScore(_ t: Double) -> Double {
        switch t {
        case ..<50:      return 0.0
        case 50..<60:    return (t - 50) / 10 * 0.2      // 0.0 → 0.2
        case 60..<65:    return 0.2 + (t - 60) / 5 * 0.3 // 0.2 → 0.5
        case 65..<66:    return 0.5                       // bridges the two bands
        case 66..<72:    return 0.5 + (t - 66) / 6 * 0.4 // 0.5 → 0.9
        case 72..<73:    return 0.9 + (t - 72) * 0.1     // 0.9 → 1.0
        default:         return 1.0                       // ≥73
        }
    }

    /// Calm water = 1.0, taper to 0 at the ceiling.
    func windScore(_ mph: Double) -> Double {
        if mph <= Constants.windCalm { return 1 }
        if mph >= Constants.windCeil { return 0 }
        return clamp01(1 - (mph - Constants.windCalm) / (Constants.windCeil - Constants.windCalm))
    }

    /// Fewer people = better, so we invert the crowd proxy.
    func crowdScore(_ crowd: CrowdEstimate) -> Double {
        clamp01(1 - crowd.value)
    }

    // MARK: Assembly

    private func buildComponents(
        effective: [ComponentKind: (norm: Double, weight: Double, contrib: Double)]
    ) -> (sunAir: ScoreComponent, water: ScoreComponent, crowds: ScoreComponent, wind: ScoreComponent) {

        func component(_ kind: ComponentKind) -> ScoreComponent {
            if let e = effective[kind] {
                return ScoreComponent(kind: kind, normalized: e.norm, weight: e.weight, weightedContribution: e.contrib)
            }
            // Missing (water only): excluded, zero weight.
            return ScoreComponent(kind: kind, normalized: nil, weight: 0, weightedContribution: 0)
        }

        return (component(.sunAir), component(.water), component(.crowds), component(.wind))
    }

    private func closedScore(safety: SafetyStatus, forecast: DayForecast) -> LakeScore {
        let reason = safety.reason ?? "active closure"
        // "Skip it — algae advisory since Jul 2." style (DESIGN.md).
        let verdict = "Skip it — \(lowercasedReason(reason))."
        let empty = ComponentKind.allCases.reduce(into: [ComponentKind: ScoreComponent]()) {
            $0[$1] = ScoreComponent(kind: $1, normalized: nil, weight: 0, weightedContribution: 0)
        }
        return LakeScore(total: nil,
                         sunAir: empty[.sunAir]!,
                         water: empty[.water]!,
                         crowds: empty[.crowds]!,
                         wind: empty[.wind]!,
                         verdict: verdict,
                         isClosed: true,
                         closureReason: reason)
    }

    // MARK: Verdict copy (plain verbs, sentence case, dominant component leads)

    private func makeVerdict(total: Int,
                             safety: SafetyStatus,
                             forecast: DayForecast,
                             waterTempF: Double?,
                             components: (sunAir: ScoreComponent, water: ScoreComponent, crowds: ScoreComponent, wind: ScoreComponent)) -> String {

        let day = weekdayName(forecast.date)
        let air = Int(forecast.highF.rounded())
        let waterPhrase = waterTempF.map { "\(Int($0.rounded()))° water" } ?? "no water reading"

        // Caution: lead with the reason, then a tempered call.
        if safety.level == .caution {
            let reason = safety.reason ?? "advisory in effect"
            let tail: String
            if total >= 45 {
                tail = "\(day) could still work — \(air)° air, \(waterPhrase)."
            } else {
                tail = "not a great \(day)."
            }
            return "\(capitalizeFirst(reason)). \(tail)"
        }

        // Find the limiting (lowest-scoring available) component to drive tone.
        let limiter = [components.sunAir, components.water, components.crowds, components.wind]
            .filter { $0.isAvailable }
            .min(by: { ($0.normalized ?? 1) < ($1.normalized ?? 1) })

        switch total {
        case 80...100:
            return "\(day) looks like a lake day — \(air)° air, \(waterPhrase)."
        case 65..<80:
            return "\(day) works — \(air)° air, \(waterPhrase)."
        case 45..<65:
            // Name the limiter so the caption explains the middling score.
            if let limiter, limiter.kind == .water, let w = waterTempF, w < 66 {
                return "Swimmable but cool — \(Int(w.rounded()))° water, \(air)° air."
            }
            if let limiter, limiter.kind == .wind {
                return "Breezy — \(Int(forecast.windMph.rounded())) mph wind, \(air)° air."
            }
            return "Decent \(day) — \(air)° air, \(waterPhrase)."
        case 25..<45:
            if let w = waterTempF, w < 60 {
                return "Cold water — \(Int(w.rounded()))° — better for a walk than a swim."
            }
            return "Marginal — \(air)° air, \(waterPhrase)."
        default:
            return "Skip the swim — \(air)° air, \(waterPhrase)."
        }
    }

    // MARK: Small helpers

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    private func weekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func lowercasedReason(_ s: String) -> String {
        guard let first = s.first else { return s }
        // Keep it lower-case for the "Skip it — <reason>" inline form, but don't
        // lower-case an all-caps token (e.g. an acronym).
        if s == s.uppercased() && s.count > 1 { return s }
        return first.lowercased() + s.dropFirst()
    }

    private func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
