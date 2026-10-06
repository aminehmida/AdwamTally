import AppKit
import SwiftUI

/// Lazily-loaded seamless Islamic pattern tile (bundled in Resources/naqsh.png).
enum PatternTile {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "naqsh", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()
}

/// The floating HUD content: dhikr label + current count, on a modern macOS
/// "Liquid Glass" card themed by the active counter's color.
struct OverlayView: View {
    @ObservedObject var state: AppState
    @State private var pulse = false

    var body: some View {
        let size = state.settings.popupSize
        content(size)
            .frame(minWidth: size.minWidth, maxWidth: size.maxContentWidth)
            .padding(.horizontal, size.padding * 1.3)
            .padding(.vertical, size.padding)
            .modifier(GlassCard(tint: accentColor, cornerRadius: size.cornerRadius,
                                showPattern: state.settings.showPattern,
                                patternOpacity: state.settings.patternOpacity,
                                backgroundOpacity: state.settings.backgroundOpacity,
                                showBorder: state.settings.showBorder))
            .scaleEffect(pulse ? 1.07 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: pulse)
            .padding(size.shadowMargin)   // room for the drop shadow
            .fixedSize(horizontal: false, vertical: true)  // bounded width, height fits
            .onChange(of: state.completionToken) { _, _ in
                pulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { pulse = false }
            }
    }

    @ViewBuilder
    private func content(_ size: PopupSize) -> some View {
        if let c = state.active {
            VStack(spacing: max(6, size.padding * 0.4)) {
                Text(c.label)
                    .font(.system(size: size.labelFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .environment(\.layoutDirection, c.isRTL ? .rightToLeft : .leftToRight)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(c.count)")
                        .font(.system(size: size.countFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(c.isComplete ? AnyShapeStyle(Color.green) : AnyShapeStyle(countGradient))
                        .contentTransition(.numericText())
                    if let t = c.target, t > 0 {
                        Text("/ \(t)")
                            .font(.system(size: size.countFontSize * 0.45, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    if c.isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: size.countFontSize * 0.4))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
        } else {
            Text("No counters")
                .font(.system(size: size.labelFontSize))
                .foregroundStyle(.secondary)
        }
    }

    private var accentColor: Color {
        if let c = state.active { return Color(hex: c.colorHex) }
        return .accentColor
    }

    private var countGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.75)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Applies a Liquid Glass background on macOS 26+, with a refined material
/// fallback on earlier systems.
private struct GlassCard: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat
    var showPattern: Bool
    var patternOpacity: Double
    var backgroundOpacity: Double
    var showBorder: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                // Real Liquid Glass: rendered at full strength so its specular
                // reflective edge stays crisp. Translucency rides on the tint's
                // alpha (scaled by the user's opacity slider), not a flattening
                // .opacity() over the whole layer.
                .background(glassBackground(shape))
                .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 9)
        } else {
            content
                .background(legacyBackground(shape).opacity(backgroundOpacity))
                .shadow(color: .black.opacity(0.22 * backgroundOpacity + 0.06),
                        radius: 16, x: 0, y: 8)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassBackground(_ shape: RoundedRectangle) -> some View {
        ZStack {
            // Only the glass lives inside the container; a plain tiled image
            // sibling gets swallowed by its compositing, so the pattern and rim
            // are layered over it here instead.
            GlassEffectContainer {
                Color.clear
                    .glassEffect(.regular.tint(tint.opacity(0.14 * backgroundOpacity)).interactive(),
                                 in: shape)
            }
            patternLayer(shape)
            specularEdge(shape)
        }
    }

    /// A bright, light-angled rim on top of the native glass so the reflective
    /// edge reads clearly even over static, low-contrast backgrounds — light
    /// catching the top-leading corner and easing off toward the bottom.
    @ViewBuilder
    private func specularEdge(_ shape: RoundedRectangle) -> some View {
        // Highlight sweep (always on — it's what makes the glass edge "pop").
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.7), .white.opacity(0.12),
                         .white.opacity(0.0), .white.opacity(0.28)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.2
        )
        .blendMode(.plusLighter)
        // Optional accent-colored rim tied to the counter color.
        if showBorder {
            shape.strokeBorder(tint.opacity(0.35), lineWidth: 1)
                .blendMode(.plusLighter)
        }
    }

    @ViewBuilder
    private func legacyBackground(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(
                LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
            )
            patternLayer(shape)
            if showBorder {
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
                shape.strokeBorder(tint.opacity(0.30), lineWidth: 1).blendMode(.plusLighter)
            }
        }
    }

    @ViewBuilder
    private func patternLayer(_ shape: RoundedRectangle) -> some View {
        if showPattern, patternOpacity > 0, let img = PatternTile.image {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable(resizingMode: .tile)
                .foregroundStyle(tint.opacity(patternOpacity))
                .clipShape(shape)
                .allowsHitTesting(false)
        }
    }
}
