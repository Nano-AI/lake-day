import Foundation

/// Persists user-added lakes (found via search) as JSON in `UserDefaults`, so
/// they survive relaunch alongside the bundled `lakes.json` set. Pass
/// `defaults: nil` (`.ephemeral`) for a no-op store in previews and tests.
final class AddedLakesStore {
    private let defaults: UserDefaults?
    private let key = "addedLakes.v1"

    init(defaults: UserDefaults? = .standard) { self.defaults = defaults }

    /// A store that never reads or writes — for previews and tests.
    static let ephemeral = AddedLakesStore(defaults: nil)

    func load() -> [Lake] {
        guard let defaults, let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Lake].self, from: data)) ?? []
    }

    func save(_ lakes: [Lake]) {
        guard let defaults else { return }
        defaults.set(try? JSONEncoder().encode(lakes), forKey: key)
    }
}
