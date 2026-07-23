import SwiftUI

private enum OverlayDismissSecondsKey: EnvironmentKey {
    static let defaultValue: TimeInterval =
        WorldSeedConfig.DisplayParams.default.overlayDismissSeconds
}

extension EnvironmentValues {
    /// Auto-dismiss delay for `DismissibleOverlay` (from `world.yaml` display knobs).
    var overlayDismissSeconds: TimeInterval {
        get { self[OverlayDismissSecondsKey.self] }
        set { self[OverlayDismissSecondsKey.self] = newValue }
    }
}

/// Shared shell for fullscreen result overlays (win, lose, defeat, level complete).
///
/// Structure: full-bleed background + centered content. Behavior: dismiss on tap,
/// or automatically after `overlayDismissSeconds` (configurable in world.yaml).
/// Backgrounds and content stay customizable per call site.
struct DismissibleOverlay<Background: View, Content: View>: View {
    @Environment(\.overlayDismissSeconds) private var dismissSeconds

    let accessibilityRootID: String
    let onFinished: () -> Void
    private let background: Background
    private let content: Content

    @State private var didFinish = false

    init(
        accessibilityRootID: String,
        onFinished: @escaping () -> Void,
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityRootID = accessibilityRootID
        self.onFinished = onFinished
        self.background = background()
        self.content = content()
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { finish() }

            content
        }
        .accessibilityIdentifier(accessibilityRootID)
        .task {
            let delay = max(dismissSeconds, 0)
            guard delay > 0 else { return }
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

extension DismissibleOverlay where Background == Color {
    /// Default dimmed backdrop used by most minigame result overlays.
    init(
        accessibilityRootID: String,
        onFinished: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            accessibilityRootID: accessibilityRootID,
            onFinished: onFinished,
            background: { Color.black.opacity(0.55) },
            content: content
        )
    }
}

/// Shared yellow star row used by puzzle result overlays.
struct OverlayStars: View {
    let count: Int
    let accessibilityID: String

    var body: some View {
        if count > 0 {
            HStack(spacing: 16) {
                ForEach(0..<count, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.yellow)
                }
            }
            .accessibilityIdentifier(accessibilityID)
        }
    }
}
