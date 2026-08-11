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

    /// 70% dim scrim so the screen behind a modal stays faintly visible.
    static let dimColor = Color.black.opacity(0.7)
}

/// CRT bezel + screen plate that sizes to its content.
///
/// Scanlines sit above the content so titles and buttons pick up the CRT look.
struct ModalCRTPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(28)
            .frame(maxWidth: .infinity)
            .background {
                StarWarsConsoleFrame { Color.clear }
            }
            .overlay {
                GeometryReader { geo in
                    let m = min(geo.size.width, geo.size.height)
                    let inset = m * StarWarsConsoleChrome.insetRatio
                    ScanlineOverlay(spacing: max(2, m * 0.06), lineOpacity: 0.32)
                        .padding(inset)
                }
                .allowsHitTesting(false)
            }
    }
}

/// Glowing CRT copy for modal titles and body text.
struct ModalCRTText: View {
    let text: String
    var size: CGFloat = 32
    var weight: Font.Weight = .bold
    var color: Color = StarWarsConsolePalette.crtBlue
    var glow: Color = StarWarsConsolePalette.crtGlow
    var accessibilityID: String? = nil
    var speakID: String? = nil

    var body: some View {
        Text(text)
            .font(AppFont.swiftUI(size: size, weight: weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .shadow(color: glow, radius: max(2, size * 0.12))
            .accessibilityIdentifier(accessibilityID ?? text)
            .modifier(ModalCRTSpeakOnTap(speakID: speakID))
    }
}

private struct ModalCRTSpeakOnTap: ViewModifier {
    let speakID: String?

    func body(content: Content) -> some View {
        if let speakID {
            content
                .contentShape(Rectangle())
                .onTapGesture { Strings.speak(speakID) }
        } else {
            content
        }
    }
}

/// Full-bleed dim scrim + centered content for modal overlays.
///
/// Structure: dim backdrop + content (prefer `ModalCRTPanel` for the dialog plate).
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

/// Shared coin row used by win result overlays (score awards).
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
