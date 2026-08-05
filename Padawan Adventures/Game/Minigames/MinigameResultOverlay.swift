import SwiftUI

/// Shared win overlay for all minigames and combat.
///
/// Shows "You won N coins!" with a centered coin row. Tap dismisses immediately.
/// After 2 seconds without a tap, coins arc to the bottom-left corner while shrinking
/// to 0, then the overlay finishes.
struct MinigameResultOverlay: View {
    let starsAwarded: Int
    let onFinished: () -> Void

    @State private var didFinish = false
    @State private var flightProgress: CGFloat = 0
    @State private var coinCenter: CGPoint?

    private static let holdSeconds: TimeInterval = 2
    private static let flightSeconds: TimeInterval = 0.75

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.frame(in: .global)

            ModalOverlayShell(
                accessibilityRootID: "minigame.result.won.root",
                onBackgroundTap: { finish() }
            ) {
                VStack(spacing: 28) {
                    Text("You won \(starsAwarded) coins!")
                        .font(AppFont.swiftUI(size: 36, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .appCopyShadow()
                        .accessibilityIdentifier("minigame.result.won.title")
                        .opacity(1 - Double(flightProgress))

                    OverlayStars(
                        count: starsAwarded,
                        accessibilityID: "minigame.result.won.stars"
                    )
                    .background {
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .global)
                            Color.clear.preference(
                                key: CoinCenterKey.self,
                                value: CGPoint(x: frame.midX, y: frame.midY)
                            )
                        }
                    }
                    .modifier(
                        CoinArcFlight(
                            progress: flightProgress,
                            start: coinCenter ?? CGPoint(x: bounds.midX, y: bounds.midY),
                            end: CGPoint(x: bounds.minX, y: bounds.maxY),
                            arcHeight: bounds.height * 0.22
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onPreferenceChange(CoinCenterKey.self) { center in
            // The measured frame travels with the coins once they launch; keep the
            // resting position so the arc has a fixed origin.
            guard flightProgress == 0 else { return }
            coinCenter = center
        }
        .task {
            let holdNanos = UInt64(Self.holdSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: holdNanos)
            guard !didFinish else { return }

            withAnimation(.easeInOut(duration: Self.flightSeconds)) {
                flightProgress = 1
            }

            let flightNanos = UInt64(Self.flightSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: flightNanos)
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

/// Moves content along a quadratic arc from `start` to `end` while shrinking to nothing.
///
/// Animating `progress` directly (rather than the resulting offset) keeps the curve:
/// SwiftUI would otherwise interpolate the endpoints in a straight line.
private struct CoinArcFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    let arcHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(max(1 - progress, 0))
            .offset(offset)
    }

    private var offset: CGSize {
        guard progress > 0 else { return .zero }
        // Control point sits most of the way toward the corner horizontally and above
        // the start, so the coins sweep left early and then drop into the corner.
        let control = CGPoint(
            x: start.x + (end.x - start.x) * 0.75,
            y: min(start.y, end.y) - arcHeight
        )
        return CGSize(
            width: Self.quad(progress, start.x, control.x, end.x) - start.x,
            height: Self.quad(progress, start.y, control.y, end.y) - start.y
        )
    }

    /// Quadratic Bézier: `(1-t)²·p0 + 2(1-t)t·p1 + t²·p2`.
    private static func quad(_ t: CGFloat, _ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * p0 + 2 * u * t * p1 + t * t * p2
    }
}

private struct CoinCenterKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
