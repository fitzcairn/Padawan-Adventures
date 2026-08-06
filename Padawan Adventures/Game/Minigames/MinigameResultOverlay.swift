import SwiftUI

/// Shared win overlay for all minigames and combat.
///
/// Shows "You won N coins!" with a centered coin row. Tap dismisses immediately.
/// After 2 seconds without a tap, coins arc to the screen's bottom-left corner while
/// shrinking to 0, then the overlay finishes.
struct MinigameResultOverlay: View {
    let starsAwarded: Int
    let onFinished: () -> Void

    @State private var didFinish = false
    @State private var flightProgress: CGFloat = 0

    private static let holdSeconds: TimeInterval = 2
    private static let flightSeconds: TimeInterval = 0.75
    /// Vertical gap from screen center to the resting coin row (title sits above).
    private static let coinRestOffsetY: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let coinStart = CGPoint(x: size.width / 2, y: size.height / 2 + Self.coinRestOffsetY)
            let coinEnd = CGPoint(x: 0, y: size.height)

            ZStack {
                OverlayChrome.dimColor
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { finish() }

                Text(Strings.text("minigame_coins_won", ["coins": String(starsAwarded)]))
                    .font(AppFont.swiftUI(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .appCopyShadow()
                    .accessibilityIdentifier("minigame.result.won.title")
                    .opacity(1 - Double(flightProgress))
                    .position(
                        x: size.width / 2,
                        y: size.height / 2 - Self.coinRestOffsetY
                    )

                OverlayStars(
                    count: starsAwarded,
                    accessibilityID: "minigame.result.won.stars"
                )
                .modifier(
                    CoinArcFlight(
                        progress: flightProgress,
                        start: coinStart,
                        end: coinEnd,
                        arcHeight: size.height * 0.22
                    )
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("minigame.result.won.root")
        .onAppear { Strings.speak("minigame_coins_won") }
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

/// Places content along a quadratic arc from `start` to `end` while shrinking to nothing.
///
/// Animating `progress` (not the resulting point) keeps the curve; SwiftUI would otherwise
/// lerp the endpoints in a straight line. Uses `.position` in the full-screen parent so the
/// end point `(0, height)` is the screen's bottom-left corner.
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
            .position(point(at: progress))
    }

    private func point(at t: CGFloat) -> CGPoint {
        let control = CGPoint(
            x: start.x + (end.x - start.x) * 0.75,
            y: min(start.y, end.y) - arcHeight
        )
        return CGPoint(
            x: Self.quad(t, start.x, control.x, end.x),
            y: Self.quad(t, start.y, control.y, end.y)
        )
    }

    /// Quadratic Bézier: `(1-t)²·p0 + 2(1-t)t·p1 + t²·p2`.
    private static func quad(_ t: CGFloat, _ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * p0 + 2 * u * t * p1 + t * t * p2
    }
}
