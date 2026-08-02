import SwiftUI

/// Home screen: collapsible map header over the ranked, scrolling lake cards.
struct LakeListView: View {
    @Environment(LakesViewModel.self) private var viewModel
    @State private var mapExpanded = true
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.states.isEmpty {
                    ContentUnavailableView(
                        "No lakes yet",
                        systemImage: "drop",
                        description: Text("Add lakes to lakes.json to get started.")
                    )
                } else {
                    content
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Lake Day")
            .navigationDestination(for: String.self) { lakeID in
                if let state = viewModel.states.first(where: { $0.lake.id == lakeID }) {
                    LakeDetailView(state: state)
                }
            }
            .refreshable { await viewModel.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("Add a lake")
                }
            }
            .sheet(isPresented: $showSearch) {
                LakeSearchView()
                    .environment(viewModel)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                LakeMapHeader(states: viewModel.states, isExpanded: $mapExpanded)

                if !viewModel.locationAuthorized && viewModel.hasLoaded {
                    // Honest note — the app still works, it just can't show ETA.
                    Text("Turn on location to sort by drive time and show ETAs.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVStack(spacing: 12) {
                    ForEach(viewModel.states) { state in
                        NavigationLink(value: state.lake.id) {
                            LakeCard(state: state)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if viewModel.isUserAdded(state.lake.id) {
                                Button(role: .destructive) {
                                    viewModel.removeLake(id: state.lake.id)
                                } label: {
                                    Label("Remove lake", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

#Preview("Lake list") {
    LakeListView()
        .environment(LakesViewModel.preview())
}

#Preview("Lake list — dark") {
    LakeListView()
        .environment(LakesViewModel.preview())
        .preferredColorScheme(.dark)
}
