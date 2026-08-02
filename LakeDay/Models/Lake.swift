import Foundation
import CoreLocation

/// A curated lake from the bundled `lakes.json`. Codable because it is
/// decoded straight from the bundle; the feed layer never mutates it.
struct Lake: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let region: String
    let beaches: [Beach]
    let hazards: [String]
    let activities: [String]
    /// USGS NWIS site id — reserved for future water-temp enrichment (nil for v1 lakes).
    let usgsSiteId: String?
    /// King County lake-buoy id — reserved for future depth-profile enrichment.
    let kcBuoyId: String?
    /// Hand-set baseline popularity 0–1 (fame + accessibility): Green Lake ≈ 1,
    /// a remote lake ≈ 0.35. Differentiates the crowd *estimate* per lake — no
    /// free real busyness feed exists (verified), so a curated weight beats a
    /// uniform baseline. Never a safety input. Optional so older JSON still decodes.
    let popularity: Double?

    /// Popularity clamped to 0–1 with a neutral default when unset.
    var popularityWeight: Double { min(1, max(0, popularity ?? 0.6)) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }
}

// MARK: - User-added lakes (from search)

extension Lake {
    /// Marks a lake the user added via search, distinguishing it from the
    /// bundled curated set (which can't be removed).
    static let userAddedPrefix = "usr"

    /// Deterministic id from rounded coordinates, so re-adding the same lake
    /// dedupes against the existing entry.
    static func userAddedID(lat: Double, lon: Double) -> String {
        String(format: "\(userAddedPrefix)-%.4f-%.4f", lat, lon)
    }

    var isUserAdded: Bool { id.hasPrefix("\(Self.userAddedPrefix)-") }
}
