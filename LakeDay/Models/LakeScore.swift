import Foundation

/// The four things that make (or break) a lake day. Order here is display
/// order in the component bars.
enum ComponentKind: String, Codable, Hashable, CaseIterable {
    case sunAir
    case water
    case crowds
    case wind

    var displayName: String {
        switch self {
        case .sunAir: return "Sun + air"
        case .water:  return "Water"
        case .crowds: return "Crowds"
        case .wind:   return "Wind"
        }
    }
}

/// One scored dimension. `normalized` is 0–1, or nil when the input was
/// missing (e.g. no water reading) — in that case the component is excluded
/// from the total and the remaining weights are renormalized.
struct ScoreComponent: Codable, Hashable, Identifiable {
    let kind: ComponentKind
    let normalized: Double?
    /// Effective weight after any renormalization for missing components.
    let weight: Double
    /// `normalized * weight` (0–1 scale). Zero when the component is missing.
    let weightedContribution: Double

    var id: String { kind.rawValue }
    var isAvailable: Bool { normalized != nil }
}

/// Result of the RatingEngine. `total` is nil when the water is unsafe
/// (closed) — the UI then draws a slashed gray gauge with no number.
struct LakeScore: Codable, Hashable {
    /// 0–100, or nil when closed / unsafe.
    let total: Int?
    let sunAir: ScoreComponent
    let water: ScoreComponent
    let crowds: ScoreComponent
    let wind: ScoreComponent
    /// One-sentence plain-language call, per DESIGN.md copy rules.
    let verdict: String
    let isClosed: Bool
    let closureReason: String?

    var components: [ScoreComponent] { [sunAir, water, crowds, wind] }
}
