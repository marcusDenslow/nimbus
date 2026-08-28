import SwiftUI

/// Black-and-white futuristic background: a stack of flowing horizontal contour lines that
/// ripple like a wireframe silk sheet. Each line is a sum of continuous sine/cosine terms
/// phase-offset from its neighbours, so the field loops forever with no seam and stays
/// brightest through the vertical centre. Shared by boot, standby, profile, empty-shelf.
struct CinematicBackground: View {
    private let lineCount = 46

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                let W = size.width, H = size.height
                let cy = H / 2
                let step: CGFloat = 8
                let gap = (H * 1.25) / CGFloat(lineCount)   // overscan top + bottom
                let yStart = -H * 0.12
                let amp = min(1.4, H / 900)                 // keep the tightness across window sizes

                for i in 0..<lineCount {
                    let fi = Double(i)
                    let baseY = yStart + CGFloat(i) * gap

                    var path = Path()
                    var x: CGFloat = -step
                    while x <= W + step {
                        let nx = Double(x / max(1, W))
                        let y = Double(baseY) + amp * (
                              sin(nx * 6.2  + t * 0.60 + fi * 0.35) * 26
                            + sin(nx * 3.1  - t * 0.45 + fi * 0.18) * 40
                            + cos(nx * 11.0 + t * 0.90 - fi * 0.22) * 10)
                        let p = CGPoint(x: x, y: CGFloat(y))
                        if path.isEmpty { path.move(to: p) } else { path.addLine(to: p) }
                        x += step
                    }

                    // Brighter toward the vertical centre, fainter at the edges.
                    let edge = max(0, 1 - abs((baseY - cy) / (H * 0.6)))
                    ctx.stroke(path,
                        with: .color(.white.opacity(0.06 + 0.32 * edge)),
                        lineWidth: 1 + 0.6 * edge)
                }

                // Vignette to seat the field in the dark.
                let r = hypot(W, H) / 2
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [.clear, .black.opacity(0.55)]),
                    center: CGPoint(x: W / 2, y: H / 2),
                    startRadius: r * 0.45, endRadius: r))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// Palette for folder accent colors.
func folderAccent(_ index: Int?) -> Color {
    let hues: [Double] = [0.55, 0.33, 0.08, 0.92, 0.72, 0.0]
    let i = ((index ?? 0) % hues.count + hues.count) % hues.count
    return Color(hue: hues[i], saturation: 0.7, brightness: 0.95)
}
