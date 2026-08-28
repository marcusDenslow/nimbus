import Foundation

/// Reads the GeForce NOW client's local data to sync the user's actual GFN library.
///
/// NVIDIA has no public per-account API, and their static supported-games JSON is
/// years stale. But the GFN client logs every library title on startup
/// ("Found game <title> in LIBRARY"), and its service-worker cache holds the raw
/// LCARS GraphQL responses with each game's cmsId and artwork. Between the two we
/// can rebuild the user's library with launchable IDs — entirely offline.
enum GFNLocal {
    static let gfnDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NVIDIA/GeForceNOW", isDirectory: true)

    private static var cacheStorageDir: URL {
        gfnDir.appendingPathComponent("CefCache/Default/Service Worker/CacheStorage", isDirectory: true)
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: gfnDir.path)
    }

    /// Titles in the user's GFN library, from the client's console log.
    /// Logged fresh on every GFN app startup.
    static func libraryTitles() -> [String] {
        var titles: [String] = []
        var seen = Set<String>()
        for name in ["console.log", "console.log.bak"] {
            let url = gfnDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            guard let regex = try? NSRegularExpression(pattern: "Found game (.+?) in LIBRARY") else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let titleRange = Range(match.range(at: 1), in: text) else { return }
                let title = text[titleRange].trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, seen.insert(normalize(title)).inserted {
                    titles.append(title)
                }
            }
        }
        return titles
    }

    /// Games recoverable from the GFN client's cached catalog responses:
    /// cmsId, title, store, and landscape artwork. Roughly whatever the user's
    /// client has browsed — reliably includes their whole library.
    static func cachedGames() -> [Game] {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheStorageDir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return [] }

        // title, then within the following window the first variant id, store and banner art
        let pattern = #""title":"((?:[^"\\]|\\.)*)"[\s\S]{0,4000}?"variants":\[\{"id":"(\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let artRegex = try? NSRegularExpression(pattern: #""TV_BANNER":"(https://[^"]+)""#),
              let storeRegex = try? NSRegularExpression(pattern: #""appStore":"([A-Z_]+)""#)
        else { return [] }

        var games: [Int: Game] = [:]
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size > 200, size < 20_000_000,
                  let data = try? Data(contentsOf: file)
            else { continue }

            let text = String(decoding: data, as: UTF8.self)
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match,
                      let titleRange = Range(match.range(at: 1), in: text),
                      let idRange = Range(match.range(at: 2), in: text),
                      let cmsId = Int(text[idRange]),
                      games[cmsId] == nil
                else { return }

                let title = decodeJSONString(String(text[titleRange]))
                guard !title.isEmpty else { return }

                // Each game object lays out as {"images":{...},"title":"...",...,"variants":[...]},
                // so artwork sits just before the title and the store just after it.
                let beforeWindow = NSRange(max(0, match.range.location - 900)..<match.range.location)
                var art: String?
                if let artMatch = artRegex.matches(in: text, range: beforeWindow).last,
                   let artRange = Range(artMatch.range(at: 1), in: text) {
                    art = String(text[artRange])
                }
                let afterWindow = NSRange(match.range.location..<min(match.range.location + match.range.length + 600, range.length))
                var store: String?
                if let storeMatch = storeRegex.firstMatch(in: text, range: afterWindow),
                   let storeRange = Range(storeMatch.range(at: 1), in: text) {
                    store = prettyStore(String(text[storeRange]))
                }

                games[cmsId] = Game(
                    id: cmsId,
                    title: title,
                    sortName: nil,
                    steamUrl: nil,
                    store: store,
                    publisher: nil,
                    genres: nil,
                    status: "AVAILABLE",
                    lastPlayed: nil,
                    nvArt: art
                )
            }
        }
        return Array(games.values)
    }

    /// Title comparison key: case/punctuation/trademark-insensitive.
    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let alnum = folded.unicodeScalars.map { scalar -> Character in
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                ? Character(scalar)
                : " "
        }
        return String(alnum).split(separator: " ").joined(separator: " ")
    }

    private static func decodeJSONString(_ escaped: String) -> String {
        let quoted = Data("\"\(escaped)\"".utf8)
        return (try? JSONDecoder().decode(String.self, from: quoted)) ?? escaped
    }

    private static func prettyStore(_ raw: String) -> String {
        switch raw {
        case "STEAM": return "Steam"
        case "EPIC": return "Epic"
        case "UBISOFT", "UPLAY": return "Ubisoft Connect"
        case "GOG": return "GOG"
        case "ORIGIN", "EA_APP": return "EA app"
        case "BATTLENET": return "Battle.net"
        case "XBOX", "MICROSOFT": return "Xbox"
        case "NONE": return ""
        default: return raw.capitalized
        }
    }
}
