import SwiftUI

/// A local person on this Mac. Each profile owns its own library, folders, settings, play
/// history, and look (avatar color + UI accent) — PS5-style. Cosmetic per-game assets
/// (custom art, themes) stay shared across profiles, since they're keyed by game id.
struct Profile: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Index into `AvatarPalette` for the gradient bubble.
    var colorIndex: Int = 0
    /// Index into `AccentPalette` for the whole-app accent this profile prefers.
    var accentIndex: Int = 0
    /// Optional SF Symbol drawn over the avatar instead of an initial (a chosen "face").
    var symbol: String?
    var createdAt: Date = Date()

    var initial: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "P" : String(letters).uppercased()
    }
}

/// What the boot flow does after the "press to enter" screen.
enum BootBehavior: String, Codable, CaseIterable {
    case select      // always show the profile switcher
    case auto        // jump straight into the last-used profile

    var label: String { self == .select ? "Choose Profile" : "Last Profile" }
}

/// Global app state that isn't tied to a single profile. Lives in `app.json` at the support
/// root, beside the shared catalog and custom-asset stores.
struct AppConfig: Codable {
    var profiles: [Profile] = []
    var lastProfileID: String?
    var bootBehavior: BootBehavior = .select
    /// Minutes of no input before the standby screensaver takes over.
    var standbyMinutes: Int = 10
    /// Set once the first-run flow finishes, so it never runs again.
    var onboardingComplete: Bool = false
}

/// One completed play session, appended to the active profile's `history.json` when a game's
/// GFN stream ends. Feeds the stats dashboard's trends, heatmaps, and streaks.
struct PlaySession: Codable, Hashable {
    let gameID: Int
    let title: String
    let start: Date
    let seconds: TimeInterval
}

// MARK: - Accent palette

/// The whole-app accent color, chosen per profile. Kept saturated so it reads over the dark
/// silk background and against white focus rings. `current` mirrors the active profile's pick
/// for the handful of plain helper views that can't reach the model.
enum AccentPalette {
    struct Option: Identifiable, Hashable {
        let id: Int
        let name: String
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    static let options: [Option] = [
        Option(id: 0, name: "Aurora",  hue: 0.52, saturation: 0.82, brightness: 1.00),
        Option(id: 1, name: "Cobalt",  hue: 0.60, saturation: 0.80, brightness: 1.00),
        Option(id: 2, name: "Violet",  hue: 0.74, saturation: 0.70, brightness: 1.00),
        Option(id: 3, name: "Fuchsia", hue: 0.87, saturation: 0.70, brightness: 1.00),
        Option(id: 4, name: "Ember",   hue: 0.02, saturation: 0.78, brightness: 1.00),
        Option(id: 5, name: "Amber",   hue: 0.10, saturation: 0.85, brightness: 1.00),
        Option(id: 6, name: "Lime",    hue: 0.34, saturation: 0.75, brightness: 0.95),
        Option(id: 7, name: "Mint",    hue: 0.44, saturation: 0.72, brightness: 0.98),
    ]

    static func option(_ index: Int) -> Option {
        options[((index % options.count) + options.count) % options.count]
    }

    /// The main accent color for an index.
    static func color(_ index: Int) -> Color {
        let o = option(index)
        return Color(hue: o.hue, saturation: o.saturation, brightness: o.brightness)
    }

    /// A slightly deeper partner color, for gradients (bright → deep).
    static func deep(_ index: Int) -> Color {
        let o = option(index)
        return Color(hue: (o.hue + 0.05).truncatingRemainder(dividingBy: 1),
                     saturation: min(1, o.saturation + 0.12),
                     brightness: o.brightness * 0.72)
    }

    static func gradient(_ index: Int) -> [Color] { [color(index), deep(index)] }

    /// Mirror of the active profile's accent, updated on profile activation. Static so the
    /// occasional plain `View` (e.g. the launch-burst ring) can tint itself without the model.
    static var current: Color = color(0)
    static var currentIndex: Int = 0
}

// MARK: - Avatar palette

/// Two-stop gradients for profile / player avatars. Distinct from the UI accent so a person
/// can have a green bubble but a cyan interface, like console avatars.
enum AvatarPalette {
    private static let pairs: [(Double, Double)] = [
        (0.58, 0.72),   // teal → indigo (the app's original)
        (0.60, 0.50),   // blue
        (0.75, 0.85),   // violet → magenta
        (0.92, 0.02),   // pink → red
        (0.07, 0.13),   // orange → gold
        (0.33, 0.42),   // green → teal
        (0.50, 0.62),   // cyan → blue
        (0.83, 0.92),   // purple → pink
    ]

    static var count: Int { pairs.count }

    static func gradient(_ index: Int) -> LinearGradient {
        let (a, b) = pairs[((index % pairs.count) + pairs.count) % pairs.count]
        return LinearGradient(
            colors: [Color(hue: a, saturation: 0.72, brightness: 0.92),
                     Color(hue: b, saturation: 0.72, brightness: 0.70)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Gradient avatar bubble for a profile — the switcher, the top-bar chip, onboarding, and the
/// stats header all draw the same face so identity stays consistent.
struct ProfileAvatar: View {
    let name: String
    var colorIndex: Int = 0
    var symbol: String?
    var size: CGFloat = 64
    var ringed: Bool = false
    var ringColor: Color = .white

    var body: some View {
        Circle()
            .fill(AvatarPalette.gradient(colorIndex))
            .frame(width: size, height: size)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(ProfileInitial.of(name))
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle().strokeBorder(ringColor.opacity(ringed ? 0.95 : 0), lineWidth: size * 0.05)
            }
            .shadow(color: .black.opacity(0.4), radius: size * 0.12, y: size * 0.04)
    }
}

enum ProfileInitial {
    static func of(_ name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "P" : String(letters).uppercased()
    }
}
