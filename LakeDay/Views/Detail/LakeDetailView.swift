import SwiftUI

/// Full lake read-out: verdict → buoy gauge → component breakdown → 7-day
/// strip → beaches → hazards → activities. The gauge is the one animated
/// moment (sweep-in on appear).
struct LakeDetailView: View {
    let state: LakeUIState

    private var lake: Lake { state.lake }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                verdictHero
                gaugeBlock
                if let score = state.score, !score.isClosed {
                    section("What's driving it") {
                        ComponentBars(score: score)
                    }
                }
                if !state.dayScores.isEmpty {
                    section("Next 7 days") {
                        DayStrip(days: state.dayScores, bestDay: state.bestDay)
                    }
                }
                beachesSection
                // Always shown — an empty list renders "No recent news" so the
                // feature reads as working, not broken, on a quiet lake.
                section("News & alerts") {
                    NewsSection(items: state.news)
                }
                if !lake.hazards.isEmpty {
                    section("Good to know") { hazards }
                }
                if !lake.activities.isEmpty {
                    section("Activities") { activities }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationTitle(lake.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Verdict + gauge

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verdictText)
                .font(.verdictHeadline)
                .foregroundStyle(Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                SafetyPill(level: state.lakeSafety.level)
                Text(lake.region)
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }

            if let note = dataNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }

            // Smoke note sits with the verdict when air quality is unhealthy
            // (AQI ≥ 101). Caution-colored; text carries the meaning too.
            if let smoke = state.smokeNote {
                Text(smoke)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.safetyCaution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verdictText: String {
        if let verdict = state.score?.verdict { return verdict }
        if let error = state.loadError { return error }
        return "No forecast yet — pull to refresh."
    }

    private var dataNote: String? {
        if state.loadError != nil, state.score != nil { return state.loadError }
        if let age = state.staleFallbackAge, age > 3600 {
            return "Showing older data from \(Staleness.ago(Date().addingTimeInterval(-age)))."
        }
        return nil
    }

    private var gaugeBlock: some View {
        VStack(spacing: 10) {
            BuoyGauge(score: state.score?.total,
                      waterTempF: state.waterTemp?.fahrenheit,
                      isClosed: state.lakeSafety.level == .closed,
                      style: .full,
                      animateOnAppear: true)

            if let water = state.waterTemp {
                Text("Water \(Staleness.sampled(water.sampledAt))")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            } else {
                Text("No water reading this week")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }

            if let crowd = state.crowd {
                Text(crowdLine(crowd))
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }

            if let air = state.airQuality {
                aqiRow(air)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Reading-style AQI row: "air quality  36  Good". Numeral in the caution
    // hue when smoky, so the state reads without relying on color alone.
    private func aqiRow(_ air: AirQualityReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("air quality")
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)
            Text("\(air.usAQI)")
                .font(.readingNumeralMedium)
                .foregroundStyle(air.isSmoky ? Color.safetyCaution : Color.primaryText)
            Text(air.category)
                .font(.footnote)
                .foregroundStyle(Color.secondaryText)
        }
    }

    private func crowdLine(_ crowd: CrowdEstimate) -> String {
        var line = "Crowds: \(crowd.level.label.lowercased()) — \(crowd.label)"
        if let eta = crowd.etaMinutes {
            line += " · ~\(eta) min drive"
        }
        return line
    }

    // MARK: Sections

    private var beachesSection: some View {
        section("Beaches") {
            VStack(spacing: 0) {
                ForEach(Array(state.beaches.enumerated()), id: \.element.id) { index, beach in
                    BeachRow(beachSafety: beach)
                    if index < state.beaches.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var hazards: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lake.hazards, id: \.self) { hazard in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.safetyCaution)
                        .imageScale(.small)
                    Text(hazard)
                        .font(.subheadline)
                        .foregroundStyle(Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var activities: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lake.activities, id: \.self) { activity in
                    Text(activity)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primaryText)   // ink on the pastel bubble — never tint-on-tint
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.shallows))
                }
            }
        }
    }

    // MARK: Section container

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Color.primaryText)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.cardSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
        }
    }
}

#Preview("Detail — open") {
    NavigationStack {
        LakeDetailView(state: MockPreviewBuilder.state(id: "lake-washington"))
    }
}

#Preview("Detail — caution") {
    NavigationStack {
        LakeDetailView(state: MockPreviewBuilder.state(id: "lake-sammamish"))
    }
}

#Preview("Detail — closed algae") {
    NavigationStack {
        LakeDetailView(state: MockPreviewBuilder.state(id: "green-lake"))
    }
}

#Preview("Detail — unknown, dark") {
    NavigationStack {
        LakeDetailView(state: MockPreviewBuilder.state(id: "angle-lake"))
    }
    .preferredColorScheme(.dark)
}
