import SwiftUI

/// One lake, glanceable. Anatomy per DESIGN.md:
///   name + mini buoy gauge / safety pill · water temp · drive time / activities
struct LakeCard: View {
    let state: LakeUIState

    private var lake: Lake { state.lake }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                nameRow

                metaLine

                if !lake.activities.isEmpty {
                    Text(lake.activities.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            BuoyGauge(score: state.score?.total,
                      waterTempF: state.waterTemp?.fahrenheit,
                      isClosed: state.lakeSafety.level == .closed,
                      style: .mini)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    // Name + straight-line distance, kept on one line. Distance holds its width
    // (layoutPriority) so a long lake name scales down before the distance clips.
    private var nameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(lake.name)
                .font(.lakeName)
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let meters = state.distanceMeters {
                Spacer(minLength: 4)
                Text(Distance.short(meters: meters))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondaryText)
                    .layoutPriority(1)
            }
        }
    }

    // Safety pill · water temp · drive time — wraps to a second line rather than
    // overflowing (drive-time strings were pushing the row off the card).
    private var metaLine: some View {
        FlowLayout(hSpacing: 8, vSpacing: 4) {
            SafetyPill(level: state.lakeSafety.level)

            if let temp = state.waterTemp {
                metaChip("water \(Int(temp.fahrenheit.rounded()))°")
            } else {
                metaChip("no water reading")
            }

            if let eta = state.etaMinutes {
                metaChip("~\(eta) min drive")
            }
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
    }
}

#Preview("Lake cards", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        ForEach(MockPreviewBuilder.states()) { state in
            LakeCard(state: state)
        }
    }
    .padding()
    .background(Color.appBackground)
}

#Preview("Lake cards — dark", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        ForEach(MockPreviewBuilder.states()) { state in
            LakeCard(state: state)
        }
    }
    .padding()
    .background(Color.appBackground)
    .environment(\.colorScheme, .dark)
}
