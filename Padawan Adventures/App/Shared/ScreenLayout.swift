import SwiftUI
import UIKit

/// Shared screen-edge insets for app content and game HUDs.
///
/// Engines/backgrounds stay full-bleed. Visual chrome is inset by
/// `max(safeArea, edgeInsetFraction × dimension)` on each edge.
enum ScreenLayout {
    static let edgeInsetFraction: CGFloat = 0.025

    static func insets(size: CGSize, safeArea: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(safeArea.top, size.height * edgeInsetFraction),
            leading: max(safeArea.leading, size.width * edgeInsetFraction),
            bottom: max(safeArea.bottom, size.height * edgeInsetFraction),
            trailing: max(safeArea.trailing, size.width * edgeInsetFraction)
        )
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
}

/// Full-bleed app screen with shared edge padding applied once at the root.
struct AppScreen<Content: View>: View {
    private let backgroundNamed: String?
    private let backgroundLibrary: BackgroundLibrary?
    @ViewBuilder private let content: () -> Content

    init(
        backgroundNamed: String? = nil,
        backgroundLibrary: BackgroundLibrary? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundNamed = backgroundNamed
        self.backgroundLibrary = backgroundLibrary
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let insets = ScreenLayout.insets(size: geo.size, safeArea: geo.safeAreaInsets)
            content()
                .padding(insets)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .ignoresSafeArea()
        .background {
            if let backgroundNamed,
               let image = backgroundLibrary?.uiImage(named: backgroundNamed) {
                ScreenBackgroundView(image: image)
            } else {
                AppChrome.backgroundColor.ignoresSafeArea()
            }
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
            let insets = ScreenLayout.insets(size: geo.size, safeArea: geo.safeAreaInsets)
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
