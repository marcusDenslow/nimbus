import SwiftUI

/// The stats & insights dashboard. A scrolling wall of accent-themed charts built from the
/// active profile's library, play history, and warmed Steam detail. Controller: ↑/↓ step through
/// sections, ←/→ (or L1/R1) change the time range, Circle/Esc closes. Pointer scrolls + clicks.
struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    private var data: StatsData {
        StatsData.make(library: model.library, history: model.history, folders: model.folders,
                       range: model.statsRange, details: { StoreInfo.shared.cached($0) })
    }

    var body: some View {
        let data = data
        let accent = model.accent
        ZStack {
            CinematicBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        kpiGrid(data).id(0)
                        trendSection(data, accent: accent).id(1)
                        topGamesSection(data, accent: accent).id(2)
                        genreSection(data).id(3)
                        weekdaySection(data, accent: accent).id(4)
                        heatmapSection(data, accent: accent).id(5)
                        qualitySection(data, accent: accent).id(6)
                        footer
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 44)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.statsFocusIndex) { _, new in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(new, anchor: .top) }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Button { model.closeStats() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if let profile = model.activeProfile {
                ProfileAvatar(name: profile.name, colorIndex: profile.colorIndex,
                              symbol: profile.symbol, size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("STATS & INSIGHTS")
                    .font(.system(size: 11, weight: .bold)).tracking(3)
                    .foregroundStyle(.white.opacity(0.55))
                Text(model.playerName)
                    .font(.nimbusDisplay(30, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Spacer()
            rangeSelector
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 6) {
            ForEach(AppModel.StatsRange.allCases, id: \.self) { range in
                let active = model.statsRange == range
                Button { model.statsRange = range } label: {
                    Text(range.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(active ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(active ? AnyShapeStyle(model.accent) : AnyShapeStyle(.white.opacity(0.06)),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.black.opacity(0.3), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }

    // MARK: - KPI grid

    private func kpiGrid(_ data: StatsData) -> some View {
        let accent = model.accent
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
        return LazyVGrid(columns: columns, spacing: 14) {
            StatTile(value: StatFormat.duration(data.totalSeconds), caption: "Total Playtime",
                     systemImage: "clock.fill", accent: accent)
            StatTile(value: StatFormat.duration(data.rangeSeconds), caption: "In \(model.statsRange.label)",
                     systemImage: "calendar", accent: accent)
            StatTile(value: "\(data.gamesCount)", caption: "Games", systemImage: "square.grid.2x2.fill", accent: accent)
            StatTile(value: "\(data.playedCount)", caption: "Played", systemImage: "play.fill", accent: accent)
            StatTile(value: "\(data.favoritesCount)", caption: "Favorites", systemImage: "heart.fill", accent: accent)
            StatTile(value: "\(data.sessionsCount)", caption: "Sessions", systemImage: "list.bullet", accent: accent)
            StatTile(value: StatFormat.duration(data.avgSessionSeconds), caption: "Avg Session",
                     systemImage: "timer", accent: accent)
            StatTile(value: "\(data.currentStreak)d", caption: "Current Streak",
                     systemImage: "flame.fill", accent: accent)
        }
    }

    // MARK: - Sections

    private func trendSection(_ data: StatsData, accent: Color) -> some View {
        DashCard(title: "Playtime Trend", subtitle: model.statsRange.label, accent: accent) {
            TrendChart(values: data.trend, accent: accent)
        }
    }

    private func topGamesSection(_ data: StatsData, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                PeriodCard(title: "Weekly", period: "week", systemImage: "calendar",
                           iconColor: Color(red: 0.94, green: 0.32, blue: 0.55),
                           seconds: data.weekSeconds, prevSeconds: data.weekPrevSeconds)
                PeriodCard(title: "Monthly", period: "month", systemImage: "sparkles",
                           iconColor: TreemapPalette.green,
                           seconds: data.monthSeconds, prevSeconds: data.monthPrevSeconds)
                PeriodCard(title: "Yearly", period: "year", systemImage: "stopwatch.fill",
                           iconColor: Color(red: 0.98, green: 0.78, blue: 0.22),
                           seconds: data.yearSeconds, prevSeconds: data.yearPrevSeconds)
            }
            TreemapChart(items: data.topGames.map {
                TreemapChart.Item(id: $0.game.id, value: $0.seconds, label: StatFormat.duration($0.seconds), game: $0.game)
            })
            .frame(height: 380)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }

    private func genreSection(_ data: StatsData) -> some View {
        DashCard(title: "Genres", subtitle: data.totalSeconds > 0 ? "By playtime" : "By library", accent: model.accent) {
            GenreOrbit(slices: data.genres, accentIndex: model.accentIndex)
        }
    }

    private func weekdaySection(_ data: StatsData, accent: Color) -> some View {
        DashCard(title: "Weekly Rhythm", subtitle: "By day, split by game", accent: accent) {
            StackedWeekday(days: data.weekdayGames, totals: data.weekday,
                           labels: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        }
    }

    private func heatmapSection(_ data: StatsData, accent: Color) -> some View {
        DashCard(title: "When You Play", subtitle: "Day × hour", accent: accent) {
            Heatmap(grid: data.heatmap, peak: data.peakHeatSeconds, accent: accent)
        }
    }

    private func qualitySection(_ data: StatsData, accent: Color) -> some View {
        DashCard(title: "Library Quality", subtitle: "From Steam", accent: accent) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    StatTile(value: data.avgMetacritic.map { "\($0)" } ?? "—", caption: "Avg Metacritic",
                             systemImage: "star.fill", accent: accent)
                    StatTile(value: data.totalReviews > 0 ? StatFormat.count(data.totalReviews) : "—",
                             caption: "Steam Reviews", systemImage: "bubble.left.fill", accent: accent)
                    StatTile(value: data.newest.map { "\($0.year)" } ?? "—", caption: "Newest", accent: accent)
                    StatTile(value: data.oldest.map { "\($0.year)" } ?? "—", caption: "Oldest", accent: accent)
                }
                if !data.releaseYears.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RELEASE YEARS").font(.system(size: 10.5, weight: .bold)).tracking(2)
                            .foregroundStyle(.white.opacity(0.5))
                        BarColumns(values: data.releaseYears.map(\.value),
                                   labels: data.releaseYears.map { "'" + String($0.name.suffix(2)) },
                                   accent: accent, height: 110,
                                   tooltip: { i, v in
                                       let n = Int(v.rounded())
                                       let year = data.releaseYears.indices.contains(i) ? data.releaseYears[i].name : ""
                                       return "\(year) · \(n) game\(n == 1 ? "" : "s")"
                                   })
                    }
                } else {
                    EmptyChartNote(text: "Release years and scores fill in from Steam as your library is read.")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 22) {
            if model.controllerConnected {
                Hint(text: "↑↓", label: "Sections")
                Hint(text: "L1 R1", label: "Range")
                Hint(symbol: "circle.circle.fill", label: "Back")
            } else {
                Hint(text: "↑↓", label: "Sections")
                Hint(text: "←→", label: "Range")
                Hint(text: "esc", label: "Back")
            }
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.top, 8)
    }
}
