import SwiftUI
import UIKit

struct PlanetStripView: View {
    let levels: [LevelDescriptor]
    let session: AppSession
    let orderedResourceNames: [String]
    let completedLevels: Set<String>
    let completedHighScores: [String: Int]
    let dadModeUnlocked: Bool
    let celebratingUnlockResource: String?
    let celebrationRevealed: Bool
    let planetSparklesActive: Bool
    let playerLocationResourceName: String?
    let playerAvatarImage: UIImage?
    let onLevelTap: (LevelDescriptor) -> Void

    @Binding var canScrollLeft: Bool
    @Binding var canScrollRight: Bool
    @State private var hasCenteredOnPlayer = false
    @State private var contentIsLaidOut = false

    /// Planet diameter as a fraction of available content width (~18% ≈ 150pt on phone landscape).
    private static let planetDiameterFraction: CGFloat = 0.18
    /// Gap between planets relative to planet diameter (keeps strip density consistent across sizes).
    private static let planetSpacingToDiameter: CGFloat = 0.26
    /// Vertical jitter half-range relative to planet diameter.
    private static let planetJitterToDiameter: CGFloat = 0.32
    /// Space above each planet so the high-score chip is not clipped.
    private static let highScoreChipToDiameter: CGFloat = 0.22

    var body: some View {
        GeometryReader { geo in
            let diameter = geo.size.width * Self.planetDiameterFraction
            let spacing = diameter * Self.planetSpacingToDiameter
            let jitterBand = diameter * Self.planetJitterToDiameter
            let chipReserve = diameter * Self.highScoreChipToDiameter

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(levels, id: \.resourceName) { level in
                            planetSprite(for: level, diameter: diameter)
                                .offset(y: verticalOffset(for: level.resourceName, band: jitterBand))
                                .id(level.resourceName)
                        }
                    }
                    // Internal scroll content inset (planet-to-edge breathing room), not screen margin.
                    .padding(.horizontal, spacing)
                    .padding(.top, chipReserve)
                    .frame(maxHeight: .infinity)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear {
                    centerOnPlayerIfNeeded(proxy: proxy, contentIsLaidOut: contentIsLaidOut)
                }
                .onChange(of: playerLocationResourceName) { _, _ in
                    centerOnPlayerIfNeeded(proxy: proxy, contentIsLaidOut: contentIsLaidOut)
                }
                .onScrollGeometryChange(for: ScrollOverflow.self) { geometry in
                    let leading = geometry.contentOffset.x
                    let trailing = geometry.contentSize.width - geometry.containerSize.width - geometry.contentOffset.x
                    return ScrollOverflow(
                        canScrollLeft: leading > 2,
                        canScrollRight: trailing > 2,
                        contentIsLaidOut: geometry.contentSize.width > 0
                    )
                } action: { _, newValue in
                    canScrollLeft = newValue.canScrollLeft
                    canScrollRight = newValue.canScrollRight
                    contentIsLaidOut = newValue.contentIsLaidOut
                    centerOnPlayerIfNeeded(proxy: proxy, contentIsLaidOut: newValue.contentIsLaidOut)
                }
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
        let chipHeight = max(18, diameter * 0.14)
        let highScore = state == .completed
            ? (completedHighScores[level.resourceName] ?? 0)
            : nil

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
                .overlay(alignment: .top) {
                    if let highScore {
                        planetHighScoreChip(score: highScore, height: chipHeight)
                            .offset(y: -(chipHeight + 4))
                    }
                }

                if showLockOverlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize, weight: .semibold))
                        .foregroundStyle(AppChrome.primaryTextColor)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .opacity(lockOpacity)
                }

                if playerLocationResourceName == level.resourceName {
                    PlayerLocationAvatar(image: playerAvatarImage)
                }

                if isCelebratingUnlock {
                    SparkleBurstView(isActive: planetSparklesActive, diameter: diameter)
                        .frame(width: diameter, height: diameter)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(planetAccessibilityLabel(level: level, highScore: highScore))
        .accessibilityIdentifier("levelSelect.\(level.resourceName)")
    }

    private func planetHighScoreChip(score: Int, height: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(Strings.text("planet_high_score", ["stars": String(score)]))
                .font(AppFont.swiftUI(size: max(12, height * 0.72), weight: .semibold))
                .foregroundStyle(AppChrome.primaryTextColor)
                .appCopyShadow()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            ScoreCoinIcon.Image(side: height * 0.78)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("levelSelect.planetHighScore")
        .allowsHitTesting(false)
    }

    private func planetAccessibilityLabel(level: LevelDescriptor, highScore: Int?) -> String {
        guard let highScore else { return level.displayName }
        return "\(level.displayName), \(Strings.text("planet_high_score", ["stars": String(highScore)]))"
    }

    private func centerOnPlayerIfNeeded(proxy: ScrollViewProxy, contentIsLaidOut: Bool) {
        guard !hasCenteredOnPlayer, let playerLocationResourceName, contentIsLaidOut else { return }
        hasCenteredOnPlayer = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(playerLocationResourceName, anchor: .center)
        }
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
        var contentIsLaidOut: Bool
    }
}

/// Menu-sized console avatar that bobs ±5% of its plate height (10% peak-to-peak) on a 3s sine.
private struct PlayerLocationAvatar: View {
    let image: UIImage?

    private static let side = PlayerAvatarView.menuSide * 0.8
    private static let period: TimeInterval = 3
    /// Peak-to-peak travel as a fraction of the rendered photo height.
    private static let totalAmplitudeFraction: CGFloat = 0.10

    @State private var startedAt: Date?

    var body: some View {
        let photoHeight = StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: Self.side, height: Self.side)
        ).height
        let halfAmplitude = photoHeight * Self.totalAmplitudeFraction / 2

        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt ?? context.date)
            let y = -sin(elapsed * 2 * .pi / Self.period) * halfAmplitude
            PlayerAvatarView(
                image: image,
                accessibilityID: "levelSelect.playerLocation",
                side: Self.side,
                style: .console
            )
            .offset(y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if startedAt == nil {
                startedAt = Date()
            }
        }
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
