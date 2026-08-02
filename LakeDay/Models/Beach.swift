import Foundation
import CoreLocation

/// A monitored beach on a lake. `locator` is the King County site code (e.g.
/// `0852SB`) and the exact join key against the beach feed; parsers match it
/// case-insensitively and log misses.
struct Beach: Codable, Identifiable, Hashable {
    let name: String
    let lat: Double
    let lon: Double
    /// County `locator` code — the stable, exact feed join key (DATA-FEEDS §4).
    /// Replaces the earlier name-based `kcSiteName`.
    let locator: String

    var id: String { locator }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
