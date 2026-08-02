import Foundation
import Observation
import CoreLocation

// MARK: - Per-lake UI state (value type; merged by the ViewModel)

/// A beach with its current advisory, for the detail beaches list.
struct BeachSafety: Identifiable, Hashable, Sendable {
    let beach: Beach
    let status: SafetyStatus
    var id: String { beach.id }
}

/// One day's total for the 7-day strip. `total` is nil when unsafe / no data.
struct DayScore: Identifiable, Hashable, Sendable {
    let date: Date
    let total: Int?
    let forecast: DayForecast
    var id: Date { date }
}

/// Everything a card / detail view needs for one lake, already merged.
struct LakeUIState: Identifiable, Hashable, Sendable {
    let lake: Lake
    /// Worst advisory across the lake's beaches — drives the map pin + gauge.
    var lakeSafety: SafetyStatus
    var beaches: [BeachSafety]
    var conditions: Conditions
    var crowd: CrowdEstimate?
    var score: LakeScore?
    var dayScores: [DayScore]
    /// Straight-line distance to the lake, when location is available.
    var distanceMeters: Double?
    /// Age of the oldest feed we fell back to (for a "showing older data" note).
    var staleFallbackAge: TimeInterval?
    var loadError: String?
    /// Smoke note shown with the verdict when air quality is unhealthy (AQI ≥ 101).
    /// Built in the merge layer, not the RatingEngine, so the engine stays pure.
    var smokeNote: String? = nil
    /// Live news & alerts (NWS + Google News RSS), already merged/capped.
    /// Display-only — never a score input. Empty → detail omits the section.
    var news: [NewsItem] = []

    var id: String { lake.id }

    var etaMinutes: Int? { crowd?.etaMinutes }
    var waterTemp: WaterTempReading? { conditions.waterTemp }
    var airQuality: AirQualityReading? { conditions.airQuality }
    var todayForecast: DayForecast? { conditions.today }

    /// Date of the highest-scoring day — the "best day" the DayStrip highlights.
    var bestDay: Date? {
        dayScores.compactMap { s in s.total.map { ($0, s.date) } }
            .max(by: { $0.0 < $1.0 })?.1
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class LakesViewModel {

    private(set) var states: [LakeUIState] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    /// Location authorization, surfaced so views can explain a missing ETA.
    private(set) var locationAuthorized = false

    private var bundledLakes: [Lake]
    private var addedLakes: [Lake]
    private let addedStore: AddedLakesStore
    private let loader: FeedLoader
    private let location: LocationProvider

    /// Bundled curated lakes plus any the user added via search.
    private var allLakes: [Lake] { bundledLakes + addedLakes }

    /// Last resolved user coordinate (nil when location is denied) — reused by
    /// the search screen for "lakes near you" and to bias search regions.
    private(set) var userCoordinate: (lat: Double, lon: Double)?

    init(lakes: [Lake],
         beachSafety: any BeachSafetyProviding,
         waterTemp: any WaterTempProviding,
         forecast: any ForecastProviding,
         traffic: any TrafficProviding,
         airQuality: any AirQualityProviding,
         news: any NewsProviding,
         algae: any AlgaeAdvisoryProviding,
         cache: FeedCache = FeedCache(),
         location: LocationProvider? = nil,
         addedStore: AddedLakesStore = AddedLakesStore()) {
        self.bundledLakes = lakes
        self.addedStore = addedStore
        self.addedLakes = addedStore.load()
        self.loader = FeedLoader(beachSafety: beachSafety,
                                 waterTemp: waterTemp,
                                 forecast: forecast,
                                 traffic: traffic,
                                 airQuality: airQuality,
                                 news: news,
                                 algae: algae,
                                 cache: cache)
        // Built here (not as a default arg) so the @MainActor init is its
        // isolation context — LocationProvider.init is main-actor isolated.
        self.location = location ?? LocationProvider()
        // Seed placeholder states so the list renders immediately while feeds load.
        self.states = (lakes + addedLakes).map { LakeUIState.placeholder(for: $0) }
    }

    /// Fan out all feeds for all lakes concurrently and merge. Never blocks on a
    /// single slow feed (per-feed 10s timeout inside `FeedLoader`).
    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }

        // Location is best-effort. When denied we skip ETA and keep heuristics.
        let coord = await resolveUserLocation()
        locationAuthorized = (coord != nil)
        userCoordinate = coord

        let loader = self.loader
        let lakes = self.allLakes

        let merged = await withTaskGroup(of: LakeUIState.self) { group in
            for lake in lakes {
                group.addTask {
                    await loader.loadState(for: lake, userCoord: coord)
                }
            }
            var out: [LakeUIState] = []
            for await state in group { out.append(state) }
            return out
        }

        states = Self.sorted(merged)
    }

    func refresh() async { await load() }

    // MARK: Search-added lakes

    /// Add a lake found via search: show it immediately (placeholder), persist
    /// it, then fetch its real state and re-sort it into place.
    func addLake(_ lake: Lake) async {
        guard !allLakes.contains(where: { $0.id == lake.id }) else { return }
        addedLakes.append(lake)
        addedStore.save(addedLakes)
        states = Self.sorted(states + [.placeholder(for: lake)])
        let newState = await loader.loadState(for: lake, userCoord: userCoordinate)
        states = Self.sorted(states.map { $0.lake.id == lake.id ? newState : $0 })
    }

    /// Remove a user-added lake (the bundled curated lakes can't be removed).
    func removeLake(id: String) {
        guard addedLakes.contains(where: { $0.id == id }) else { return }
        addedLakes.removeAll { $0.id == id }
        addedStore.save(addedLakes)
        states.removeAll { $0.lake.id == id }
    }

    /// True if this lake was user-added (vs bundled) — drives the delete affordance.
    func isUserAdded(_ id: String) -> Bool { id.hasPrefix("\(Lake.userAddedPrefix)-") }

    /// True if a lake with this id is already in the list (bundled or added).
    func contains(_ id: String) -> Bool { allLakes.contains { $0.id == id } }

    // MARK: Sorting — rating desc, unsafe (closed) last.

    static func sorted(_ states: [LakeUIState]) -> [LakeUIState] {
        states.sorted { a, b in
            let aClosed = a.lakeSafety.level == .closed
            let bClosed = b.lakeSafety.level == .closed
            if aClosed != bClosed { return !aClosed }   // safe lakes first
            let aScore = a.score?.total ?? -1
            let bScore = b.score?.total ?? -1
            if aScore != bScore { return aScore > bScore }
            return a.lake.name < b.lake.name
        }
    }

    // MARK: Location

    private func resolveUserLocation() async -> (lat: Double, lon: Double)? {
        await location.currentCoordinate()
    }
}

// MARK: - Convenience factories

extension LakesViewModel {
    /// Production wiring: bundled lakes + real feeds. One `KingCountyBeachService`
    /// instance backs both beach-safety and water-temp so a single cached fetch
    /// serves both (bacteria + closures + toxic-algae + water temp, DATA-FEEDS §1).
    static func live() -> LakesViewModel {
        let lakes = LakeStore().lakesOrEmpty()
        let kingCounty = KingCountyBeachService()
        return LakesViewModel(lakes: lakes,
                              beachSafety: kingCounty,
                              waterTemp: kingCounty,
                              forecast: OpenMeteoService(),
                              traffic: TrafficService(),
                              airQuality: AirQualityService(),
                              news: LakeNewsService(),
                              algae: AlgaeAdvisoryService())
    }

    /// Preview wiring: rich deterministic mocks, no network, no location.
    static func preview() -> LakesViewModel {
        let vm = LakesViewModel(lakes: MockServices.lakes,
                                beachSafety: MockServices.beachSafetyService,
                                waterTemp: MockServices.waterTempService,
                                forecast: MockServices.forecastService,
                                traffic: MockServices.trafficService,
                                airQuality: MockServices.airQualityService,
                                news: MockServices.newsService,
                                algae: MockServices.algaeService,
                                location: LocationProvider(disabled: true),
                                addedStore: .ephemeral)
        // Build states synchronously so previews render without awaiting.
        vm.states = Self.sorted(MockPreviewBuilder.states())
        vm.hasLoaded = true
        return vm
    }
}

extension LakeUIState {
    static func placeholder(for lake: Lake) -> LakeUIState {
        LakeUIState(lake: lake,
                    lakeSafety: .unknown,
                    beaches: lake.beaches.map { BeachSafety(beach: $0, status: .unknown) },
                    conditions: Conditions(),
                    crowd: nil,
                    score: nil,
                    dayScores: [],
                    distanceMeters: nil,
                    staleFallbackAge: nil,
                    loadError: nil)
    }
}
