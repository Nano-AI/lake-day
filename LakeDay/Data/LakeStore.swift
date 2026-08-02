import Foundation

/// Loads the curated lake list from the bundled `lakes.json`. Synchronous and
/// cheap — the file is small and read once at launch.
struct LakeStore {

    private struct Payload: Codable {
        let lakes: [Lake]
    }

    enum LoadError: Error, LocalizedError {
        case missingResource
        case decodeFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "lakes.json is missing from the app bundle."
            case .decodeFailed(let underlying):
                return "Couldn't read lakes.json: \(underlying.localizedDescription)"
            }
        }
    }

    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Throwing load — surfaces a clear error if the resource is missing or bad.
    func loadLakes() throws -> [Lake] {
        guard let url = bundle.url(forResource: "lakes", withExtension: "json") else {
            throw LoadError.missingResource
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return payload.lakes
        } catch {
            throw LoadError.decodeFailed(underlying: error)
        }
    }

    /// Non-throwing convenience for view code / previews — empty list on failure.
    func lakesOrEmpty() -> [Lake] {
        (try? loadLakes()) ?? []
    }
}
