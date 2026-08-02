import Foundation
import MapKit

/// A lake found via MapKit local search — enough to add it to the list and
/// score it from its coordinate (weather / air / traffic / crowd).
struct LakeSearchResult: Identifiable, Hashable, Sendable {
    let name: String
    let locality: String?
    let lat: Double
    let lon: Double

    /// Deterministic id from rounded coordinates, so re-adding the same lake
    /// dedupes against the existing entry.
    var id: String { Lake.userAddedID(lat: lat, lon: lon) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Build a `Lake` with no beaches: outside King County there is no
    /// beach-safety feed, so water safety shows "unknown" — but the
    /// coordinate-based feeds (weather, air, traffic, crowd) still score it.
    func asLake() -> Lake {
        Lake(id: id, name: name, lat: lat, lon: lon,
             region: locality ?? "Washington",
             beaches: [], hazards: [], activities: [],
             usgsSiteId: nil, kcBuoyId: nil, popularity: nil)
    }
}

/// Wraps `MKLocalSearch` for two flows: free-text search (a lake name or a
/// place) and "lakes near you" around a coordinate. Results are filtered to
/// water bodies and de-duplicated by coordinate.
@MainActor
struct LakeSearchService {

    /// Rough bounding region for Washington, used when we have no user location.
    private var washington: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.4, longitude: -120.5),
                           latitudinalMeters: 500_000, longitudinalMeters: 500_000)
    }

    /// Search by lake name or place. Appends "lake" when the query doesn't
    /// already mention it, and biases the region toward the user when known.
    func search(query: String, near coord: CLLocationCoordinate2D?) async -> [LakeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed.range(of: "lake", options: .caseInsensitive) == nil
            ? "\(trimmed) lake" : trimmed
        request.resultTypes = .pointOfInterest
        request.region = coord.map {
            MKCoordinateRegion(center: $0, latitudinalMeters: 250_000, longitudinalMeters: 250_000)
        } ?? washington
        return await run(request)
    }

    /// Lakes within ~60 km of a coordinate.
    func nearby(_ coord: CLLocationCoordinate2D) async -> [LakeSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "lake"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: coord,
                                            latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        return await run(request)
    }

    // MARK: -

    private func run(_ request: MKLocalSearch.Request) async -> [LakeSearchResult] {
        let response = try? await MKLocalSearch(request: request).start()
        let items = response?.mapItems ?? []
        var seen = Set<String>()
        var out: [LakeSearchResult] = []
        for item in items {
            guard let loc = item.placemark.location else { continue }
            let name = item.name ?? item.placemark.name ?? "Lake"
            // Keep water bodies only — a "lake" query also pulls in parks/roads.
            guard looksLikeWater(name) else { continue }
            let result = LakeSearchResult(
                name: name,
                locality: item.placemark.locality ?? item.placemark.administrativeArea,
                lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
            if seen.insert(result.id).inserted { out.append(result) }
        }
        return out
    }

    private func looksLikeWater(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["lake", "pond", "reservoir", "lagoon", "slough"].contains { n.contains($0) }
    }
}
