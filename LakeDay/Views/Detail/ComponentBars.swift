import SwiftUI

/// The score broken into its four drivers. Each bar fills by the component's
/// 0–1 normalized value; a missing component (no water reading) reads "no
/// reading" rather than an empty bar.
struct ComponentBars: View {
    let score: LakeScore

    var body: some View {
        VStack(spacing: 12) {
            ForEach(score.components) { component in
                ComponentBarRow(component: component)
            }
        }
    }
}

private struct ComponentBarRow: View {
    let component: ScoreComponent

    private var fillColor: Color {
        // Warm the bar toward `sunDeck` as the component gets better.
        guard let n = component.normalized else { return Color.secondaryText }
        return n >= 0.66 ? .sunDeck : .coldWater
    }

    private var valueText: String {
        guard let n = component.normalized else { return "—" }
        return "\(Int((n * 100).rounded()))"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(component.kind.displayName)
                .font(.subheadline)
                .foregroundStyle(Color.primaryText)
                .frame(minWidth: 76, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gaugeTrack)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(0, geo.size.width * (component.normalized ?? 0)))
                }
            }
            .frame(height: 8)

            Text(valueText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.secondaryText)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.kind.displayName): \(component.isAvailable ? valueText + " out of 100" : "no reading")")
    }
}

#Preview("Component bars", traits: .sizeThatFitsLayout) {
    ComponentBars(score: MockPreviewBuilder.requireScore(id: "lake-washington"))
        .padding()
        .background(Color.appBackground)
}

#Preview("Component bars — missing water", traits: .sizeThatFitsLayout) {
    ComponentBars(score: MockPreviewBuilder.requireScore(id: "angle-lake"))
        .padding()
        .background(Color.appBackground)
}
