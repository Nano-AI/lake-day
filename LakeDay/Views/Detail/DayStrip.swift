import SwiftUI

/// Seven-day outlook. Each column: weekday, a bar sized by that day's score,
/// the score, and the day's high. The best day is highlighted in `sunDeck`.
struct DayStrip: View {
    let days: [DayScore]
    let bestDay: Date?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    DayColumn(day: day, isBest: isBest(day))
                }
            }
        }
    }

    private func isBest(_ day: DayScore) -> Bool {
        guard let bestDay else { return false }
        return calendar.isDate(day.date, inSameDayAs: bestDay)
    }
}

private struct DayColumn: View {
    let day: DayScore
    let isBest: Bool

    private let maxBarHeight: CGFloat = 64

    private var barHeight: CGFloat {
        guard let total = day.total else { return 4 }
        return max(6, maxBarHeight * CGFloat(total) / 100)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(day.total.map { "\($0)" } ?? "–")
                .font(.readingNumeralSmall)
                .foregroundStyle(isBest ? Color.lakeInk : Color.primaryText)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.gaugeTrack.opacity(0.5))
                    .frame(width: 10, height: maxBarHeight)
                Capsule()
                    .fill(isBest ? Color.sunDeck : Color.coldWater)
                    .frame(width: 10, height: barHeight)
            }

            Text("\(Int(day.forecast.highF.rounded()))°")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.secondaryText)

            Text(Staleness.shortWeekday(day.date))
                .font(.caption2)
                .foregroundStyle(isBest ? Color.primaryText : Color.secondaryText)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isBest ? Color(hex: Palette.green) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "\(Staleness.shortWeekday(day.date)), high \(Int(day.forecast.highF.rounded())) degrees"
        let scorePart = day.total.map { ", score \($0)" } ?? ", no score"
        return base + scorePart + (isBest ? ", best day" : "")
    }
}

#Preview("Day strip", traits: .sizeThatFitsLayout) {
    DayStrip(days: MockPreviewBuilder.state(id: "lake-washington").dayScores,
             bestDay: MockPreviewBuilder.state(id: "lake-washington").bestDay)
        .padding()
        .background(Color.appBackground)
}
