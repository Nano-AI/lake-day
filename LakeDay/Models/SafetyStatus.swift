import Foundation

/// Advisory state for a beach or lake. Conventional safety semantics on
/// purpose (DESIGN.md): green/amber/red/gray, and we NEVER fake green — a
/// missing feed degrades to `.unknown`, not `.open`.
enum SafetyLevel: String, Codable, CaseIterable, Hashable {
    case open
    case caution
    case closed
    case unknown

    /// Short label used on the safety pill. Color alone is never enough
    /// (color-blind floor), so the pill always shows this text too.
    var label: String {
        switch self {
        case .open:    return "Open"
        case .caution: return "Caution"
        case .closed:  return "Closed"
        case .unknown: return "No data"
        }
    }
}

/// A safety reading with its provenance. `sampledAt` drives the always-visible
/// staleness copy ("sampled Tue"); `reason` explains a caution/closure.
struct SafetyStatus: Codable, Hashable {
    let level: SafetyLevel
    let reason: String?
    let sampledAt: Date?

    init(level: SafetyLevel, reason: String? = nil, sampledAt: Date? = nil) {
        self.level = level
        self.reason = reason
        self.sampledAt = sampledAt
    }

    /// No-data sentinel. Used whenever a feed fails or has no sample yet.
    static let unknown = SafetyStatus(level: .unknown, reason: nil, sampledAt: nil)
}
