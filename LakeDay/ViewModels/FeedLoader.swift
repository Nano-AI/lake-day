import Foundation
import CoreLocation

/// Off-main-actor fetch + merge for a single lake. Sendable so the ViewModel
/// can fan it out across a task group. Every feed call is wrapped in a 10s
/// timeout and falls back to the last cached value (with its age) — nothing
/// here blocks the list on one slow county server.
struct FeedLoader: Sendable {
    let beachSafety: any BeachSafetyProviding
    let waterTemp: any WaterTempProviding
    let forecast: any ForecastProviding
    let traffic: any TrafficProviding
    let airQuality: any AirQualityProviding
    let news: any NewsProviding
    let algae: any AlgaeAdvisoryProviding
    let cache: FeedCache
    let engine = RatingEngine()

    // Computed (not stored) so it stays out of the synthesized memberwise init,
    // which must remain internally accessible from the ViewModel's file.
    private var perFeedTimeout: Double { 10 }

    // MARK: Merge one lake

    func loadState(for lake: Lake, userCoord: (lat: Double, lon: Double)?) async -> LakeUIState {
        // Fan out the independent feeds.
        async let beachesTask = loadBeachSafeties(lake)
        async let tempTask = loadWaterTemp(lake)
        async let forecastTask = loadForecast(lake)
        async let airQualityTask = loadAirQuality(lake)
        async let newsTask = loadNews(lake)
        async let algaeTask = loadAlgae(lake)

        let beaches = await beachesTask
        let tempResult = await tempTask
        let forecastResult = await forecastTask
        let airResult = await airQualityTask
        let newsResult = await newsTask
        let algaeStatus = await algaeTask

        let forecastDays = forecastResult.days
        let today = forecastDays.first
        // Statewide algae advisory folded in beside beach bacteria — for a
        // search-added lake with no monitored beaches, it may be the only signal.
        let lakeSafety = Self.worst(beaches.map { $0.status } + [algaeStatus].compactMap { $0 })

        // Today's crowd carries the live ETA (when we have coords).
        let todayCrowd = await loadTodayCrowd(lake, coord: userCoord, forecast: today)

        // Primary (today) score.
        var score: LakeScore?
        if let today {
            score = engine.score(safety: lakeSafety,
                                  waterTempF: tempResult.reading?.fahrenheit,
                                  forecast: today,
                                  crowd: todayCrowd)
        }

        // 7-day strip. Only day 0 may hit the network (live ETA); future days are
        // pure heuristic, so we call the traffic service directly with no coords.
        var dayScores: [DayScore] = []
        for (index, day) in forecastDays.enumerated() {
            let crowd: CrowdEstimate
            if index == 0 {
                crowd = todayCrowd
            } else {
                crowd = (try? await traffic.crowdEstimate(for: lake, from: nil, forecast: day, on: day.date))
                    ?? CrowdEstimate(level: .medium, value: 0.5)
            }
            let s = engine.score(safety: lakeSafety,
                                 waterTempF: tempResult.reading?.fahrenheit,
                                 forecast: day,
                                 crowd: crowd)
            dayScores.append(DayScore(date: day.date, total: s.total, forecast: day))
        }

        // Straight-line distance for the card.
        var distance: Double?
        if let userCoord {
            let user = CLLocation(latitude: userCoord.lat, longitude: userCoord.lon)
            distance = user.distance(from: lake.location)
        }

        let loadError = forecastDays.isEmpty
            ? "Couldn't reach the weather service. Check again."
            : nil
        let staleFallbackAge = [forecastResult.age, tempResult.age, airResult.age].compactMap { $0 }.max()

        return LakeUIState(lake: lake,
                           lakeSafety: lakeSafety,
                           beaches: beaches,
                           conditions: Conditions(waterTemp: tempResult.reading,
                                                  forecast: forecastDays,
                                                  airQuality: airResult.reading),
                           crowd: todayCrowd,
                           score: score,
                           dayScores: dayScores,
                           distanceMeters: distance,
                           staleFallbackAge: staleFallbackAge,
                           loadError: loadError,
                           // Smoke note appended to the displayed verdict here in the
                           // merge layer — RatingEngine stays pure (ARCHITECTURE).
                           smokeNote: airResult.reading?.smokeNote,
                           news: newsResult.items)
    }

    // MARK: Per-feed loaders (fresh cache → live+timeout → stale cache → empty)

    private func loadForecast(_ lake: Lake) async -> (days: [DayForecast], age: TimeInterval?) {
        let key = "forecast-\(lake.id)"
        if let fresh = await cache.fresh(for: key, as: [DayForecast].self, ttl: CacheTTL.forecast) {
            return (fresh, nil)
        }
        let forecast = self.forecast
        if let days = await withTimeout(perFeedTimeout, operation: { try await forecast.forecast(for: lake) }),
           !days.isEmpty {
            await cache.set(days, for: key)
            return (days, nil)
        }
        if let entry = await cache.entry(for: key, as: [DayForecast].self) {
            return (entry.value, entry.age)
        }
        return ([], nil)
    }

    private func loadWaterTemp(_ lake: Lake) async -> (reading: WaterTempReading?, age: TimeInterval?) {
        let key = "watertemp-\(lake.id)"
        if let fresh = await cache.fresh(for: key, as: WaterTempReading.self, ttl: CacheTTL.waterTemp) {
            return (fresh, nil)
        }
        let waterTemp = self.waterTemp
        // withTimeout returns T? where here T == WaterTempReading?, so flatten.
        let outcome = await withTimeout(perFeedTimeout, operation: { try await waterTemp.waterTemp(for: lake) })
        if let reading = outcome.flatMap({ $0 }) {
            await cache.set(reading, for: key)
            return (reading, nil)
        }
        if let entry = await cache.entry(for: key, as: WaterTempReading.self) {
            return (entry.value, entry.age)
        }
        return (nil, nil)
    }

    private func loadAirQuality(_ lake: Lake) async -> (reading: AirQualityReading?, age: TimeInterval?) {
        let key = "airquality-\(lake.id)"
        if let fresh = await cache.fresh(for: key, as: AirQualityReading.self, ttl: CacheTTL.airQuality) {
            return (fresh, nil)
        }
        let airQuality = self.airQuality
        // withTimeout returns T? where here T == AirQualityReading?, so flatten.
        let outcome = await withTimeout(perFeedTimeout, operation: { try await airQuality.airQuality(for: lake) })
        if let reading = outcome.flatMap({ $0 }) {
            await cache.set(reading, for: key)
            return (reading, nil)
        }
        if let entry = await cache.entry(for: key, as: AirQualityReading.self) {
            return (entry.value, entry.age)
        }
        return (nil, nil)
    }

    /// News & alerts: fresh cache → live (+timeout) → stale cache → empty.
    /// Display-only, so its age is NOT folded into `staleFallbackAge` (news is
    /// inherently old; a stale story shouldn't trigger the "older data" banner).
    private func loadNews(_ lake: Lake) async -> (items: [NewsItem], age: TimeInterval?) {
        let key = "news-\(lake.id)"
        if let fresh = await cache.fresh(for: key, as: [NewsItem].self, ttl: CacheTTL.news) {
            return (fresh, nil)
        }
        let news = self.news
        if let items = await withTimeout(perFeedTimeout, operation: { try await news.news(for: lake) }),
           !items.isEmpty {
            await cache.set(items, for: key)
            return (items, nil)
        }
        if let entry = await cache.entry(for: key, as: [NewsItem].self) {
            return (entry.value, entry.age)
        }
        return ([], nil)
    }

    /// Statewide toxic-algae advisory for the lake (nil when none / unreachable).
    /// The service owns its own snapshot cache; here we just bound the wait.
    private func loadAlgae(_ lake: Lake) async -> SafetyStatus? {
        let algae = self.algae
        // withTimeout returns T? where T == SafetyStatus?, so flatten.
        return await withTimeout(perFeedTimeout, operation: { try await algae.advisory(for: lake) })
            .flatMap { $0 }
    }

    private func loadBeachSafeties(_ lake: Lake) async -> [BeachSafety] {
        let results = await withTaskGroup(of: BeachSafety.self) { group -> [BeachSafety] in
            for beach in lake.beaches {
                group.addTask { await self.loadBeachSafety(beach, lake: lake) }
            }
            var out: [BeachSafety] = []
            for await bs in group { out.append(bs) }
            return out
        }
        // Preserve declared beach order.
        return lake.beaches.compactMap { beach in results.first { $0.beach.id == beach.id } }
    }

    private func loadBeachSafety(_ beach: Beach, lake: Lake) async -> BeachSafety {
        let key = "safety-\(lake.id)-\(beach.id)"
        if let fresh = await cache.fresh(for: key, as: SafetyStatus.self, ttl: CacheTTL.bacteria) {
            return BeachSafety(beach: beach, status: fresh)
        }
        let beachSafety = self.beachSafety
        if let status = await withTimeout(perFeedTimeout, operation: { try await beachSafety.safety(for: beach, in: lake) }),
           status.level != .unknown {
            await cache.set(status, for: key)
            return BeachSafety(beach: beach, status: status)
        }
        if let entry = await cache.entry(for: key, as: SafetyStatus.self) {
            return BeachSafety(beach: beach, status: entry.value)   // stale but real
        }
        return BeachSafety(beach: beach, status: .unknown)
    }

    private func loadTodayCrowd(_ lake: Lake, coord: (lat: Double, lon: Double)?, forecast: DayForecast?) async -> CrowdEstimate {
        let key = "crowd-\(lake.id)"
        if let fresh = await cache.fresh(for: key, as: CrowdEstimate.self, ttl: CacheTTL.eta) {
            return fresh
        }
        let traffic = self.traffic
        let lat = coord?.lat
        let lon = coord?.lon
        let date = Date()
        let outcome = await withTimeout(perFeedTimeout, operation: {
            let coordinate = (lat != nil && lon != nil)
                ? CLLocationCoordinate2D(latitude: lat!, longitude: lon!)
                : nil
            return try await traffic.crowdEstimate(for: lake, from: coordinate, forecast: forecast, on: date)
        })
        if let crowd = outcome {
            await cache.set(crowd, for: key)
            return crowd
        }
        if let entry = await cache.entry(for: key, as: CrowdEstimate.self) {
            return entry.value
        }
        return CrowdEstimate(level: .medium, value: 0.5)
    }

    // MARK: Lake-level safety merge

    /// Highest severity wins: closed > caution > open > unknown. `.unknown`
    /// only if every beach is unknown — a real signal never gets masked.
    static func worst(_ statuses: [SafetyStatus]) -> SafetyStatus {
        let order: [SafetyLevel] = [.closed, .caution, .open, .unknown]
        for level in order {
            if let match = statuses.first(where: { $0.level == level }) {
                return match
            }
        }
        return .unknown
    }
}

// MARK: - Timeout helper

/// Runs `operation`, returning nil if it throws or exceeds `seconds`. Used to
/// keep any single feed from stalling the fan-out.
func withTimeout<T: Sendable>(_ seconds: Double,
                              operation: @escaping @Sendable () async throws -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

// MARK: - Preview state builder

/// Builds fully-merged `LakeUIState`s synchronously from the deterministic
/// mocks, so SwiftUI previews render instantly without awaiting a fan-out.
enum MockPreviewBuilder {
    static func states() -> [LakeUIState] {
        let engine = RatingEngine()
        return MockServices.lakes.map { lake in
            let safety = MockServices.safety(for: lake)
            let temp = MockServices.waterTemp(for: lake)
            let days = MockServices.forecast(for: lake)
            let crowd = MockServices.crowd(for: lake)
            let air = MockServices.airQuality(for: lake)
            let news = MockServices.news(for: lake)

            var score: LakeScore?
            if let today = days.first {
                score = engine.score(safety: safety, waterTempF: temp?.fahrenheit, forecast: today, crowd: crowd)
            }
            let dayScores = days.map { day -> DayScore in
                let s = engine.score(safety: safety, waterTempF: temp?.fahrenheit, forecast: day, crowd: crowd)
                return DayScore(date: day.date, total: s.total, forecast: day)
            }

            return LakeUIState(lake: lake,
                               lakeSafety: safety,
                               beaches: lake.beaches.map { BeachSafety(beach: $0, status: safety) },
                               conditions: Conditions(waterTemp: temp, forecast: days, airQuality: air),
                               crowd: crowd,
                               score: score,
                               dayScores: dayScores,
                               distanceMeters: crowd.etaMinutes.map { Double($0) * 700 },
                               staleFallbackAge: nil,
                               loadError: nil,
                               smokeNote: air?.smokeNote,
                               news: news)
        }
    }

    /// A single state by lake id, for focused component previews.
    static func state(id: String) -> LakeUIState {
        states().first { $0.lake.id == id } ?? states()[0]
    }

    /// Non-optional score for previews of score-driven components (the ids used
    /// are never closed, so a score always exists).
    static func requireScore(id: String) -> LakeScore {
        let engine = RatingEngine()
        let lake = MockServices.lakes.first { $0.id == id } ?? MockServices.washington
        let safety = MockServices.safety(for: lake)
        let temp = MockServices.waterTemp(for: lake)
        let day = MockServices.forecast(for: lake).first
            ?? DayForecast(date: Date(), highF: 80, lowF: 60, cloudCoverPercent: 0,
                           windMph: 4, precipProbabilityPercent: 0, uvIndexMax: 7)
        return engine.score(safety: safety, waterTempF: temp?.fahrenheit,
                            forecast: day, crowd: MockServices.crowd(for: lake))
    }
}
