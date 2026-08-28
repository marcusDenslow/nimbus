import Foundation

/// Fetches store-page detail (description, developer, genres, release date) for the game
/// info page. Steam games have a real page via Steam's public `appdetails` endpoint; other
/// stores have no open API, so those fall back to whatever the catalog already carries.
///
/// Results are cached in memory and on disk so reopening a game's page is instant and works
/// offline after the first visit.
@MainActor
final class StoreInfo {
    static let shared = StoreInfo()

    private var memory: [Int: GameDetails] = [:]
    private var inFlight: [Int: Task<GameDetails?, Never>] = [:]
    private let dir = AppModel.supportDir.appendingPathComponent("details", isDirectory: true)

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Best-effort detail for a game. Returns a catalog-derived fallback immediately when
    /// there's no Steam page to fetch, so the info panel is never blank.
    /// Synchronous peek at already-fetched detail (memory only) — the stats dashboard reads this
    /// after `enrichLibraryForStats` has warmed the cache.
    func cached(_ id: Int) -> GameDetails? { memory[id] }

    func details(for game: Game) async -> GameDetails {
        if let cached = memory[game.id] { return cached }

        let file = dir.appendingPathComponent("\(game.id).json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(GameDetails.self, from: data) {
            memory[game.id] = saved
            return saved
        }

        // Only Steam exposes an open detail API. Merge whatever it returns over the catalog fields.
        guard let appID = game.steamAppID else { return fallback(for: game) }

        let task: Task<GameDetails?, Never>
        if let existing = inFlight[game.id] {
            task = existing
        } else {
            task = Task<GameDetails?, Never> { await Self.fetchSteam(appID: appID) }
            inFlight[game.id] = task
        }
        let fetched = await task.value
        inFlight[game.id] = nil

        var merged = fallback(for: game)
        if let fetched {
            merged.description = fetched.description ?? merged.description
            merged.developer = fetched.developer ?? merged.developer
            merged.releaseDate = fetched.releaseDate ?? merged.releaseDate
            if let g = fetched.genres, !g.isEmpty { merged.genres = g }
            merged.metacritic = fetched.metacritic
            merged.steamReviews = fetched.steamReviews
            merged.releaseYear = fetched.releaseYear
        }
        memory[game.id] = merged
        if let data = try? JSONEncoder().encode(merged) {
            try? data.write(to: file, options: .atomic)
        }
        return merged
    }

    private func fallback(for game: Game) -> GameDetails {
        GameDetails(
            description: nil,
            developer: game.publisher,
            releaseDate: nil,
            genres: game.genres
        )
    }

    /// Steam's appdetails response is keyed by the appid at the top level, so the shape is
    /// dynamic — parse it with JSONSerialization rather than a fixed Codable tree.
    private static func fetchSteam(appID: String) async -> GameDetails? {
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any],
              entry["success"] as? Bool == true,
              let payload = entry["data"] as? [String: Any]
        else { return nil }

        let description = (payload["short_description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let developer = (payload["developers"] as? [String])?.first
        let releaseDate = (payload["release_date"] as? [String: Any])?["date"] as? String
        let genres = (payload["genres"] as? [[String: Any]])?
            .compactMap { $0["description"] as? String }
        let metacritic = (payload["metacritic"] as? [String: Any])?["score"] as? Int
        let steamReviews = (payload["recommendations"] as? [String: Any])?["total"] as? Int
        let releaseYear = releaseDate.flatMap(Self.year(from:))

        return GameDetails(
            description: description?.isEmpty == true ? nil : description,
            developer: developer,
            releaseDate: releaseDate,
            genres: genres?.isEmpty == true ? nil : genres,
            metacritic: metacritic,
            steamReviews: steamReviews,
            releaseYear: releaseYear
        )
    }

    /// Pull a 4-digit year out of Steam's free-form release string ("12 Oct, 2023", "2019", …).
    private static func year(from dateString: String) -> Int? {
        var digits = ""
        for ch in dateString where ch.isNumber {
            digits.append(ch)
            if digits.count == 4, let n = Int(digits), n >= 1970, n <= 2100 { return n }
            if digits.count == 4 { digits = "" }   // wasn't a plausible year — keep scanning
        }
        // Fall back to any 4-run at the end (e.g. leading day/month consumed the first run).
        let matches = dateString.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return matches.first { $0 >= 1970 && $0 <= 2100 }
    }
}
