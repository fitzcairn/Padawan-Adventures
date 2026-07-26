import SwiftUI
import UIKit

private enum OverlayDismissSecondsKey: EnvironmentKey {
    static let defaultValue: TimeInterval =
        AppConfig.DisplayParams.default.overlayDismissSeconds
}

extension EnvironmentValues {
    /// Auto-dismiss delay for `DismissibleOverlay` (from `app.yaml` display knobs).
    var overlayDismissSeconds: TimeInterval {
        get { self[OverlayDismissSecondsKey.self] }
        set { self[OverlayDismissSecondsKey.self] = newValue }
    }
}

/// Shared chrome for modal overlays and fullscreen minigame hosts.
enum OverlayChrome {
    /// Fully opaque fill for minigames / UIKit fullscreen hosts.
    static let backgroundColor = Color.black
    static var uiBackgroundColor: UIColor { .black }

    /// 50% dim scrim so the screen behind a modal stays visible.
    static let dimColor = Color.black.opacity(0.5)
}

/// Full-bleed dim scrim + centered content for modal overlays.
///
/// Structure: 50% transparent backdrop + content (modal boxes should be opaque).
/// Optional background tap for dismiss.
struct ModalOverlayShell<Content: View>: View {
    let accessibilityRootID: String
    var onBackgroundTap: (() -> Void)?
    private let content: Content

    init(
        accessibilityRootID: String,
        onBackgroundTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityRootID = accessibilityRootID
        self.onBackgroundTap = onBackgroundTap
        self.content = content()
    }

    var body: some View {
        ZStack {
            OverlayChrome.dimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onBackgroundTap?()
                }

            content
                .appScreenContentPadding()
        }
        .accessibilityIdentifier(accessibilityRootID)
    }
}

/// Shared shell for fullscreen result overlays (win, lose, defeat, level complete).
///
/// Structure: dim scrim + centered content. Behavior: dismiss on tap,
/// or automatically after `overlayDismissSeconds` (configurable in app.yaml).
struct DismissibleOverlay<Content: View>: View {
    @Environment(\.overlayDismissSeconds) private var dismissSeconds

    let accessibilityRootID: String
    let onFinished: () -> Void
    private let content: Content

    @State private var didFinish = false

    init(
        accessibilityRootID: String,
        onFinished: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityRootID = accessibilityRootID
        self.onFinished = onFinished
        self.content = content()
    }

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: accessibilityRootID,
            onBackgroundTap: { finish() }
        ) {
            content
        }
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

/// Shared coin row used by puzzle result overlays (score awards).
struct OverlayStars: View {
    let count: Int
    let accessibilityID: String

    var body: some View {
        if count > 0 {
            HStack(spacing: 16) {
                ForEach(0..<count, id: \.self) { _ in
                    ScoreCoinIcon.Image(side: 54)
                }
            }
            .accessibilityIdentifier(accessibilityID)
        }
    }
}
