import Foundation
import CoreLocation

/// Thin async wrapper over `CLLocationManager` for when-in-use location. The
/// whole app stays functional when this returns nil (denied / disabled): the
/// list just sorts by rating and drops drive-time ETA.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager: CLLocationManager?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    /// `disabled` is used by previews so no permission prompt ever appears.
    init(disabled: Bool = false) {
        manager = disabled ? nil : CLLocationManager()
        super.init()
        manager?.delegate = self
        manager?.desiredAccuracy = kCLLocationAccuracyKilometer   // plenty for sorting
    }

    /// Best-effort current coordinate. Requests when-in-use authorization the
    /// first time; returns nil if denied, disabled, or timed out.
    func currentCoordinate() async -> (lat: Double, lon: Double)? {
        guard let manager else { return nil }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization(manager)
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        guard let coord = await requestOneLocation(manager) else { return nil }
        return (coord.latitude, coord.longitude)
    }

    // MARK: Continuation-bridged requests

    private func requestAuthorization(_ manager: CLLocationManager) async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
            // Safety net: don't hang the launch fan-out if no callback arrives.
            // Route through self (Sendable) rather than capturing the manager.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                self.authTimedOut()
            }
        }
    }

    private func authTimedOut() {
        resumeAuth(manager?.authorizationStatus ?? .notDetermined)
    }

    private func requestOneLocation(_ manager: CLLocationManager) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.resumeLocation(lat: nil, lon: nil)
            }
        }
    }

    // Resumers guard on the continuation being non-nil, so a timeout that fires
    // after a real callback (or vice-versa) is a harmless no-op.
    private func resumeAuth(_ status: CLAuthorizationStatus) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(returning: status)
    }

    private func resumeLocation(lat: Double?, lon: Double?) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        let coord: CLLocationCoordinate2D?
        if let lat, let lon {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            coord = nil
        }
        continuation.resume(returning: coord)
    }

    // MARK: CLLocationManagerDelegate
    //
    // Callbacks arrive off the main-actor boundary; extract primitives, then
    // hop to the main actor to touch continuation state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.resumeAuth(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.first?.coordinate
        let lat = coord?.latitude
        let lon = coord?.longitude
        Task { @MainActor in self.resumeLocation(lat: lat, lon: lon) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resumeLocation(lat: nil, lon: nil) }
    }
}
