import Foundation

/// One GeForce NOW game, as it appears in NVIDIA's public supported-games list.
/// `id` is the GFN cmsId, which is also what the deep link uses to launch.
struct Game: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    var sortName: String?
    var steamUrl: String?
    var store: String?
    var publisher: String?
    var genres: [String]?
    var status: String?
    /// Set locally when the user launches the game; never present in the catalog JSON.
    var lastPlayed: Date?
    /// Accumulated streaming time in seconds, tracked from launch until the GFN app quits.
    /// Optional so older library.json files decode.
    var playSeconds: TimeInterval?
    /// Pinned by the user; favorites sort ahead of everything. Optional for decode compat.
    var favorite: Bool?
    /// NVIDIA artwork URL recovered from the GFN client's local cache (landscape banner).
    /// Used when there's no Steam capsule to show.
    var nvArt: String?

    var steamAppID: String? {
        guard let steamUrl, let range = steamUrl.range(of: "/app/") else { return nil }
        let digits = steamUrl[range.upperBound...].prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    /// Art sources in preference order: Steam vertical capsule (600x900, then 1x),
    /// then NVIDIA's banner from the GFN cache. Games with none get a styled fallback tile.
    var artCandidates: [URL] {
        var urls: [URL] = []
        if let appID = steamAppID {
            urls += [
                URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900_2x.jpg"),
                URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg"),
            ].compactMap { $0 }
        }
        if let nvArt, let url = URL(string: nvArt) {
            urls.append(url)
        }
        return urls
    }

    /// Landscape art for the ambient background and the detail-page banner. Always widescreen
    /// so backgrounds stay a consistent shape — mixing portrait capsules and landscape banners
    /// made the background jump aspect between games. Steam's hero/header first, then NVIDIA's
    /// TV banner (already landscape).
    var heroArtCandidates: [URL] {
        var urls: [URL] = []
        if let appID = steamAppID {
            urls += [
                URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_hero.jpg"),
                URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"),
            ].compactMap { $0 }
        }
        if let nvArt, let url = URL(string: nvArt) {
            urls.append(url)
        }
        return urls
    }

    /// Deep link route the GeForce NOW client registers; verified against the installed app binary.
    var launchURL: URL? {
        URL(string: "geforcenow://route/#?cmsId=\(id)&launchSource=External")
    }

    var isFavorite: Bool { favorite == true }

    /// "6 min" / "3.5 h" / "42 h" — shown on the detail page and the profile stats.
    static func playtimeLabel(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours < 1 { return "\(max(1, Int(seconds / 60))) min" }
        if hours < 10 { return String(format: "%.1f h", hours) }
        return "\(Int(hours.rounded())) h"
    }

    /// Stable hash for the fallback tile gradient so a game keeps its color between launches.
    var stableHue: Double {
        var hash: UInt64 = 5381
        for scalar in title.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return Double(hash % 360) / 360.0
    }
}

/// How the library shelf is ordered. Persisted in settings and cycled with `[` / `]`.
enum SortMode: String, CaseIterable, Codable {
    case recent, mostPlayed, alphabetical, store

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .mostPlayed: return "Most Played"
        case .alphabetical: return "A–Z"
        case .store: return "Store"
        }
    }
}

/// A user-made collection of library games (Steam-style category). Persisted separately
/// from the library so membership survives re-syncs. `gameIDs` are GFN cmsIds.
struct Folder: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var gameIDs: [Int] = []
    /// Accent color index into the folder palette. Optional so older folders.json decodes.
    var colorIndex: Int?
}

/// Extra store-page detail fetched lazily for the game info page. Steam games get a real
/// description/developer/genres from the Steam store API; everything else falls back to the
/// catalog fields already on `Game`.
struct GameDetails: Codable {
    var description: String?
    var developer: String?
    var releaseDate: String?
    var genres: [String]?
    /// Steam-only enrichment for the stats dashboard's quality metrics.
    var metacritic: Int?
    var steamReviews: Int?
    var releaseYear: Int?
}
