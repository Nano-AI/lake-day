import SwiftUI

/// Safety state as text + symbol + color — never color alone (color-blind
/// floor, DESIGN.md). Used on cards and the detail header.
struct SafetyPill: View {
    let level: SafetyLevel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbolName)
                .imageScale(.small)
            Text(level.label)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(level.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(level.tint.opacity(0.14))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safety: \(level.label)")
    }
}

#Preview("Safety pills", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 10) {
        SafetyPill(level: .open)
        SafetyPill(level: .caution)
        SafetyPill(level: .closed)
        SafetyPill(level: .unknown)
    }
    .padding()
    .background(Color.appBackground)
}
