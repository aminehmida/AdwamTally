import AppKit
import SwiftUI

/// Full-screen counting view: the active dhikr large over the chosen
/// background, with a ring filling toward its target.
struct FullscreenView: View {
    @ObservedObject var state: AppState
    @State private var pulse = false
    @State private var showHint = true

    var body: some View {
        GeometryReader { geo in
            // Everything scales off the screen's short side.
            let unit = min(geo.size.width, geo.size.height)
            ZStack {
                FullscreenBackdrop(style: state.settings.fullscreenBackground, tint: accentColor)
                    .ignoresSafeArea()
                FullscreenCounter(counter: state.active, unit: unit, pulse: pulse)
                hint(unit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .contentShape(Rectangle())
        .onTapGesture { state.increment() }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.6), value: state.active?.colorHex)
        .onChange(of: state.completionToken) { _, _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
        }
        .task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.easeOut(duration: 1.2)) { showHint = false }
        }
    }

    private func hint(_ unit: CGFloat) -> some View {
        Text("Esc to exit  ·  Space or click to count  ·  ← → to switch")
            .font(.system(size: max(12, unit * 0.017), weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.bottom, unit * 0.05)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(showHint ? 1 : 0)
    }

    private var accentColor: Color {
        if let c = state.active { return Color(hex: c.colorHex) }
        return .accentColor
    }
}

/// The label over a dial: the count, its target, and a progress ring for
/// counters that have one.
struct FullscreenCounter: View {
    var counter: Counter?
    var unit: CGFloat
    var pulse = false

    var body: some View {
        if let c = counter {
            VStack(spacing: unit * 0.05) {
                Text(c.label)
                    .font(.system(size: unit * 0.05, weight: .medium))
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, c.isRTL ? .rightToLeft : .leftToRight)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: unit * 1.1)

                dial(c)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.55), value: pulse)
            }
        } else {
            Text("No counters")
                .font(.system(size: unit * 0.04))
                .foregroundStyle(.secondary)
        }
    }

    private func dial(_ c: Counter) -> some View {
        let diameter = unit * 0.5
        let lineWidth = unit * 0.012
        let ringColor = c.isComplete ? Color.green : Color(hex: c.colorHex)
        return ZStack {
            if let t = c.target, t > 0 {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(1, Double(c.count) / Double(t)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.6), radius: unit * 0.02)
                    .animation(.easeOut(duration: 0.4), value: c.count)
            }

            VStack(spacing: 0) {
                Text("\(c.count)")
                    .font(.system(size: unit * 0.16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(c.isComplete ? AnyShapeStyle(Color.green) : AnyShapeStyle(.white))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: c.count)
                if let t = c.target, t > 0 {
                    Text("/ \(t)")
                        .font(.system(size: unit * 0.045, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: diameter * 0.8)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Backgrounds

/// The full-screen background in the chosen style, themed by the active
/// counter's color. Also drawn small as the previews in Settings.
struct FullscreenBackdrop: View {
    var style: FullscreenBackground
    var tint: Color

    var body: some View {
        switch style {
        case .pattern: PatternBackdrop(tint: tint)
        case .aurora: AuroraBackdrop(tint: tint)
        case .frosted: FrostedBackdrop(tint: tint)
        case .nightSky: NightSkyBackdrop(tint: tint)
        }
    }
}

/// Near-black with a glow of the dhikr's color and the naqsh tile over it.
private struct PatternBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            Color(white: 0.035)
            Glow(tint: tint, intensity: 0.42, reach: 0.7)
            if let img = PatternTile.image {
                GeometryReader { geo in
                    // Shrink the tile in the small Settings previews so they
                    // show the pattern, not a close-up of one motif.
                    let k = detailScale(for: geo.size)
                    Image(nsImage: img)
                        .renderingMode(.template)
                        .resizable(resizingMode: .tile)
                        .frame(width: geo.size.width / k, height: geo.size.height / k)
                        .scaleEffect(k, anchor: .topLeading)
                }
                .foregroundStyle(tint)
                .opacity(0.16)
                .mask {
                    EllipticalGradient(colors: [.white, .white.opacity(0.3)],
                                       startRadiusFraction: 0, endRadiusFraction: 0.75)
                }
            }
            Vignette()
        }
    }
}

/// Soft blobs of the dhikr's color and two hue-shifted neighbours, drifting
/// slowly. Moved with repeating SwiftUI animations rather than redrawn per
/// frame, so it stays cheap at full-screen size.
private struct AuroraBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            Color(white: 0.02)
            Rectangle().fill(tint)
                .mask {
                    ZStack {
                        AuroraBlob(size: 0.9, from: UnitPoint(x: 0.2, y: 0.3),
                                   to: UnitPoint(x: 0.45, y: 0.65), period: 19)
                        AuroraBlob(size: 0.7, from: UnitPoint(x: 0.85, y: 0.75),
                                   to: UnitPoint(x: 0.6, y: 0.3), period: 23)
                    }
                }
                .opacity(0.55)
            Rectangle().fill(tint)
                .hueRotation(.degrees(40))
                .mask {
                    AuroraBlob(size: 0.8, from: UnitPoint(x: 0.75, y: 0.15),
                               to: UnitPoint(x: 0.3, y: 0.8), period: 29)
                }
                .opacity(0.4)
            Rectangle().fill(tint)
                .hueRotation(.degrees(-40))
                .mask {
                    AuroraBlob(size: 0.6, from: UnitPoint(x: 0.15, y: 0.85),
                               to: UnitPoint(x: 0.8, y: 0.2), period: 31)
                }
                .opacity(0.35)
            Vignette()
        }
    }
}

/// A soft white disc (used as a mask) gliding between two points.
private struct AuroraBlob: View {
    /// Diameter as a fraction of the container's long side.
    var size: CGFloat
    var from: UnitPoint
    var to: UnitPoint
    var period: Double
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height) * size
            let p = moved ? to : from
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
                .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                moved = true
            }
        }
    }
}

/// Whatever is behind the window, blurred and dimmed.
private struct FrostedBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            BehindWindowBlur()
            Color.black.opacity(0.35)
            Glow(tint: tint, intensity: 0.25, reach: 0.7)
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        // Stay blurred even though the app is never the active one.
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Navy fading to black overhead, twinkling stars, and a horizon glow in the
/// dhikr's color.
private struct NightSkyBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.015, blue: 0.05),
                                    Color(red: 0.03, green: 0.05, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(Starfield.groups.indices, id: \.self) { i in
                StarLayer(stars: Starfield.groups[i], period: Starfield.periods[i])
            }
            Glow(tint: tint, center: UnitPoint(x: 0.5, y: 1.1), intensity: 0.85, reach: 0.6)
        }
    }
}

private struct Star {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var alpha: Double
}

private enum Starfield {
    /// A fixed, seeded sky so the stars don't move between sessions. Split
    /// into groups that fade in and out of phase with each other, which reads
    /// as twinkling without animating each star.
    static let groups: [[Star]] = {
        var rng = SplitMix64(seed: 0xAD3A)
        var groups: [[Star]] = Array(repeating: [], count: periods.count)
        for i in 0..<300 {
            // Denser overhead, thinning toward the horizon glow.
            let y = pow(CGFloat.random(in: 0...1, using: &rng), 1.5) * 0.85
            let star = Star(x: .random(in: 0...1, using: &rng),
                            y: y,
                            radius: .random(in: 0.6...1.6, using: &rng),
                            alpha: .random(in: 0.4...1, using: &rng))
            groups[i % groups.count].append(star)
        }
        return groups
    }()

    static let periods: [Double] = [3.1, 4.7, 6.3]
}

private struct StarLayer: View {
    var stars: [Star]
    var period: Double
    @State private var dim = false

    var body: some View {
        Canvas { ctx, size in
            // Fewer, smaller stars when drawn small (the Settings preview).
            let count = min(stars.count, max(12, Int(size.width * size.height / 9000)))
            let k = detailScale(for: size)
            for s in stars.prefix(count) {
                let center = CGPoint(x: s.x * size.width, y: s.y * size.height)
                if s.radius > 1.4 {
                    // A faint halo on the biggest few.
                    let r = s.radius * 4 * k
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(s.alpha * 0.12)))
                }
                let r = s.radius * k
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white.opacity(s.alpha)))
            }
        }
        .opacity(dim ? 0.3 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                dim = true
            }
        }
    }
}

/// Deterministic generator for the star layout.
private struct SplitMix64: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The dhikr's color fading out from `center`. A masked fill rather than a
/// gradient of the color itself, so switching dhikr animates the color.
private struct Glow: View {
    var tint: Color
    var center: UnitPoint = .center
    var intensity: Double
    /// Where the glow fades out, as a fraction of the view's size.
    var reach: CGFloat

    var body: some View {
        Rectangle().fill(tint)
            .mask {
                EllipticalGradient(colors: [.white.opacity(intensity), .white.opacity(intensity * 0.25), .clear],
                                   center: center, startRadiusFraction: 0, endRadiusFraction: reach)
            }
    }
}

/// 1 at full-screen sizes, shrinking fine detail (pattern tile, stars) when a
/// background is drawn as a small preview.
private func detailScale(for size: CGSize) -> CGFloat {
    min(1, max(0.4, size.width / 1000))
}

/// Darkens the corners to keep the eye on the count.
private struct Vignette: View {
    var body: some View {
        EllipticalGradient(colors: [.clear, .black.opacity(0.65)],
                           startRadiusFraction: 0.25, endRadiusFraction: 0.8)
    }
}
