import SwiftUI

/// Upward-pointing triangle (apex at top-center). The gauge value marker.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The one bold element. A circular lake-day dial banded like a mooring buoy:
/// a `sunDeck` value arc over a `shallows` track, with a `lakeInk` cap, the
/// water-temp numeral at center and the score below. Mini (card) drops the
/// numerals; the full one sweeps its arc in on appear.
///
/// Unsafe water (closed) renders slate-gray with a slash and no number.
struct BuoyGauge: View {

    enum Style { case mini, full }

    let score: Int?
    let waterTempF: Double?
    let isClosed: Bool
    var style: Style = .full
    var animateOnAppear: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Double
    @State private var appeared: Bool

    init(score: Int?, waterTempF: Double?, isClosed: Bool,
         style: Style = .full, animateOnAppear: Bool = false) {
        self.score = score
        self.waterTempF = waterTempF
        self.isClosed = isClosed
        self.style = style
        self.animateOnAppear = animateOnAppear
        // Start collapsed only when we intend to animate; otherwise render full.
        _sweep = State(initialValue: animateOnAppear ? 0 : 1)
        _appeared = State(initialValue: animateOnAppear ? false : true)
    }

    private var diameter: CGFloat { style == .mini ? 46 : 176 }
    private var lineWidth: CGFloat { style == .mini ? 5 : 14 }
    private let arcFraction = 0.75            // 270° dial, gap at the bottom
    private let startDegrees = 135.0

    private var progress: Double {
        guard let score, !isClosed else { return 0 }
        return min(1, max(0, Double(score) / 100)) * sweep
    }

    var body: some View {
        ZStack {
            track
            if !isClosed { valueArc; cap }
            if isClosed { slash }
            center
        }
        .frame(width: diameter, height: diameter)
        .opacity(reduceMotion && animateOnAppear ? (appeared ? 1 : 0) : 1)
        .onAppear(perform: runAppearAnimation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Rings

    private var radius: CGFloat { (diameter - lineWidth) / 2 }

    private var dashStyle: StrokeStyle {
        // Banded look: split the 270° arc into ~14 segments (buoy stripes).
        let arcLength = 2 * .pi * radius * CGFloat(arcFraction)
        let bandCount: CGFloat = 14
        let gap: CGFloat = 3
        let on = max(2, arcLength / bandCount - gap)
        return StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: [on, gap])
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: CGFloat(arcFraction))
            .stroke(isClosed ? Color.safetyUnknown.opacity(0.5) : Color.gaugeTrack, style: dashStyle)
            .rotationEffect(.degrees(startDegrees))
    }

    private var valueArc: some View {
        Circle()
            .trim(from: 0, to: CGFloat(arcFraction * progress))
            .stroke(Color.sunDeck, style: dashStyle)
            .rotationEffect(.degrees(startDegrees))
    }

    /// `lakeInk` triangle marker at the leading end of the value arc, apex
    /// pointing outward along the radius (replaces the old round cap).
    private var cap: some View {
        let endDegrees = startDegrees + arcFraction * 360 * progress
        let radians = endDegrees * .pi / 180
        let x = CGFloat(cos(radians)) * radius
        let y = CGFloat(sin(radians)) * radius
        let markerSize = lineWidth + 6
        return Triangle()
            .fill(Color.lakeInk)
            .frame(width: markerSize, height: markerSize)
            .rotationEffect(.degrees(endDegrees + 90))
            .offset(x: x, y: y)
            .opacity(progress > 0.001 ? 1 : 0)
    }

    private var slash: some View {
        Capsule()
            .fill(Color.safetyClosed)
            .frame(width: diameter * 0.9, height: lineWidth * 0.7)
            .rotationEffect(.degrees(-45))
    }

    // MARK: Center content

    @ViewBuilder private var center: some View {
        if style == .mini {
            if isClosed {
                Image(systemName: "nosign")
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(Color.safetyClosed)
            } else if let score {
                Text("\(score)")
                    .font(.readingNumeralSmall)
                    .foregroundStyle(Color.primaryText)
            } else {
                Text("–")
                    .font(.readingNumeralSmall)
                    .foregroundStyle(Color.secondaryText)
            }
        } else {
            fullCenter
        }
    }

    @ViewBuilder private var fullCenter: some View {
        if isClosed {
            VStack(spacing: 4) {
                Image(systemName: "nosign")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.safetyClosed)
                Text("no score")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        } else {
            VStack(spacing: 2) {
                if let waterTempF {
                    Text("\(Int(waterTempF.rounded()))°")
                        .font(.readingNumeral)
                        .foregroundStyle(Color.primaryText)
                    Text("water")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                } else {
                    Text("–")
                        .font(.readingNumeral)
                        .foregroundStyle(Color.secondaryText)
                    Text("no reading")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                }
                HStack(spacing: 4) {
                    Text(score.map { "\($0)" } ?? "–")
                        .font(.readingNumeralMedium)
                        .foregroundStyle(Color.coldWater)
                    Text("score")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: Animation

    private func runAppearAnimation() {
        guard animateOnAppear else { return }
        if reduceMotion {
            // Crossfade instead of a sweep.
            sweep = 1
            withAnimation(.easeIn(duration: 0.4)) { appeared = true }
        } else {
            appeared = true
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { sweep = 1 }
        }
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        if isClosed { return "Lake day score unavailable, water closed." }
        let scorePart = score.map { "Lake day score \($0) out of 100." } ?? "No score yet."
        let waterPart = waterTempF.map { " Water \(Int($0.rounded())) degrees." } ?? " No water reading."
        return scorePart + waterPart
    }
}

#Preview("Buoy gauge — states", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        BuoyGauge(score: 82, waterTempF: 66, isClosed: false, style: .full, animateOnAppear: false)
        VStack(spacing: 20) {
            BuoyGauge(score: 78, waterTempF: 66, isClosed: false, style: .mini)
            BuoyGauge(score: nil, waterTempF: 74, isClosed: true, style: .mini)
        }
    }
    .padding()
    .background(Color.appBackground)
}

#Preview("Buoy gauge — closed", traits: .sizeThatFitsLayout) {
    BuoyGauge(score: nil, waterTempF: 74, isClosed: true, style: .full)
        .padding()
        .background(Color.appBackground)
}
