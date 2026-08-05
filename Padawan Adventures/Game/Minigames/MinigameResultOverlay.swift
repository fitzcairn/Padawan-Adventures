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
    @State private var coinFrame: CGRect = .zero

    private static let holdSeconds: TimeInterval = 2
    private static let flightSeconds: TimeInterval = 0.75
    private static let coordinateSpace = "minigame.result.won"

    var body: some View {
        GeometryReader { geo in
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
                            Color.clear.preference(
                                key: CoinFrameKey.self,
                                value: proxy.frame(in: .named(Self.coordinateSpace))
                            )
                        }
                    }
                    .offset(flightOffset(in: geo.size))
                    .scaleEffect(1 - flightProgress)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(CoinFrameKey.self) { coinFrame = $0 }
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

    /// Offset from the coin row's laid-out center along a quadratic arc to the
    /// bottom-left corner of the overlay `(0, height)`.
    private func flightOffset(in size: CGSize) -> CGSize {
        guard flightProgress > 0, coinFrame != .zero else { return .zero }

        let start = CGPoint(x: coinFrame.midX, y: coinFrame.midY)
        let end = CGPoint(x: 0, y: size.height)
        let control = CGPoint(
            x: (start.x + end.x) * 0.5,
            y: min(start.y, end.y) - size.height * 0.22
        )
        let x = Self.quad(flightProgress, start.x, control.x, end.x)
        let y = Self.quad(flightProgress, start.y, control.y, end.y)
        return CGSize(width: x - start.x, height: y - start.y)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }

    /// Quadratic Bézier: `(1-t)²·p0 + 2(1-t)t·p1 + t²·p2`.
    private static func quad(_ t: CGFloat, _ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
        let u = 1 - t
        return u * u * p0 + 2 * u * t * p1 + t * t * p2
    }
}

private struct CoinFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
