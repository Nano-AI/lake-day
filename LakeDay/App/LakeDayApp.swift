import SwiftUI

@main
struct LakeDayApp: App {
    // The ViewModel owns all feed wiring; @State holds the single @Observable
    // instance for the app's lifetime (iOS 17 Observation pattern).
    @State private var viewModel = LakesViewModel.live()

    var body: some Scene {
        WindowGroup {
            LakeListView()
                .environment(viewModel)
                .tint(.coldWater)
                .task {
                    await viewModel.load()
                }
        }
    }
}
