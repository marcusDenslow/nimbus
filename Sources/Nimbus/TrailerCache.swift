import AppKit

/// Resolves Steam trailer streams for the hover-to-play ambient preview — the little video +
/// theme that starts after you dwell on a game, PS5-style.
///
/// Steam serves trailers as HLS manifests (`.m3u8`), which `AVPlayer` streams natively, so
/// nothing is downloaded — we just resolve and cache the remote URL. Games that ship a
/// `steamUrl` use its appID directly; the rest (Epic / Ubisoft entries like Black Myth: Wukong)
/// are matched to a Steam appID by title so they get trailers too. Misses are remembered.
@MainActor
final class TrailerCache {
    static let shared = TrailerCache()

    private var memory: [Int: URL] = [:]                 // gameID → remote HLS url
    private var inFlight: [Int: Task<URL?, Never>] = [:]
    private var knownMisses: Set<Int> = []
    /// normalized title → Steam appID, so each unmatched game is searched at most once.
    private var appIDByTitle: [String: String] = [:]

    private init() {}

    /// Streamable trailer URL for the game, or `nil` when no Steam match / no movie / fetch fails.
    func trailer(for game: Game) async -> URL? {
        let key = game.id
        if let cached = memory[key] { return cached }
        if knownMisses.contains(key) { return nil }
        if let existing = inFlight[key] { return await existing.value }

        // Inherits @MainActor; the URLSession awaits suspend rather than block, and the payloads
        // (a movie list, a search result) are tiny, so parsing them here is cheap.
        let task = Task<URL?, Never> { [weak self] in
            guard let self else { return nil }
            guard let appID = await self.appID(for: game) else { return nil }
            return await Self.movieURL(appID: appID)
        }

        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory[key] = result } else { knownMisses.insert(key) }
        return result
    }

    /// The game's Steam appID — from its `steamUrl` when present, otherwise resolved by title
    /// (searched once, then cached) so non-Steam library entries still find a trailer.
    private func appID(for game: Game) async -> String? {
        if let known = game.steamAppID { return known }
        let titleKey = Self.norm(game.title)
        if let hit = appIDByTitle[titleKey] { return hit }
        guard let resolved = await Self.resolveAppID(title: game.title) else { return nil }
        appIDByTitle[titleKey] = resolved
        return resolved
    }

    /// Fetch Steam's appdetails and pull an `AVPlayer`-playable trailer stream (HLS preferred).
    private static func movieURL(appID: String) async -> URL? {
        guard let api = URL(string:
            "https://store.steampowered.com/api/appdetails?appids=\(appID)&filters=movies")
        else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: api),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any],
              (entry["success"] as? Bool) == true,
              let dataObj = entry["data"] as? [String: Any],
              let movies = dataObj["movies"] as? [[String: Any]],
              let first = movies.first
        else { return nil }
        // Current Steam serves HLS manifests; older entries may still carry a direct mp4.
        var pick = first["hls_h264"] as? String
        if pick == nil, let mp4 = first["mp4"] as? [String: Any] {
            pick = (mp4["max"] as? String) ?? (mp4["480"] as? String)
        }
        guard var str = pick else { return nil }
        if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        return URL(string: str)
    }

    /// Find a Steam appID for a game by title via Steam's public app search, matching the top
    /// result whose name normalizes to the query — so "Black Myth: Wukong" resolves cleanly.
    private static func resolveAppID(title: String) async -> String? {
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        guard let url = URL(string: "https://steamcommunity.com/actions/SearchApps/\(q)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        let want = norm(title)
        // Exact normalized match first; otherwise the first result whose name starts with the
        // title (drops "Deluxe Edition" / "Demo" suffixes). Never a loose substring.
        if let exact = results.first(where: { norm($0["name"] as? String ?? "") == want }) {
            return exact["appid"] as? String
        }
        if let prefix = results.first(where: { norm($0["name"] as? String ?? "").hasPrefix(want) }) {
            return prefix["appid"] as? String
        }
        return nil
    }

    /// Lowercased, alphanumerics only — so punctuation / spacing differences don't block a match.
    private static func norm(_ s: String) -> String {
        String(String.UnicodeScalarView(
            s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}
