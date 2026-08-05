import SwiftUI
import UIKit

struct PlanetStripView: View {
    let levels: [LevelDescriptor]
    let session: AppSession
    let orderedResourceNames: [String]
    let completedLevels: Set<String>
    let dadModeUnlocked: Bool
    let celebratingUnlockResource: String?
    let celebrationRevealed: Bool
    let planetSparklesActive: Bool
    let onLevelTap: (LevelDescriptor) -> Void

    @Binding var canScrollLeft: Bool
    @Binding var canScrollRight: Bool

    /// Planet diameter as a fraction of available content width (~18% ≈ 150pt on phone landscape).
    private static let planetDiameterFraction: CGFloat = 0.18
    /// Gap between planets relative to planet diameter (keeps strip density consistent across sizes).
    private static let planetSpacingToDiameter: CGFloat = 0.26
    /// Vertical jitter half-range relative to planet diameter.
    private static let planetJitterToDiameter: CGFloat = 0.32

    var body: some View {
        GeometryReader { geo in
            let diameter = geo.size.width * Self.planetDiameterFraction
            let spacing = diameter * Self.planetSpacingToDiameter
            let jitterBand = diameter * Self.planetJitterToDiameter

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(levels, id: \.resourceName) { level in
                        planetSprite(for: level, diameter: diameter)
                            .offset(y: verticalOffset(for: level.resourceName, band: jitterBand))
                    }
                }
                // Internal scroll content inset (planet-to-edge breathing room), not screen margin.
                .padding(.horizontal, spacing)
                .frame(maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onScrollGeometryChange(for: ScrollOverflow.self) { geometry in
                let leading = geometry.contentOffset.x
                let trailing = geometry.contentSize.width - geometry.containerSize.width - geometry.contentOffset.x
                return ScrollOverflow(
                    canScrollLeft: leading > 2,
                    canScrollRight: trailing > 2
                )
            } action: { _, newValue in
                canScrollLeft = newValue.canScrollLeft
                canScrollRight = newValue.canScrollRight
            }
        }
    }

    private func planetSprite(for level: LevelDescriptor, diameter: CGFloat) -> some View {
        let state = LevelProgression.unlockState(
            for: level.resourceName,
            orderedLevels: orderedResourceNames,
            completed: completedLevels,
            dadModeUnlocked: dadModeUnlocked
        )
        let isLocked = !dadModeUnlocked && state == .locked
        let isCelebratingUnlock = celebratingUnlockResource == level.resourceName
        let visuallyLocked = isLocked || (isCelebratingUnlock && !celebrationRevealed)
        let showLockOverlay = isLocked || isCelebratingUnlock
        let lockOpacity: Double = {
            if isCelebratingUnlock {
                return celebrationRevealed ? 0 : 1
            }
            return isLocked ? 1 : 0
        }()
        let fill = Color(uiColor: UIColor(hex: level.color) ?? .gray)
        let planetImage = level.sprite != nil
            ? session.spriteLibrary.uiImage(id: level.resourceName, named: "idle")
            : nil
        let lockIconSize = diameter * 0.19
        let completedStroke = max(2, diameter * 0.027)

        return Button {
            onLevelTap(level)
        } label: {
            ZStack {
                Group {
                    if let planetImage {
                        Image(uiImage: planetImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Circle().fill(fill)
                    }
                }
                .frame(width: diameter, height: diameter)
                .overlay {
                    if state == .completed {
                        Circle()
                            .stroke(Color.green, lineWidth: completedStroke)
                    }
                }
                .opacity(visuallyLocked ? 0.5 : 1)

                if showLockOverlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize, weight: .semibold))
                        .foregroundStyle(AppChrome.primaryTextColor)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .opacity(lockOpacity)
                }

                if isCelebratingUnlock {
                    SparkleBurstView(isActive: planetSparklesActive, diameter: diameter)
                        .frame(width: diameter, height: diameter)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.displayName)
        .accessibilityIdentifier("levelSelect.\(level.resourceName)")
    }

    /// Stable pseudo-random vertical jitter so planets don't share one baseline.
    private func verticalOffset(for resourceName: String, band: CGFloat) -> CGFloat {
        var hash: UInt64 = 1469598103934665603
        for byte in resourceName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let unit = Double(hash % 1001) / 1000.0
        return CGFloat(unit * 2 - 1) * band
    }

    private struct ScrollOverflow: Equatable {
        var canScrollLeft: Bool
        var canScrollRight: Bool
    }
}

struct PlanetStripScrollHints: View {
    let canScrollLeft: Bool
    let canScrollRight: Bool

    var body: some View {
        GeometryReader { geo in
            let insets = ScreenLayout.insets(
                size: geo.size,
                safeArea: ScreenLayout.safeArea(fromProxy: geo.safeAreaInsets)
            )
            HStack {
                scrollHintArrow(systemName: "chevron.left", visible: canScrollLeft)
                    .accessibilityIdentifier("levelSelect.scrollLeftHint")
                Spacer()
                scrollHintArrow(systemName: "chevron.right", visible: canScrollRight)
                    .accessibilityIdentifier("levelSelect.scrollRightHint")
            }
            .padding(.leading, insets.leading + 8)
            .padding(.trailing, insets.trailing + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func scrollHintArrow(systemName: String, visible: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(AppChrome.primaryTextColor)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: visible)
            .accessibilityHidden(true)
    }
}
