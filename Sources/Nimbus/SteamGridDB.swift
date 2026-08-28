import AppKit

/// Thin SteamGridDB API client for the customize card's artwork search and the logo titles.
///
/// Needs a free personal API key (steamgriddb.com → Profile → Preferences → API), stored in
/// UserDefaults. Flow: autocomplete the game title to an SGDB game id, list that game's art —
/// heroes (1920×620 landscape, the ambient background's shape), grids (box-art covers for the
/// shelf card), or logos (transparent wordmarks shown in place of the plain-text title).
@MainActor
enum SteamGridDB {
    /// Which artwork pool the picker is browsing. `screenshot` and `wallpaper` aren't SGDB at
    /// all — SGDB heroes only come as ~3:1 banners, so true 16:9 art is served from the Steam
    /// store's screenshot API (official shots) and Wallhaven's wallpaper API (community 4K).
    /// `logo` is SGDB's transparent wordmark pool, applied as the game's title logo.
    enum Kind: CaseIterable { case screenshot, wallpaper, hero, grid, logo }
    private static let base = URL(string: "https://www.steamgriddb.com/api/v2/")!
    private static let keyDefault = "steamGridDBKey"

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: keyDefault) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyDefault) }
    }
    static var hasKey: Bool { !apiKey.isEmpty }

    struct SGDBGame: Decodable, Identifiable, Equatable {
        let id: Int
        let name: String
    }

    /// One artwork entry. `thumb` is the grid thumbnail; `url` the full-resolution file.
    /// Dimensions and author feed the hero-focus picker's caption. `urlOriginal` (Steam
    /// screenshots only) points at the publisher's original upload — often 4K — which
    /// `download` tries before settling for `url`.
    struct SGDBImage: Decodable, Identifiable, Equatable {
        let id: Int
        let url: String
        let thumb: String
        let width: Int?
        let height: Int?
        let author: Author?
        var urlOriginal: String?

        struct Author: Decodable, Equatable {
            let name: String
        }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let errors: [String]?
    }

    enum SGDBError: LocalizedError {
        case noKey, badKey, network, noMatch

        var errorDescription: String? {
            switch self {
            case .noKey: return "No SteamGridDB API key set"
            case .badKey: return "SteamGridDB rejected the API key"
            case .network: return "Couldn't reach SteamGridDB"
            case .noMatch: return "No SteamGridDB entry found for this title"
            }
        }
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        guard hasKey else { throw SGDBError.noKey }
        guard let url = URL(string: path, relativeTo: base) else { throw SGDBError.network }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { throw SGDBError.network }
        if http.statusCode == 401 { throw SGDBError.badKey }
        guard http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Envelope<T>.self, from: data),
              decoded.success, let payload = decoded.data else { throw SGDBError.network }
        return payload
    }

    /// Title → SGDB games, best match first.
    static func searchGames(_ query: String) async throws -> [SGDBGame] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        return try await get("search/autocomplete/\(escaped)")
    }

    /// Hero (landscape banner) artwork for an SGDB game.
    static func heroes(gameID: Int) async throws -> [SGDBImage] {
        try await get("heroes/game/\(gameID)")
    }

    /// Grid (box-art cover) artwork. Constrained to the portrait/square shapes the shelf's
    /// square tiles crop well, and static files only (no animated covers).
    static func grids(gameID: Int) async throws -> [SGDBImage] {
        try await get("grids/game/\(gameID)?dimensions=600x900,512x512,1024x1024&types=static")
    }

    /// Logo (transparent wordmark) artwork, best-ranked first.
    static func logos(gameID: Int) async throws -> [SGDBImage] {
        try await get("logos/game/\(gameID)")
    }

    static func images(gameID: Int, kind: Kind) async throws -> [SGDBImage] {
        switch kind {
        case .hero: return try await heroes(gameID: gameID)
        case .grid: return try await grids(gameID: gameID)
        case .logo: return try await logos(gameID: gameID)
        case .screenshot, .wallpaper: return []   // not SGDB pools — Steam / Wallhaven
        }
    }

    /// Wallhaven wallpaper search — keyless, SFW-only, 16:9 at 1080p or better, best matches
    /// first. Community uploads, so quality varies, but it's the deepest 4K pool there is for
    /// game art. The API pages at a fixed 24 results, so the first four pages are fetched in
    /// parallel (up to 96 wallpapers); short/empty pages just contribute what they have.
    static func wallhavenSearch(query: String) async throws -> [SGDBImage] {
        struct Response: Decodable {
            let data: [Wall]
        }
        struct Wall: Decodable {
            let id: String
            let path: String
            let dimension_x: Int
            let dimension_y: Int
            let thumbs: Thumbs
            struct Thumbs: Decodable {
                let large: String
            }
        }

        func fetchPage(_ page: Int) async -> [Wall] {
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard let url = URL(string: "https://wallhaven.cc/api/v1/search?q=\(escaped)&categories=110&purity=100&atleast=1920x1080&ratios=16x9&sorting=relevance&page=\(page)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(Response.self, from: data)
            else { return [] }
            return decoded.data
        }

        let pages = await withTaskGroup(of: (Int, [Wall]).self) { group in
            for page in 1...4 {
                group.addTask { (page, await fetchPage(page)) }
            }
            var results: [(Int, [Wall])] = []
            for await entry in group { results.append(entry) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        guard !pages.isEmpty else { throw SGDBError.noMatch }

        var seen = Set<String>()
        return pages.filter { seen.insert($0.id).inserted }.map {
            // Wallhaven ids are alphanumeric; fold them to a stable Int for SGDBImage.
            var hash: Int = 5381
            for byte in $0.id.utf8 { hash = (hash &* 33) &+ Int(byte) }
            return SGDBImage(id: abs(hash), url: $0.path, thumb: $0.thumbs.large,
                             width: $0.dimension_x, height: $0.dimension_y, author: nil,
                             urlOriginal: nil)
        }
    }

    /// Resolve a title to a Steam appid via the store's keyless search — for games whose
    /// catalog record has no steamUrl (GFN-cache recoveries) even though they're on Steam.
    static func steamAppID(title: String) async throws -> String {
        let escaped = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        guard let url = URL(string: "https://store.steampowered.com/api/storesearch/?term=\(escaped)&cc=us&l=en")
        else { throw SGDBError.network }
        struct SearchResult: Decodable {
            let items: [Item]
            struct Item: Decodable {
                let id: Int
                let name: String
            }
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResult.self, from: data)
        else { throw SGDBError.network }
        guard let top = decoded.items.first else { throw SGDBError.noMatch }
        return String(top.id)
    }

    /// Steam store screenshots (1920×1080) for the Backgrounds tab. Mapped into `SGDBImage`
    /// so the picker treats every source the same; `thumb` gets the 600×338 thumbnail for the
    /// rail while `url` keeps the full-res file for the preview and download.
    static func steamScreenshots(appID: String) async throws -> [SGDBImage] {
        struct Details: Decodable {
            let success: Bool
            let data: Payload?
            struct Payload: Decodable {
                let screenshots: [Shot]?
            }
        }
        struct Shot: Decodable {
            let id: Int
            let path_thumbnail: String
            let path_full: String
        }
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&filters=screenshots")
        else { throw SGDBError.network }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode([String: Details].self, from: data),
              let payload = decoded[appID], payload.success
        else { throw SGDBError.network }
        guard let shots = payload.data?.screenshots, !shots.isEmpty else { throw SGDBError.noMatch }
        // The store only serves fixed renditions (path_full is a literal ss_<hash>.1920x1080.jpg),
        // but stripping the size suffix reaches the publisher's original upload — 3840×2160 for
        // games whose press shots were 4K. Kept alongside the rendition as the download's first try.
        return shots.map {
            SGDBImage(id: $0.id, url: $0.path_full, thumb: $0.path_thumbnail,
                      width: nil, height: nil, author: nil,
                      urlOriginal: $0.path_full.replacingOccurrences(of: ".1920x1080.", with: "."))
        }
    }

    /// One call for the picker: resolve the title, pull the top match's art of the given kind.
    /// Returns the matched SGDB game name alongside the images.
    static func imagesForTitle(_ title: String, kind: Kind) async throws -> (match: String, images: [SGDBImage]) {
        let games = try await searchGames(title)
        guard let top = games.first else { throw SGDBError.noMatch }
        let images = try await images(gameID: top.id, kind: kind)
        guard !images.isEmpty else { throw SGDBError.noMatch }
        return (top.name, images)
    }

    /// Download the file behind a picked image, to a temp path the CustomStore can copy in
    /// (it keys the stored file's extension off this URL's). The original upload is tried
    /// first when one is known (Steam screenshots — the 4K path), then the sized rendition.
    static func download(_ image: SGDBImage) async throws -> URL {
        let candidates = [image.urlOriginal, image.url].compactMap { $0 }.compactMap(URL.init(string:))
        for url in candidates {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, NSImage(data: data) != nil
            else { continue }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("sgdb-\(image.id).\(ext)")
            try data.write(to: tmp, options: .atomic)
            return tmp
        }
        throw SGDBError.network
    }
}
