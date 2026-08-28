import Foundation

/// A single day's total play, for the trend line.
struct DayValue: Identifiable {
    let id = UUID()
    let date: Date
    let seconds: TimeInterval
}

/// One game's contribution, for ranked bars and the 3D chart.
struct GameStat: Identifiable {
    var id: Int { game.id }
    let game: Game
    let seconds: TimeInterval
}

/// A named slice (genre / store / release-year bucket) with a numeric weight.
struct CategoryStat: Identifiable {
    var id: String { name }
    let name: String
    let value: Double
}

/// Everything the dashboard draws, computed once from the profile's library + play history +
/// whatever Steam detail has been warmed. Pure and defensive — every field is safe when the
/// profile is brand new and nothing has been played yet.
struct StatsData {
    var totalSeconds: TimeInterval = 0
    var rangeSeconds: TimeInterval = 0
    var gamesCount = 0
    var playedCount = 0
    var favoritesCount = 0
    var foldersCount = 0
    var sessionsCount = 0
    var avgSessionSeconds: TimeInterval = 0
    var longestSessionSeconds: TimeInterval = 0
    var currentStreak = 0
    var bestStreak = 0

    // Rolling-window playtime for the hero KPIs (current period vs. the one before it).
    var weekSeconds: TimeInterval = 0
    var weekPrevSeconds: TimeInterval = 0
    var monthSeconds: TimeInterval = 0
    var monthPrevSeconds: TimeInterval = 0
    var yearSeconds: TimeInterval = 0
    var yearPrevSeconds: TimeInterval = 0

    var trend: [DayValue] = []
    var topGames: [GameStat] = []
    var genres: [CategoryStat] = []
    var stores: [CategoryStat] = []
    var weekday: [Double] = Array(repeating: 0, count: 7)   // Sun … Sat
    var weekdayGames: [[GameStat]] = Array(repeating: [], count: 7)   // per weekday, games desc by seconds
    var heatmap: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var releaseYears: [CategoryStat] = []

    var avgMetacritic: Int?
    var totalReviews = 0
    var bestReviewed: GameStat?
    var newest: (title: String, year: Int)?
    var oldest: (title: String, year: Int)?

    var hasPlayHistory: Bool { sessionsCount > 0 }
    var peakWeekdaySeconds: Double { weekday.max() ?? 0 }
    var peakHeatSeconds: Double { heatmap.flatMap { $0 }.max() ?? 0 }

    static func make(library: [Game],
                     history: [PlaySession],
                     folders: [Folder],
                     range: AppModel.StatsRange,
                     details: (Int) -> GameDetails?) -> StatsData {
        var s = StatsData()
        let cal = Calendar.current
        let now = Date()

        s.gamesCount = library.count
        s.foldersCount = folders.count
        s.favoritesCount = library.filter(\.isFavorite).count
        s.playedCount = library.filter { ($0.playSeconds ?? 0) > 0 || $0.lastPlayed != nil }.count
        s.totalSeconds = library.reduce(0) { $0 + ($1.playSeconds ?? 0) }

        // Ranked games (all-time, from the durable per-game totals).
        s.topGames = library
            .filter { ($0.playSeconds ?? 0) > 0 }
            .sorted { ($0.playSeconds ?? 0) > ($1.playSeconds ?? 0) }
            .prefix(14)
            .map { GameStat(game: $0, seconds: $0.playSeconds ?? 0) }

        // Genre + store distribution, weighted by playtime, with a count fallback so a fresh
        // library (no playtime yet) still shows its shape.
        let anyPlay = s.totalSeconds > 0
        var genreW: [String: Double] = [:]
        var storeW: [String: Double] = [:]
        for game in library {
            let weight = anyPlay ? (game.playSeconds ?? 0) : 1
            guard weight > 0 else { continue }
            let genres = details(game.id)?.genres ?? game.genres ?? []
            for g in genres.prefix(3) where !g.isEmpty { genreW[g, default: 0] += weight }
            let store = (game.store?.isEmpty == false ? game.store! : "Other")
            storeW[store, default: 0] += weight
        }
        s.genres = genreW.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(8).map { CategoryStat(name: $0.key, value: $0.value) }
        s.stores = storeW.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { CategoryStat(name: $0.key, value: $0.value) }

        // Release-year buckets (needs Steam enrichment; empty until warmed).
        var yearCount: [Int: Int] = [:]
        var newest: (String, Int)?
        var oldest: (String, Int)?
        var metaScores: [Int] = []
        var reviews = 0
        var bestMeta: (Game, Int)?
        for game in library {
            guard let d = details(game.id) else { continue }
            if let y = d.releaseYear {
                yearCount[y, default: 0] += 1
                if newest == nil || y > newest!.1 { newest = (game.title, y) }
                if oldest == nil || y < oldest!.1 { oldest = (game.title, y) }
            }
            if let m = d.metacritic { metaScores.append(m); if bestMeta == nil || m > bestMeta!.1 { bestMeta = (game, m) } }
            if let r = d.steamReviews { reviews += r }
        }
        s.releaseYears = yearCount.sorted { $0.key < $1.key }
            .map { CategoryStat(name: String($0.key), value: Double($0.value)) }
        s.avgMetacritic = metaScores.isEmpty ? nil : Int((Double(metaScores.reduce(0, +)) / Double(metaScores.count)).rounded())
        s.totalReviews = reviews
        s.bestReviewed = bestMeta.map { GameStat(game: $0.0, seconds: $0.0.playSeconds ?? 0) }
        s.newest = newest
        s.oldest = oldest

        // ---- Session-derived series ----
        s.sessionsCount = history.count
        if !history.isEmpty {
            s.avgSessionSeconds = history.reduce(0) { $0 + $1.seconds } / Double(history.count)
            s.longestSessionSeconds = history.map(\.seconds).max() ?? 0
        }
        let gamesByID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var weekdayGameSeconds: [[Int: TimeInterval]] = Array(repeating: [:], count: 7)
        for session in history {
            let comps = cal.dateComponents([.weekday, .hour], from: session.start)
            let wd = (comps.weekday ?? 1) - 1        // 0=Sunday
            let hr = comps.hour ?? 0
            if s.weekday.indices.contains(wd) {
                s.weekday[wd] += session.seconds
                weekdayGameSeconds[wd][session.gameID, default: 0] += session.seconds
            }
            if s.heatmap.indices.contains(wd), s.heatmap[wd].indices.contains(hr) {
                s.heatmap[wd][hr] += session.seconds
            }
        }
        // Per-weekday breakdown by game (for the stacked "Weekly Rhythm" bars): each day's total
        // split into one segment per game, ordered longest-first. Sessions whose game has left the
        // library are dropped — a segment needs a game to colour and identify it.
        s.weekdayGames = weekdayGameSeconds.map { byGame in
            byGame.sorted { $0.value > $1.value }
                .compactMap { gid, sec in gamesByID[gid].map { GameStat(game: $0, seconds: sec) } }
        }

        // Trend: per-day totals across the selected window (or since first session for "all").
        let today = cal.startOfDay(for: now)
        let windowDays: Int = {
            if let d = range.days { return d }
            guard let first = history.map(\.start).min() else { return 30 }
            let days = (cal.dateComponents([.day], from: cal.startOfDay(for: first), to: today).day ?? 0) + 1
            return min(max(days, 14), 365)
        }()
        var byDay: [Date: TimeInterval] = [:]
        for session in history {
            let day = cal.startOfDay(for: session.start)
            byDay[day, default: 0] += session.seconds
        }
        var days: [DayValue] = []
        for offset in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            days.append(DayValue(date: day, seconds: byDay[day] ?? 0))
        }
        s.trend = days
        s.rangeSeconds = days.reduce(0) { $0 + $1.seconds }

        // Streaks: consecutive days with any play, counting back from today/yesterday.
        let playedDays = Set(byDay.filter { $0.value > 0 }.keys)
        s.currentStreak = Self.currentStreak(playedDays: playedDays, today: today, cal: cal)
        s.bestStreak = Self.bestStreak(playedDays: playedDays, cal: cal)

        // Period comparisons: current rolling window vs. the immediately preceding one.
        for session in history {
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: session.start), to: today).day ?? -1
            guard d >= 0 else { continue }
            let sec = session.seconds
            if d < 7 { s.weekSeconds += sec } else if d < 14 { s.weekPrevSeconds += sec }
            if d < 30 { s.monthSeconds += sec } else if d < 60 { s.monthPrevSeconds += sec }
            if d < 365 { s.yearSeconds += sec } else if d < 730 { s.yearPrevSeconds += sec }
        }

        return s
    }

    private static func currentStreak(playedDays: Set<Date>, today: Date, cal: Calendar) -> Int {
        var streak = 0
        var cursor = today
        // Allow the streak to be "alive" if you played today OR yesterday.
        if !playedDays.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor), playedDays.contains(y) else { return 0 }
            cursor = y
        }
        while playedDays.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private static func bestStreak(playedDays: Set<Date>, cal: Calendar) -> Int {
        guard !playedDays.isEmpty else { return 0 }
        let sorted = playedDays.sorted()
        var best = 1, run = 1
        for i in 1..<sorted.count {
            if let next = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]), next == sorted[i] {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
        }
        return best
    }
}

// MARK: - Formatting helpers

enum StatFormat {
    /// Compact hours/minutes for chart labels and tiles: "0m", "42m", "3.5h", "128h".
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0m" }
        let hours = seconds / 3600
        if hours < 1 { return "\(Int((seconds / 60).rounded()))m" }
        if hours < 10 { return String(format: "%.1fh", hours) }
        return "\(Int(hours.rounded()))h"
    }

    /// "1,240" grouped counts.
    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
