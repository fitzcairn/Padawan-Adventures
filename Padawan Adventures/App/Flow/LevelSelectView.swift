import SwiftUI
import UIKit

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let levels: [LevelDescriptor]

    @State private var messageOverlay: MessageKind?
    @State private var selectedLevel: LevelDescriptor?
    @State private var showPassword = false
    /// Bumps when Dad mode / progression changes so buttons re-read session state.
    @State private var progressionEpoch = 0
    @State private var nameSpeaker = LevelNameSpeaker()
    @State private var canScrollLeft = false
    @State private var canScrollRight = false

    private let planetDiameter: CGFloat = 96
    /// Previous spacing was 28; +40% → 39.2.
    private let planetSpacing: CGFloat = 39.2

    init(
        session: AppSession,
        router: FlowRouter,
        levels: [LevelDescriptor]? = nil
    ) {
        self.session = session
        self.router = router
        self.levels = levels ?? LevelCatalog.loadFromBundle()
    }

    private var inventoryArtifacts: [String] {
        session.playerState?.inventory.artifacts ?? []
    }

    private var orderedResourceNames: [String] {
        levels.map(\.resourceName)
    }

    private var completedLevels: Set<String> {
        let progress = session.playerState?.levels ?? [:]
        return Set(progress.compactMap { name, level in
            level.completed ? name : nil
        })
    }

    private var dadModeUnlocked: Bool {
        _ = progressionEpoch
        return session.isDadModeUnlocked
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                starCountHeader
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                planetStrip
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)

                // Inventory + chrome buttons share one bottom band (bottoms aligned).
                HStack(alignment: .bottom, spacing: 16) {
                    AppCircularIconButton(
                        systemName: "chevron.backward",
                        accessibilityID: "levelSelect.back",
                        accessibilityLabel: "Back"
                    ) {
                        if router.path.isEmpty {
                            router.showMenu()
                        } else {
                            router.pop()
                        }
                    }

                    inventorySection
                        .frame(maxWidth: AppChrome.maxContentWidth)
                        .frame(maxWidth: .infinity)

                    AppCircularIconButton(
                        systemName: "lock.fill",
                        accessibilityID: "levelSelect.dadModeLock",
                        accessibilityLabel: "Dad mode"
                    ) {
                        showPassword = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            if let messageOverlay {
                MessageOverlay(
                    title: messageOverlay.title,
                    accessibilityRootID: messageOverlay.rootID,
                    accessibilityTitleID: messageOverlay.titleID
                ) {
                    self.messageOverlay = nil
                }
                .environment(
                    \.overlayDismissSeconds,
                    session.seedConfig.display.overlayDismissSeconds
                )
            }

            if let selectedLevel {
                let progress = session.playerState?.levels[selectedLevel.resourceName]
                LevelDetailOverlay(
                    levelName: selectedLevel.displayName,
                    hasBeenPlayed: progress?.started == true,
                    highestStars: progress?.starsEarned ?? 0,
                    onStart: {
                        startLevel(selectedLevel)
                    },
                    onDismiss: {
                        self.selectedLevel = nil
                    }
                )
            }
        }
        .appScreenBackground()
        .playScreenMusic("level_select")
        .fullScreenCover(isPresented: $showPassword) {
            DadModePasswordView(
                expectedPassword: session.seedConfig.dadModePassword,
                onSuccess: {
                    showPassword = false
                    Task {
                        await session.unlockDadMode()
                        progressionEpoch += 1
                        messageOverlay = .dadModeUnlocked
                    }
                },
                onCancel: {
                    showPassword = false
                }
            )
        }
    }

    private var starCountHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 22, weight: .semibold))
            Text("\(session.playerState?.totalStars ?? 0)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.primaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("levelSelect.totalStars")
    }

    private var planetStrip: some View {
        ZStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: planetSpacing) {
                    ForEach(levels, id: \.resourceName) { level in
                        planetSprite(for: level)
                            .offset(y: verticalOffset(for: level.resourceName))
                    }
                }
                .padding(.horizontal, 36)
                .frame(maxHeight: .infinity)
            }
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

            HStack {
                scrollHintArrow(systemName: "chevron.left", visible: canScrollLeft)
                    .accessibilityIdentifier("levelSelect.scrollLeftHint")
                Spacer()
                scrollHintArrow(systemName: "chevron.right", visible: canScrollRight)
                    .accessibilityIdentifier("levelSelect.scrollRightHint")
            }
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
        }
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

    @ViewBuilder
    private func planetSprite(for level: LevelDescriptor) -> some View {
        let state = LevelProgression.unlockState(
            for: level.resourceName,
            orderedLevels: orderedResourceNames,
            completed: completedLevels,
            dadModeUnlocked: dadModeUnlocked
        )
        let isLocked = !dadModeUnlocked && state == .locked
        let fill = Color(uiColor: UIColor(hex: level.color) ?? .gray)

        Button {
            handleLevelTap(level)
        } label: {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: planetDiameter, height: planetDiameter)
                    .overlay {
                        if state == .completed {
                            Circle()
                                .stroke(Color.green, lineWidth: 4)
                        }
                    }
                    .opacity(isLocked ? 0.5 : 1)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppChrome.primaryTextColor)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .opacity(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.displayName)
        .accessibilityIdentifier("levelSelect.\(level.resourceName)")
    }

    /// Stable pseudo-random vertical jitter so planets don't share one baseline.
    private func verticalOffset(for resourceName: String) -> CGFloat {
        var hash: UInt64 = 1469598103934665603
        for byte in resourceName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let band: CGFloat = 48
        let unit = Double(hash % 1001) / 1000.0
        return CGFloat(unit * 2 - 1) * band
    }

    private func handleLevelTap(_ level: LevelDescriptor) {
        let playable = LevelProgression.isPlayable(
            for: level.resourceName,
            orderedLevels: orderedResourceNames,
            completed: completedLevels,
            dadModeUnlocked: dadModeUnlocked
        )
        guard playable else {
            messageOverlay = .completeCurrentFirst
            return
        }

        nameSpeaker.speak(level.displayName)
        selectedLevel = level
    }

    private func startLevel(_ level: LevelDescriptor) {
        selectedLevel = nil
        Task {
            if dadModeUnlocked {
                await session.applyDadModeProgression(to: level.resourceName)
            }
            do {
                try session.selectLevel(resourceName: level.resourceName)
                router.navigate(to: .preparing(.newGame))
            } catch {
                // Ignore invalid/missing level resources.
            }
        }
    }

    private var inventorySection: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(AppChrome.secondaryTextColor, lineWidth: 2)
            .frame(height: 72)
            .overlay {
                HStack(spacing: 16) {
                    ForEach(inventoryArtifacts, id: \.self) { artifact in
                        Image(systemName: artifact)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppChrome.primaryTextColor)
                            .accessibilityIdentifier("levelSelect.inventory.\(artifact)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("levelSelect.inventory")
            .accessibilityLabel("Inventory")
    }

    private struct ScrollOverflow: Equatable {
        var canScrollLeft: Bool
        var canScrollRight: Bool
    }

    private enum MessageKind: Equatable {
        case completeCurrentFirst
        case dadModeUnlocked

        var title: String {
            switch self {
            case .completeCurrentFirst:
                return "Complete the current level first!"
            case .dadModeUnlocked:
                return "Dad mode unlocked!"
            }
        }

        var rootID: String {
            switch self {
            case .completeCurrentFirst:
                return "levelSelect.lockedOverlay"
            case .dadModeUnlocked:
                return "levelSelect.dadModeOverlay"
            }
        }

        var titleID: String {
            switch self {
            case .completeCurrentFirst:
                return "levelSelect.lockedOverlay.title"
            case .dadModeUnlocked:
                return "levelSelect.dadModeOverlay.title"
            }
        }
    }
}
