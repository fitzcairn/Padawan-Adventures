import SwiftUI
import UIKit

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let viewModel: LevelSelectViewModel
    private let screenBackground: String?

    @State private var messageOverlay: LevelSelectMessage?
    @State private var selectedLevel: LevelDescriptor?
    @State private var showPassword = false
    /// Bumps when Dad mode / progression changes so buttons re-read session state.
    @State private var progressionEpoch = 0
    @State private var nameSpeaker = LevelNameSpeaker()
    @State private var canScrollLeft = false
    @State private var canScrollRight = false
    @State private var inventoryIcons: [String: UIImage] = [:]
    /// False until planets, inventory icons, and coin art are warm — content stays hidden.
    @State private var isContentReady = false
    /// False until `AppScreen` has painted the backdrop, so planets never land on bare colour.
    @State private var isBackgroundReady = false
    /// Resource whose treasure should fade in (first completion this session).
    @State private var celebratingInventoryResource: String?
    /// Planet that should animate from locked → unlocked.
    @State private var celebratingUnlockResource: String?
    /// When false during a celebration, show the pre-unlock visuals; then animate to true.
    @State private var celebrationRevealed = true
    @State private var inventorySparklesActive = false
    @State private var planetSparklesActive = false

    private static let celebrationHoldNanoseconds: UInt64 = 350_000_000
    private static let contentFadeSeconds: Double = 0.35

    init(
        session: AppSession,
        router: FlowRouter,
        levels: [LevelDescriptor]? = nil
    ) {
        self.session = session
        self.router = router
        let resolvedLevels = levels ?? LevelCatalog.loadFromBundle()
        self.viewModel = LevelSelectViewModel(session: session, levels: resolvedLevels)
        let background = (try? ScreenConfig.loadFromBundle(named: "level_select"))?.background
        self.screenBackground = background

        // Seed celebration from session so the first frame already hides the new item / lock.
        let pending = session.pendingLevelSelectCelebration
        let ordered = resolvedLevels.map(\.resourceName)
        _celebratingInventoryResource = State(initialValue: pending)
        _celebratingUnlockResource = State(
            initialValue: LevelSelectViewModel.initialCelebrationUnlockResource(
                pending: pending,
                orderedLevels: ordered
            )
        )
        _celebrationRevealed = State(initialValue: pending == nil)

        _inventoryIcons = State(
            initialValue: LevelSelectViewModel.seededInventoryIcons(
                session: session,
                levels: resolvedLevels
            )
        )
        // Bootstrap warms planets / icons / coin; show content on first frame when present.
        let planetsReady = LevelSelectViewModel.planetsReady(session: session, levels: resolvedLevels)
        _isContentReady = State(initialValue: planetsReady && ScoreCoinIcon.uiImage() != nil)
        _isBackgroundReady = State(
            initialValue: session.backgroundLibrary.isReady(named: background)
        )
    }

    /// Planets wait on the backdrop; the background is dropped on level exit, so arriving
    /// here usually means a fresh multi-megapixel decode.
    private var showsContent: Bool {
        isContentReady && isBackgroundReady
    }

    var body: some View {
        ZStack {
            AppScreen(
                backgroundNamed: screenBackground,
                backgroundLibrary: session.backgroundLibrary,
                isBackgroundReady: $isBackgroundReady
            ) {
                Group {
                    if showsContent {
                        readyContent
                            .transition(.opacity)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("levelSelect.loading")
                    }
                }
                .animation(.easeIn(duration: Self.contentFadeSeconds), value: showsContent)
            }

            if showsContent {
                PlanetStripScrollHints(
                    canScrollLeft: canScrollLeft,
                    canScrollRight: canScrollRight
                )
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
                    session.appConfig.display.overlayDismissSeconds
                )
            }

            if let selectedLevel {
                let progress = session.playerState?.levels[selectedLevel.resourceName]
                LevelDetailOverlay(
                    levelName: selectedLevel.displayName,
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
        .playScreenMusic("level_select")
        .onAppear { MemoryProbe.mark("level-select") }
        .task {
            // Assets are warmed on the loading screen; refresh icons if progression changed.
            let ids = viewModel.inventoryTreasureIDs(progressionEpoch: progressionEpoch)
            inventoryIcons = viewModel.refreshInventoryIcons(ids: ids)
            isContentReady = true
        }
        .task(id: showsContent) {
            // Held back until the strip is on screen, or the reveal plays behind a blank screen.
            guard showsContent else { return }
            await runPendingCelebrationIfNeeded()
        }
        .fullScreenCover(isPresented: $showPassword) {
            DadModePasswordView(
                expectedPassword: session.appConfig.dadModePassword,
                onSuccess: {
                    Task { @MainActor in
                        await session.unlockDadMode()
                        progressionEpoch += 1
                        showPassword = false
                        messageOverlay = .dadModeUnlocked
                    }
                },
                onCancel: {
                    showPassword = false
                }
            )
        }
    }

    @MainActor
    private func runPendingCelebrationIfNeeded() async {
        let completed = celebratingInventoryResource ?? session.pendingLevelSelectCelebration
        guard let completed else { return }
        _ = session.consumeLevelSelectCelebration()
        celebratingInventoryResource = completed
        celebratingUnlockResource = LevelProgression.resourceUnlockedByCompleting(
            completed,
            orderedLevels: viewModel.orderedResourceNames
        )
        celebrationRevealed = false
        inventorySparklesActive = false
        planetSparklesActive = false

        // Warm the new treasure icon before fading it in.
        if let treasureID = viewModel.levels.first(where: { $0.resourceName == completed })?.treasure {
            await session.ensureTreasureIconsLoaded(ids: [treasureID])
            if let image = session.spriteLibrary.uiImage(id: treasureID) {
                inventoryIcons[treasureID] = image
            }
        }

        try? await Task.sleep(nanoseconds: Self.celebrationHoldNanoseconds)
        guard !Task.isCancelled else { return }

        let artifactTrackID = SoundEffectsController.shared.commonFx.trackID(for: "artifact_appear")
        let revealSeconds = SoundEffectsController.shared.cueDuration(of: artifactTrackID)
        SoundEffectsController.shared.playCommon(event: "artifact_appear")
        inventorySparklesActive = true
        planetSparklesActive = celebratingUnlockResource != nil
        withAnimation(.easeIn(duration: revealSeconds)) {
            celebrationRevealed = true
        }

        try? await Task.sleep(nanoseconds: UInt64(revealSeconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        inventorySparklesActive = false
        planetSparklesActive = false
    }

    private var readyContent: some View {
        VStack(spacing: 0) {
            starCountHeader
                .padding(.bottom, 8)

            PlanetStripView(
                levels: viewModel.levels,
                session: session,
                orderedResourceNames: viewModel.orderedResourceNames,
                completedLevels: viewModel.completedLevels,
                dadModeUnlocked: viewModel.dadModeUnlocked(progressionEpoch: progressionEpoch),
                celebratingUnlockResource: celebratingUnlockResource,
                celebrationRevealed: celebrationRevealed,
                planetSparklesActive: planetSparklesActive,
                onLevelTap: handleLevelTap,
                canScrollLeft: $canScrollLeft,
                canScrollRight: $canScrollRight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12)

            // Inventory + chrome buttons share one bottom band (bottoms aligned).
            HStack(alignment: .bottom, spacing: 16) {
                AppCircularIconButton(
                    systemName: "chevron.backward",
                    accessibilityID: "levelSelect.back",
                    accessibilityLabel: "Back"
                ) {
                    router.popOrShowMenu()
                }

                InventoryRackView(
                    session: session,
                    inventoryLevels: viewModel.inventoryLevels(progressionEpoch: progressionEpoch),
                    inventoryTreasureIDs: viewModel.inventoryTreasureIDs(progressionEpoch: progressionEpoch),
                    isContentReady: showsContent,
                    celebratingInventoryResource: celebratingInventoryResource,
                    celebrationRevealed: celebrationRevealed,
                    inventorySparklesActive: inventorySparklesActive,
                    inventoryIcons: $inventoryIcons
                )
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
        }
    }

    private var starCountHeader: some View {
        HStack(spacing: 8) {
            ScoreCoinIcon.Image(side: 22)
            Text("\(session.playerState?.totalStars ?? 0)")
                .font(AppFont.swiftUI(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.primaryTextColor)
                .appCopyShadow()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("levelSelect.totalStars")
    }

    private func handleLevelTap(_ level: LevelDescriptor) {
        if let message = viewModel.handleLevelTap(
            level,
            progressionEpoch: progressionEpoch,
            nameSpeaker: nameSpeaker
        ) {
            playMenuSound("button_click")
            messageOverlay = message
            return
        }

        let hasBeenPlayed = session.playerState?.levels[level.resourceName]?.started == true
        if hasBeenPlayed {
            playMenuSound("button_click")
            selectedLevel = level
        } else {
            // First visit: takeoff on planet tap and start immediately (no confirm modal).
            playMenuSound("takeoff")
            startLevel(level)
        }
    }

    private func startLevel(_ level: LevelDescriptor) {
        selectedLevel = nil
        Task {
            if viewModel.dadModeUnlocked(progressionEpoch: progressionEpoch) {
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
}
