import Foundation

/// Per-feed cache TTLs (ARCHITECTURE.md). Kept in one place so the ViewModel
/// and the services agree on freshness windows.
enum CacheTTL {
    static let bacteria: TimeInterval   = 6 * 3600
    static let algae: TimeInterval      = 6 * 3600
    static let waterTemp: TimeInterval  = 1 * 3600
    static let forecast: TimeInterval   = 3 * 3600
    static let airQuality: TimeInterval = 3 * 3600
    static let news: TimeInterval       = 4 * 3600
    static let eta: TimeInterval        = 15 * 60
}

/// A cached value plus the moment it was stored, so callers can show age even
/// when they choose to use a stale entry.
struct CachedEntry<Value: Codable & Sendable>: Codable, Sendable {
    let value: Value
    let storedAt: Date

    var age: TimeInterval { Date().timeIntervalSince(storedAt) }
    func isFresh(ttl: TimeInterval) -> Bool { age < ttl }
}

/// Generic per-key TTL cache: in-memory first, backed by JSON files in the
/// system caches directory so results survive relaunches. An `actor` so
/// concurrent feed tasks can read/write without data races.
///
/// The cache is deliberately type-agnostic: each call names the value type it
/// expects. Callers must use a stable `key`/`type` pairing per feed.
actor FeedCache {

    private struct AnyBox {
        let storedAt: Date
        let data: Data   // JSON-encoded value; decoded lazily per requested type
    }

    private var memory: [String: AnyBox] = [:]
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(namespace: String = "FeedCache", fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent(namespace, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Read

    /// Latest entry for `key` regardless of freshness (memory, then disk).
    /// Returns the value with its age so the caller can decide.
    func entry<Value: Codable & Sendable>(for key: String, as type: Value.Type) -> CachedEntry<Value>? {
        if let box = memory[key], let value = try? decoder.decode(Value.self, from: box.data) {
            return CachedEntry(value: value, storedAt: box.storedAt)
        }
        // Fall back to disk, and warm memory on a hit.
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let stored = try? decoder.decode(StoredFile.self, from: data),
              let value = try? decoder.decode(Value.self, from: stored.payload)
        else { return nil }
        memory[key] = AnyBox(storedAt: stored.storedAt, data: stored.payload)
        return CachedEntry(value: value, storedAt: stored.storedAt)
    }

    /// Entry only if still within `ttl`.
    func fresh<Value: Codable & Sendable>(for key: String, as type: Value.Type, ttl: TimeInterval) -> Value? {
        guard let entry = entry(for: key, as: Value.self), entry.isFresh(ttl: ttl) else { return nil }
        return entry.value
    }

    // MARK: Write

    func set<Value: Codable & Sendable>(_ value: Value, for key: String, at date: Date = Date()) {
        guard let payload = try? encoder.encode(value) else { return }
        memory[key] = AnyBox(storedAt: date, data: payload)
        let file = StoredFile(storedAt: date, payload: payload)
        if let data = try? encoder.encode(file) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    // MARK: Maintenance

    func clear() {
        memory.removeAll()
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Disk plumbing

    /// On-disk shape: the raw encoded payload plus its timestamp.
    private struct StoredFile: Codable {
        let storedAt: Date
        let payload: Data
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(sanitized(key)).appendingPathExtension("json")
    }

    private func sanitized(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = key.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars)
    }
}
