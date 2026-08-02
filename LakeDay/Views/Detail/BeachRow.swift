import SwiftUI

/// One beach in the detail list: name, its advisory, and when it was sampled.
/// Empty state is an invitation, not an apology (DESIGN.md copy rules).
struct BeachRow: View {
    let beachSafety: BeachSafety

    private var status: SafetyStatus { beachSafety.status }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(beachSafety.beach.name)
                    .font(.body)
                    .foregroundStyle(Color.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 8)
            SafetyPill(level: status.level)
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        if let sampledAt = status.sampledAt {
            var text = Staleness.sampled(sampledAt)
            if let reason = status.reason, status.level != .open {
                text += " · \(reason)"
            }
            return text
        }
        if status.level == .unknown {
            return "No sampling this season yet — first samples usually mid-June."
        }
        return status.reason ?? "No sample time on record."
    }
}

#Preview("Beach rows", traits: .sizeThatFitsLayout) {
    VStack(spacing: 0) {
        ForEach(MockPreviewBuilder.state(id: "lake-washington").beaches) { bs in
            BeachRow(beachSafety: bs)
        }
    }
    .padding()
    .background(Color.appBackground)
}
