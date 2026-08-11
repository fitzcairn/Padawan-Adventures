import SwiftUI
import UIKit

/// Shared screen-edge insets for app content and game HUDs.
///
/// Engines/backgrounds stay full-bleed. Visual chrome is inset by
/// `max(safeArea, edgeInsetFraction × dimension)` on each edge.
enum ScreenLayout {
    static let edgeInsetFraction: CGFloat = 0.025

    static func insets(size: CGSize, safeArea: EdgeInsets) -> EdgeInsets {
        edgeInsets(uiInsets(size: size, safeArea: uiEdgeInsets(safeArea)))
    }

    static func uiInsets(size: CGSize, safeArea: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: max(safeArea.top, size.height * edgeInsetFraction),
            left: max(safeArea.left, size.width * edgeInsetFraction),
            bottom: max(safeArea.bottom, size.height * edgeInsetFraction),
            right: max(safeArea.right, size.width * edgeInsetFraction)
        )
    }

    static func padding(for view: UIView) -> UIEdgeInsets {
        uiInsets(size: view.bounds.size, safeArea: view.safeAreaInsets)
    }

    /// Chrome insets for SpriteKit scenes.
    ///
    /// Measured against `sceneSize` rather than the SKView's bounds, so the fractional edge
    /// padding is right even when the scene lays out before its view does — which is what
    /// tutorial demos do, since they build once and never rebuild.
    @MainActor
    static func chromeInsets(sceneSize: CGSize, viewSafeArea: UIEdgeInsets) -> UIEdgeInsets {
        uiInsets(size: sceneSize, safeArea: resolvedSafeArea(viewSafeArea))
    }

    /// Center Y for a row of sprites resting on the bottom chrome inset.
    ///
    /// `ceiling` is the highest center the row may take (typically just under whatever it
    /// must stay clear of). A row too tall to fit gives up its bottom padding rather than
    /// climbing into the content above it.
    static func bottomRowCenterY(
        rowHeight: CGFloat,
        bottomInset: CGFloat,
        ceiling: CGFloat
    ) -> CGFloat {
        let half = max(rowHeight, 0) * 0.5
        return max(min(bottomInset + half, ceiling), half)
    }

    /// GeometryReader reports zero insets after `.ignoresSafeArea()`; fall back to the key window
    /// so landscape Dynamic Island / home-indicator edges still inset chrome.
    @MainActor
    static func safeArea(fromProxy proxy: EdgeInsets) -> EdgeInsets {
        edgeInsets(resolvedSafeArea(uiEdgeInsets(proxy)))
    }

    /// Anything that ignores the safe area reports zero insets, so a zero `candidate` means
    /// "unknown" rather than "no inset needed" — the key window has the real edges.
    @MainActor
    private static func resolvedSafeArea(_ candidate: UIEdgeInsets) -> UIEdgeInsets {
        guard candidate == .zero else { return candidate }
        return AppWindow.key?.safeAreaInsets ?? .zero
    }

    private static func uiEdgeInsets(_ insets: EdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: insets.top,
            left: insets.leading,
            bottom: insets.bottom,
            right: insets.trailing
        )
    }

    private static func edgeInsets(_ insets: UIEdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}

/// Full-bleed app screen with shared edge padding applied once at the root.
struct AppScreen<Content: View>: View {
    private let backgroundNamed: String?
    private let backgroundLibrary: BackgroundLibrary?
    private let isBackgroundReady: Binding<Bool>?
    @ViewBuilder private let content: () -> Content

    /// Held in state rather than read from the library on each pass: the library is a
    /// plain cache, so nothing else would redraw the screen once the decode lands.
    @State private var backgroundImage: UIImage?

    init(
        backgroundNamed: String? = nil,
        backgroundLibrary: BackgroundLibrary? = nil,
        isBackgroundReady: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundNamed = backgroundNamed
        self.backgroundLibrary = backgroundLibrary
        self.isBackgroundReady = isBackgroundReady
        self.content = content
        _backgroundImage = State(
            initialValue: backgroundNamed.flatMap { backgroundLibrary?.uiImage(named: $0) }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let insets = ScreenLayout.insets(
                size: geo.size,
                safeArea: ScreenLayout.safeArea(fromProxy: geo.safeAreaInsets)
            )
            content()
                .padding(insets)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .ignoresSafeArea()
        .background {
            if let backgroundImage {
                ScreenBackgroundView(image: backgroundImage)
            } else {
                AppChrome.backgroundColor.ignoresSafeArea()
            }
        }
        .task(id: backgroundNamed) {
            guard let backgroundNamed, let backgroundLibrary else {
                isBackgroundReady?.wrappedValue = true
                return
            }
            await backgroundLibrary.ensureLoaded(named: backgroundNamed)
            backgroundLibrary.retain(names: [backgroundNamed])
            backgroundImage = backgroundLibrary.uiImage(named: backgroundNamed)
            // Signalled even when the resource is missing, so content is never stranded.
            isBackgroundReady?.wrappedValue = true
        }
    }
}

extension View {
    /// Applies shared screen-edge padding. Use when the view already owns its background
    /// (e.g. dimmed overlays). Backgrounds should ignore safe area separately.
    func appScreenContentPadding() -> some View {
        modifier(AppScreenContentPaddingModifier())
    }
}

private struct AppScreenContentPaddingModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            let insets = ScreenLayout.insets(
                size: geo.size,
                safeArea: ScreenLayout.safeArea(fromProxy: geo.safeAreaInsets)
            )
            content
                .padding(insets)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

/// Keeps Auto Layout edge constants in sync with `ScreenLayout` as bounds/safe area change.
final class ScreenEdgeInsetController {
    private weak var host: UIView?
    private var topConstraints: [NSLayoutConstraint] = []
    private var leadingConstraints: [NSLayoutConstraint] = []
    private var trailingConstraints: [NSLayoutConstraint] = []
    private var bottomConstraints: [NSLayoutConstraint] = []

    init(host: UIView) {
        self.host = host
    }

    func addTop(_ constraint: NSLayoutConstraint) {
        topConstraints.append(constraint)
    }

    func addLeading(_ constraint: NSLayoutConstraint) {
        leadingConstraints.append(constraint)
    }

    func addTrailing(_ constraint: NSLayoutConstraint) {
        trailingConstraints.append(constraint)
    }

    func addBottom(_ constraint: NSLayoutConstraint) {
        bottomConstraints.append(constraint)
    }

    func update() {
        guard let host else { return }
        let insets = ScreenLayout.padding(for: host)
        for constraint in topConstraints {
            constraint.constant = insets.top
        }
        for constraint in leadingConstraints {
            constraint.constant = insets.left
        }
        for constraint in trailingConstraints {
            constraint.constant = -insets.right
        }
        for constraint in bottomConstraints {
            constraint.constant = -insets.bottom
        }
    }
}
