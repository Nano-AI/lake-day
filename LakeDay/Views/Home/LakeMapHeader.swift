import SwiftUI
import MapKit

/// Collapsible map header. Pins are colored by safety (green/amber/red/gray)
/// and carry the matching symbol, so state reads without relying on color.
struct LakeMapHeader: View {
    let states: [LakeUIState]
    @Binding var isExpanded: Bool

    var body: some View {
        Map(initialPosition: .region(Self.region(covering: states))) {
            ForEach(states) { state in
                Marker(state.lake.name,
                       systemImage: state.lakeSafety.level.symbolName,
                       coordinate: state.lake.coordinate)
                    .tint(state.lakeSafety.level.tint)
            }
        }
        .frame(height: isExpanded ? 260 : 116)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.bold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(8)
            .accessibilityLabel(isExpanded ? "Collapse map" : "Expand map")
        }
    }

    /// Bounding region over all lakes, with padding and a sensible minimum span.
    static func region(covering states: [LakeUIState]) -> MKCoordinateRegion {
        let coords = states.map { $0.lake.coordinate }
        guard let first = coords.first else {
            // Fallback: Seattle.
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33),
                                      span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4))
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.08),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.08))
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview("Map header") {
    LakeMapHeader(states: MockPreviewBuilder.states(), isExpanded: .constant(true))
        .padding()
        .background(Color.appBackground)
}
