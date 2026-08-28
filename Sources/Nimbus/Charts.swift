import SwiftUI

extension CGFloat {
    func finiteOr(_ fallback: CGFloat) -> CGFloat { isFinite ? self : fallback }
}

/// Hand-rolled, accent-themed chart primitives for the stats dashboard. Everything is drawn
/// from SwiftUI shapes so it inherits the app's exact look (materials, fonts, accent) and adds
/// no dependencies. Each piece is pure — hand it data, an accent, and it draws.

/// Harmonious categorical colors fanned out from the profile's accent hue.
enum StatPalette {
    static func colors(_ n: Int, accentIndex: Int) -> [Color] {
        let base = AccentPalette.option(accentIndex).hue
        return (0..<max(1, n)).map { i in
            let hue = (base + Double(i) * 0.13).truncatingRemainder(dividingBy: 1)
            let bright = 0.98 - Double(i % 3) * 0.08
            return Color(hue: hue, saturation: 0.66, brightness: bright)
        }
    }
}

// MARK: - Hover tooltips

/// A small floating label that follows the pointer inside a chart. Each chart keeps two boxes —
/// the current label (nil = hidden) and the pointer location — and its elements set the label on
/// their own `.onHover`. Pointer tracking + the bubble itself live in the `.chartHover` modifier.
struct TooltipBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.black.opacity(0.75), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
    }
}

private struct ChartHover: ViewModifier {
    @ObservedObject var text: ViewState<String?>
    @ObservedObject var loc: ViewState<CGPoint>

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): loc.value = p
                case .ended: text.value = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let t = text.value {
                    TooltipBubble(text: t)
                        .allowsHitTesting(false)
                        .position(x: loc.value.x, y: max(16, loc.value.y - 26))
                }
            }
            .animation(.easeOut(duration: 0.12), value: text.value)
    }
}

extension View {
    /// Track the pointer and float a tooltip over this chart. Elements inside set `text.value`
    /// on hover; the pointer leaving the chart clears it.
    func chartHover(_ text: ViewState<String?>, _ loc: ViewState<CGPoint>) -> some View {
        modifier(ChartHover(text: text, loc: loc))
    }
}

/// Translucent rounded section container for the dashboard.
struct DashCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var accent: Color = .white
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 11.5, weight: .bold)).tracking(2.5)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.9))
                }
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .black.opacity(0.38), in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(
            .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                .white.opacity(0.08)))
    }
}

/// A single KPI stat: big value, small caption, optional icon + accent.
struct StatTile: View {
    let value: String
    let caption: String
    var systemImage: String?
    var accent: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption.uppercased())
                .font(.system(size: 10.5, weight: .bold)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                .white.opacity(0.07)))
    }
}

/// Filled area + line trend of per-day playtime.
struct TrendChart: View {
    let values: [DayValue]
    let accent: Color
    var height: CGFloat = 170

    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    private var maxV: Double { max(values.map(\.seconds).max() ?? 0, 1) }

    var body: some View {
        if values.allSatisfy({ $0.seconds == 0 }) {
            EmptyChartNote(
                text: "No play logged in this range yet — your trend fills in as you play."
            )
            .frame(height: height)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let n = max(values.count - 1, 1)
                    let pts = values.enumerated().map { i, d in
                        CGPoint(
                            x: (w * CGFloat(i) / CGFloat(n)).finiteOr(0),
                            y: (h - CGFloat(d.seconds / maxV) * (h - 6) - 3).finiteOr(h))
                    }
                    ZStack {
                        // horizontal guides
                        ForEach(0..<3, id: \.self) { i in
                            let y = h * CGFloat(i) / 2
                            Path {
                                $0.move(to: CGPoint(x: 0, y: y))
                                $0.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                        }
                        areaPath(pts, w: w, h: h)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.42), accent.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom))
                        linePath(pts)
                            .stroke(
                                accent,
                                style: StrokeStyle(
                                    lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        // last-point dot
                        if let last = pts.last {
                            Circle().fill(accent).frame(width: 7, height: 7).position(last)
                                .shadow(color: accent.opacity(0.6), radius: 6)
                        }
                        // one transparent hit column per day, for the hover tooltip
                        HStack(spacing: 0) {
                            ForEach(values.indices, id: \.self) { i in
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .onHover {
                                        if $0 {
                                            hoverText.value =
                                                "\(rangeLabel(values[i].date)) · \(StatFormat.duration(values[i].seconds))"
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(height: height)
                .chartHover(hoverText, hoverLoc)

                HStack {
                    Text(rangeLabel(values.first?.date)).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("Peak \(StatFormat.duration(maxV))").font(
                        .system(size: 11, weight: .semibold)
                    )
                    .foregroundStyle(accent.opacity(0.9))
                    Spacer()
                    Text(rangeLabel(values.last?.date)).font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func areaPath(_ pts: [CGPoint], w: CGFloat, h: CGFloat) -> Path {
        var p = linePath(pts)
        guard let first = pts.first, let last = pts.last else { return p }
        p.addLine(to: CGPoint(x: last.x, y: h))
        p.addLine(to: CGPoint(x: first.x, y: h))
        p.closeSubpath()
        return p
    }

    private func rangeLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

/// Horizontal ranked bars — top games (with a cover) or any labelled series.
struct RankedBars: View {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let value: Double
        let game: Game?
    }
    let rows: [Row]
    let accent: Color

    private var maxV: Double { max(rows.map(\.value).max() ?? 1, 1) }

    var body: some View {
        if rows.isEmpty {
            EmptyChartNote(text: "Play a few games and your top titles rank here.")
        } else {
            VStack(spacing: 12) {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 18, alignment: .trailing)
                        if let game = row.game {
                            BoxArt(game: game)
                                .frame(width: 30, height: 45)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.title).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            GeometryReader { geo in
                                Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [accent, accent.opacity(0.6)],
                                                startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(
                                            width: max(
                                                6, geo.size.width * CGFloat(row.value / maxV)))
                                }
                            }
                            .frame(height: 7)
                        }
                        Text(StatFormat.duration(row.value))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// Genres as a single ring of glowing points — one hue per genre, each genre claiming a share of
/// the ring in proportion to its playtime. The focal centrepiece of the genre card: big, centred,
/// count in the hub, legend below. Points fan in around the ring on appear.
struct GenreOrbit: View {
    let slices: [CategoryStat]
    let accentIndex: Int

    /// Points on the ring. Enough to render smooth proportional arcs for up to 8 genres.
    private let dotCount = 60
    // `@State` can't compile without full Xcode (SwiftUIMacros); ViewState is the app's stand-in.
    @StateObject private var appear = ViewState(false)
    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 1) }

    var body: some View {
        if slices.isEmpty {
            EmptyChartNote(text: "Genre mix appears once your games carry genre data.")
        } else {
            let colors = StatPalette.colors(slices.count, accentIndex: accentIndex)
            let dots = assignment
            VStack(spacing: 28) {
                ZStack {
                    ring(dots: dots, colors: colors)
                    hub
                }
                .frame(width: 300, height: 300)
                .frame(maxWidth: .infinity)

                legend(colors: colors)
            }
            .frame(maxWidth: .infinity)
            .onAppear { appear.value = true }
        }
    }

    private func ring(dots: [Int], colors: [Color]) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 12
            ForEach(Array(dots.enumerated()), id: \.offset) { i, gi in
                let angle = Double(i) / Double(max(dots.count, 1)) * 2 * .pi - .pi / 2
                let color = colors.indices.contains(gi) ? colors[gi] : .white
                Circle()  // enlarged transparent hit target
                    .fill(.clear)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                    .overlay(
                        Circle().fill(color).frame(width: 11, height: 11)
                            .shadow(color: color.opacity(0.7), radius: 5)
                    )
                    .scaleEffect(appear.value ? 1 : 0.1)
                    .opacity(appear.value ? 1 : 0)
                    .position(
                        x: center.x + CGFloat(cos(angle)) * radius,
                        y: center.y + CGFloat(sin(angle)) * radius
                    )
                    .onHover {
                        if $0, slices.indices.contains(gi) {
                            hoverText.value =
                                "\(slices[gi].name) · \(Int((slices[gi].value / total * 100).rounded()))%"
                        }
                    }
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.012),
                        value: appear.value)
            }
        }
        .chartHover(hoverText, hoverLoc)
    }

    private var hub: some View {
        VStack(spacing: 3) {
            Text("\(slices.count)")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("GENRES")
                .font(.system(size: 10, weight: .bold)).tracking(2.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .scaleEffect(appear.value ? 1 : 0.8)
        .opacity(appear.value ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.18), value: appear.value)
    }

    private func legend(colors: [Color]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 18, alignment: .leading),
            GridItem(.flexible(), spacing: 18, alignment: .leading),
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 11) {
            ForEach(Array(slices.prefix(8).enumerated()), id: \.element.id) { i, slice in
                HStack(spacing: 9) {
                    Circle().fill(colors[i]).frame(width: 10, height: 10)
                        .shadow(color: colors[i].opacity(0.6), radius: 3)
                    Text(slice.name).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int((slice.value / total * 100).rounded()))%")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(
                            .white.opacity(0.55))
                }
            }
        }
    }

    /// One genre index per ring dot. Floor each genre's proportional share, guarantee every genre
    /// with any weight at least one dot, then hand the leftover dots to the largest fractional
    /// remainders (largest-remainder apportionment) so the ring stays proportional.
    private var assignment: [Int] {
        let raw = slices.map { Double(dotCount) * $0.value / total }
        var counts = raw.map { Int($0.rounded(.down)) }
        for i in counts.indices where counts[i] == 0 && slices[i].value > 0 { counts[i] = 1 }
        var remaining = dotCount - counts.reduce(0, +)
        if remaining > 0 {
            let order = raw.enumerated()
                .sorted {
                    ($0.element - $0.element.rounded(.down))
                        > ($1.element - $1.element.rounded(.down))
                }
                .map(\.offset)
            var k = 0
            while remaining > 0 {
                counts[order[k % order.count]] += 1
                remaining -= 1
                k += 1
            }
        } else if remaining < 0 {
            let order = counts.enumerated().sorted { $0.element > $1.element }.map(\.offset)
            var k = 0
            while remaining < 0 && k < dotCount * 4 {
                let i = order[k % order.count]
                if counts[i] > 1 {
                    counts[i] -= 1
                    remaining += 1
                }
                k += 1
            }
        }
        var out: [Int] = []
        for (gi, c) in counts.enumerated() { out += Array(repeating: gi, count: c) }
        return out
    }
}

/// Vertical bar columns with per-bar labels (weekday activity).
struct BarColumns: View {
    let values: [Double]
    let labels: [String]
    let accent: Color
    var height: CGFloat = 150
    /// How a bar's value reads in the hover tooltip (release-year counts vs. anything else).
    var tooltip: (Int, Double) -> String = { _, v in "\(Int(v.rounded()))" }

    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    private var maxV: Double { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 8) {
                    Text(v > 0 ? StatFormat.duration(v) : "")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.5)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .frame(height: max(3, CGFloat(v / maxV) * height))
                        .onHover { if $0 { hoverText.value = tooltip(i, v) } }
                    Text(labels.indices.contains(i) ? labels[i] : "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 44)
        .chartHover(hoverText, hoverLoc)
    }
}

/// Weekly rhythm as stacked columns: each day's bar is as tall as that day's total playtime, and
/// splits into one segment per game — coloured by the game's stable hue, sized by how long that
/// game was played that day. No average line; the length *is* the hours. Bars grow up on appear,
/// staggered across the week.
struct StackedWeekday: View {
    let days: [[GameStat]]  // [7], each already sorted desc by seconds
    let totals: [Double]  // [7]
    let labels: [String]
    var height: CGFloat = 240
    private let maxSegments = 6
    private let barWidth: CGFloat = 24
    private let axisWidth: CGFloat = 46
    private let colSpacing: CGFloat = 10

    // `@State` can't compile without full Xcode (SwiftUIMacros); ViewState is the app's stand-in.
    @StateObject private var grow = ViewState(false)
    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    /// The chart's vertical scale = the busiest day's total. So the whole chart "zooms" to whatever
    /// the peak day is, and the top axis tick always reads that peak.
    private var maxV: Double { max(totals.max() ?? 1, 1) }

    /// Evenly spaced axis marks from 0 up to the peak day total.
    private var ticks: [Double] {
        let steps = 4
        return (0...steps).map { maxV * Double($0) / Double(steps) }
    }

    var body: some View {
        if totals.allSatisfy({ $0 <= 0 }) {
            EmptyChartNote(text: "Play across the week and each day stacks up here, split by game.")
        } else {
            HStack(alignment: .top, spacing: 10) {
                yAxis
                plot
            }
            .onAppear { grow.value = true }
            .chartHover(hoverText, hoverLoc)
        }
    }

    // Left axis: hour totals, auto-scaled so the top tick is the peak day.
    private var yAxis: some View {
        GeometryReader { g in
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                let y = min(max((1 - CGFloat(t / maxV)) * g.size.height, 8), g.size.height - 6)
                Text(StatFormat.duration(t))
                    .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: axisWidth - 6, alignment: .trailing)
                    .position(x: (axisWidth - 6) / 2, y: y)
            }
        }
        .frame(width: axisWidth, height: height)
    }

    private var plot: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .bottom) {
                gridlines
                HStack(alignment: .bottom, spacing: colSpacing) {
                    ForEach(0..<min(7, totals.count), id: \.self) { i in barColumn(i) }
                }
            }
            .frame(height: height)
            HStack(spacing: colSpacing) {
                ForEach(0..<min(7, labels.count), id: \.self) { i in
                    Text(labels[i])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var gridlines: some View {
        GeometryReader { g in
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                let y = (1 - CGFloat(t / maxV)) * g.size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
                .stroke(.white.opacity(t == 0 ? 0.14 : 0.06), lineWidth: 1)
            }
        }
    }

    private func barColumn(_ i: Int) -> some View {
        let colH = CGFloat(totals[i] / maxV) * height
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.035))
                .frame(width: barWidth, height: height)
            VStack(spacing: 2) {
                ForEach(Array(segments(i).enumerated()), id: \.offset) { _, seg in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(seg.color)
                        .frame(height: seg.height)
                        .shadow(color: seg.color.opacity(0.5), radius: 3)
                        .onHover { if $0 { hoverText.value = seg.label } }
                }
            }
            .frame(width: barWidth, height: colH, alignment: .bottom)
            .scaleEffect(x: 1, y: grow.value ? 1 : 0, anchor: .bottom)
            .opacity(grow.value ? 1 : 0)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.78).delay(Double(i) * 0.05),
                value: grow.value)
        }
        .frame(maxWidth: .infinity)
    }

    private struct Seg {
        let color: Color
        let height: CGFloat
        let label: String
    }

    /// The stacked segments for day `i`, tallest game at the bottom. Beyond `maxSegments` the tail
    /// collapses into one muted "others" block so busy days stay legible.
    private func segments(_ i: Int) -> [Seg] {
        guard totals.indices.contains(i), totals[i] > 0, days.indices.contains(i) else { return [] }
        let scale = height / CGFloat(maxV)
        let list = days[i]
        func h(_ seconds: TimeInterval) -> CGFloat { max(3, CGFloat(seconds) * scale) }
        func seg(_ s: GameStat) -> Seg {
            Seg(
                color: gameColor(s.game), height: h(s.seconds),
                label: "\(s.game.title) · \(StatFormat.duration(s.seconds))")
        }
        if list.count > maxSegments {
            let head = list.prefix(maxSegments - 1)
            let tail = list.dropFirst(maxSegments - 1).reduce(0.0) { $0 + $1.seconds }
            return head.map(seg)
                + [
                    Seg(
                        color: .white.opacity(0.22), height: h(tail),
                        label:
                            "\(list.count - (maxSegments - 1)) more · \(StatFormat.duration(tail))")
                ]
        }
        return list.map(seg)
    }

    private func gameColor(_ game: Game) -> Color {
        Color(hue: game.stableHue, saturation: 0.72, brightness: 0.92)
    }
}

/// Weekday × hour intensity grid.
struct Heatmap: View {
    let grid: [[Double]]  // [7][24]
    let peak: Double
    let accent: Color

    private let rowLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let hourTicks = [0, 6, 12, 18, 23]

    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    var body: some View {
        if peak <= 0 {
            EmptyChartNote(text: "When you play, a weekly rhythm shows up here.")
        } else {
            VStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { r in
                    HStack(spacing: 3) {
                        Text(rowLabels[r]).font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4)).frame(width: 14)
                        ForEach(0..<24, id: \.self) { c in
                            let v =
                                grid.indices.contains(r) && grid[r].indices.contains(c)
                                ? grid[r][c] : 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(accent.opacity(v <= 0 ? 0.05 : 0.18 + 0.82 * (v / peak)))
                                .frame(height: 15)
                                .frame(maxWidth: .infinity)
                                .onHover {
                                    if $0 {
                                        hoverText.value =
                                            "\(dayNames[r]) \(hourLabel(c)) · \(StatFormat.duration(v))"
                                    }
                                }
                        }
                    }
                }
                HStack(spacing: 3) {
                    Spacer().frame(width: 14)
                    ForEach(0..<24, id: \.self) { c in
                        Text(hourTicks.contains(c) ? hourLabel(c) : "")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .chartHover(hoverText, hoverLoc)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        switch h {
        case 0: return "12a"
        case 12: return "12p"
        case 23: return "11p"
        default: return h < 12 ? "\(h)a" : "\(h - 12)p"
        }
    }
}

// MARK: - Treemap (Most Played)

/// The two-tone blob palette for the treemap. Kept distinct from the profile accent so the
/// green/purple "bubble" identity reads the same on every theme.
enum TreemapPalette {
    static let purple = Color(red: 0.49, green: 0.42, blue: 0.95)
    static let green = Color(red: 0.58, green: 0.89, blue: 0.33)
}

/// Squarified treemap (Bruls, Huizing & van Wijk). Given weights and a box, returns one rect per
/// weight (same order as the input), packed to keep every cell as close to square as possible —
/// so the biggest values land in near-square cells (drawn as circles) and the tail stretches into
/// pills. Weights must be > 0.
enum TreemapLayout {
    static func rects(_ weights: [Double], in bounds: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: weights.count)
        }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = weights.map { max($0 * scale, 0.0001) }
        var out = [CGRect](repeating: .zero, count: areas.count)
        var pending = Array(areas.enumerated())  // (originalIndex, area)
        var free = bounds
        var row: [(offset: Int, element: Double)] = []

        func worst(_ row: [(offset: Int, element: Double)], side: Double) -> Double {
            let a = row.map(\.element)
            let sum = a.reduce(0, +)
            let mx = a.max() ?? 0
            let mn = a.min() ?? 0
            guard sum > 0, mn > 0 else { return .greatestFiniteMagnitude }
            let s2 = sum * sum
            let side2 = side * side
            return max(side2 * mx / s2, s2 / (side2 * mn))
        }

        func place(_ row: [(offset: Int, element: Double)], in rect: inout CGRect) {
            let sum = row.reduce(0) { $0 + $1.element }
            if rect.width >= rect.height {  // lay a column down the left edge
                let colW = CGFloat(sum) / rect.height
                var y = rect.minY
                for (idx, area) in row {
                    let h = CGFloat(area) / colW
                    out[idx] = CGRect(x: rect.minX, y: y, width: colW, height: h)
                    y += h
                }
                rect = CGRect(
                    x: rect.minX + colW, y: rect.minY,
                    width: rect.width - colW, height: rect.height)
            } else {  // lay a row across the top edge
                let rowH = CGFloat(sum) / rect.width
                var x = rect.minX
                for (idx, area) in row {
                    let w = CGFloat(area) / rowH
                    out[idx] = CGRect(x: x, y: rect.minY, width: w, height: rowH)
                    x += w
                }
                rect = CGRect(
                    x: rect.minX, y: rect.minY + rowH,
                    width: rect.width, height: rect.height - rowH)
            }
        }

        while !pending.isEmpty {
            let side = Double(min(free.width, free.height))
            let candidate = pending[0]
            if row.isEmpty || worst(row, side: side) >= worst(row + [candidate], side: side) {
                row.append(candidate)
                pending.removeFirst()
            } else {
                place(row, in: &free)
                row = []
            }
        }
        if !row.isEmpty { place(row, in: &free) }
        return out
    }
}

/// One tile: a rounded square of the game's cover art, a two-tone accent border + glow so rank
/// tone still reads, and a playtime badge pinned to the bottom. The badge hides when the cell is tiny.
private struct TreemapCell: View {
    let rect: CGRect
    let color: Color
    let game: Game
    let label: String

    var body: some View {
        let r = rect.insetBy(dx: 5, dy: 5)  // gutter between neighbours
        let side = min(r.width, r.height)
        let corner = min(max(side * 0.16, 10), 26)  // rounded square, not a circle
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        BoxArt(game: game)
            .frame(width: r.width, height: r.height)
            .clipShape(shape)
            .overlay(  // darken the bottom so the badge reads
                shape.fill(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .center, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(color.opacity(0.9), lineWidth: 2))
            .overlay(alignment: .bottom) {
                if side >= 34 {
                    Text(label)
                        .font(
                            .system(
                                size: max(9, min(side * 0.15, 17)), weight: .bold, design: .rounded)
                        )
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, max(8, side * 0.1))
                        .padding(.vertical, max(5, side * 0.06))
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
            }
            .shadow(color: color.opacity(0.5), radius: side * 0.22)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }
}

/// The Most Played treemap: cover-art tiles sized by playtime, two-tone accents, biggest first.
struct TreemapChart: View {
    struct Item: Identifiable {
        let id: Int
        let value: Double
        let label: String
        let game: Game
    }
    let items: [Item]

    @StateObject private var hoverText = ViewState<String?>(nil)
    @StateObject private var hoverLoc = ViewState<CGPoint>(.zero)

    var body: some View {
        if items.isEmpty {
            EmptyChartNote(text: "Play a few games and your top titles bubble up here.")
        } else {
            let sorted = items.sorted { $0.value > $1.value }
            GeometryReader { geo in
                let rects = TreemapLayout.rects(
                    sorted.map(\.value),
                    in: CGRect(origin: .zero, size: geo.size))
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, item in
                    // Two purple, two green, repeating — mirrors the reference layout.
                    let color = (i / 2) % 2 == 0 ? TreemapPalette.purple : TreemapPalette.green
                    if i < rects.count {
                        TreemapCell(
                            rect: rects[i], color: color, game: item.game, label: item.label
                        )
                        .onHover {
                            if $0 { hoverText.value = "\(item.game.title) · \(item.label)" }
                        }
                    }
                }
            }
            .chartHover(hoverText, hoverLoc)
        }
    }
}

/// A hero KPI: icon + period name, big playtime, up/down delta vs. the previous period, and the
/// "compared to …" footnote. Matches the weekly/monthly/yearly row of the reference design.
struct PeriodCard: View {
    let title: String
    let period: String  // "week" / "month" / "year"
    let systemImage: String
    let iconColor: Color
    let seconds: Double
    let prevSeconds: Double

    private var delta: Double? {  // percent change; nil means "no prior data to compare"
        guard prevSeconds > 0 else { return nil }
        return (seconds - prevSeconds) / prevSeconds * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(iconColor)
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(StatFormat.duration(seconds))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let delta {
                    let up = delta >= 0
                    HStack(spacing: 1) {
                        Image(systemName: up ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .heavy))
                        Text(
                            "\(abs(delta) < 10 ? String(format: "%.1f", abs(delta)) : "\(Int(abs(delta).rounded()))")%"
                        )
                        .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(
                        up ? TreemapPalette.green : Color(red: 0.95, green: 0.35, blue: 0.4))
                } else if seconds > 0 {
                    Text("NEW").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TreemapPalette.green)
                }
            }
            Text("Compared to \(StatFormat.duration(prevSeconds)) last \(period)")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared "nothing here yet" note, kept gentle and on-brand.
struct EmptyChartNote: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 14))
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}
