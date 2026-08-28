import SwiftUI

/// Nimbus display type.
///
/// One modern, expanded-width system face (SF Pro Expanded) is used everywhere the UI wants to
/// feel premium — the focused game title and the standby clock — so the whole app reads as a
/// single typographic system instead of the old rounded-vs-Avenir mix.
extension Font {
    /// Big, wide title face: the focused game name and standby headings.
    static func nimbusDisplay(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    /// Wide label/eyebrow face for small uppercase text that sits above the display type.
    static func nimbusLabel(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
}
