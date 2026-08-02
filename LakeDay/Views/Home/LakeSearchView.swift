import SwiftUI
import CoreLocation

/// Search MapKit for a lake by name or place, or browse lakes near you, and add
/// candidates to the list. Added lakes are scored from their coordinate;
/// outside King County, water safety shows "unknown" (no beach feed exists).
struct LakeSearchView: View {
    @Environment(LakesViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [LakeSearchResult] = []
    @State private var nearby: [LakeSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private let service = LakeSearchService()

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    nearbySection
                } else {
                    resultsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .listStyle(.insetGrouped)
            .navigationTitle("Add a lake")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Lake name or a place")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in scheduleSearch() }
            .task { await loadNearby() }
        }
    }

    // MARK: Sections

    @ViewBuilder private var nearbySection: some View {
        if !nearby.isEmpty {
            Section("Lakes near you") {
                ForEach(nearby) { resultRow($0) }
            }
        } else {
            Section {
                Text(viewModel.userCoordinate == nil
                     ? "Turn on location to see lakes near you, or search above."
                     : "Search a lake name or a place to add more lakes.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    @ViewBuilder private var resultsSection: some View {
        Section {
            if isSearching && results.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(Color.secondaryText)
                }
            } else if results.isEmpty {
                Text("No lakes found for “\(query)”.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            } else {
                ForEach(results) { resultRow($0) }
            }
        }
    }

    private func resultRow(_ result: LakeSearchResult) -> some View {
        let alreadyAdded = viewModel.contains(result.id)
        return Button {
            Task { await viewModel.addLake(result.asLake()) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.body)
                        .foregroundStyle(Color.primaryText)
                    if let locality = result.locality {
                        Text(locality)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(alreadyAdded ? Color.safetyOpen : Color.coldWater)
            }
        }
        .disabled(alreadyAdded)
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)   // debounce keystrokes
            if Task.isCancelled { return }
            let coord = viewModel.userCoordinate.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            let found = await service.search(query: text, near: coord)
            if Task.isCancelled { return }
            results = found
            isSearching = false
        }
    }

    private func loadNearby() async {
        guard let coord = viewModel.userCoordinate else { return }
        nearby = await service.nearby(
            CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon))
    }
}

#Preview("Lake search") {
    LakeSearchView()
        .environment(LakesViewModel.preview())
}
