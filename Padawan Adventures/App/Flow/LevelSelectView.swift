import SwiftUI
import UIKit

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let viewModel: LevelSelectViewModel
    private let screenBackground: String?

    @State private var messageOverlay: LevelSelectMessage?
    @State private var selectedLevel: LevelDescriptor?
    @State private var detailMode: LevelDetailMode?
    @State private var showPassword = false
    /// Bumps when Dad mode / progression changes so buttons re-read session state.
    @State private var progressionEpoch = 0
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
    /// Campaign-clear sequence after the final artifact fades in.
    @State private var campaignWinActive = false
    @State private var campaignWinScrimOpacity: Double = 0
    @State private var campaignWinTextOpacity: Double = 0
    @State private var campaignWinInteractive = false
    @State private var campaignWinArtifactsOffsetY: CGFloat = 0
    @State private var campaignWinSparklesActive = false
    @State private var playerAvatarImage: UIImage?
    @State private var playerAvatarReady = false

    private static let celebrationHoldNanoseconds: UInt64 = 350_000_000
    private static let contentFadeSeconds: Double = 0.35
    private static let campaignWinScrimFadeSeconds: Double = 0.9
    private static let campaignWinTextFadeSeconds: Double = 0.5
    private static let campaignWinArtifactsLiftSeconds: Double = 0.7
    /// Lift the rack from the bottom band toward mid-screen under "Congratulations!".
    private static let campaignWinArtifactsLiftPoints: CGFloat = 200

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

            if showsContent && !campaignWinActive {
                PlanetStripScrollHints(
                    canScrollLeft: canScrollLeft,
                    canScrollRight: canScrollRight
                )
            }

            if campaignWinActive {
                CampaignWinOverlay(
                    spriteLibrary: session.spriteLibrary,
                    scrimOpacity: campaignWinScrimOpacity,
                    textOpacity: campaignWinTextOpacity,
                    isInteractive: campaignWinInteractive,
                    onFinished: {
                        router.popOrShowMenu()
                    }
                ) {
                    campaignWinArtifacts
                }
            }

            if let messageOverlay {
                MessageOverlay(
                    title: messageOverlay.title,
                    accessibilityRootID: messageOverlay.rootID,
                    accessibilityTitleID: messageOverlay.titleID,
                    speakStringID: messageOverlay.stringID
                ) {
                    self.messageOverlay = nil
                }
                .environment(
                    \.overlayDismissSeconds,
                    session.appConfig.display.overlayDismissSeconds
                )
            }

            if let selectedLevel, let detailMode {
                let menuIcons = session.spriteLibrary.uiImages(id: MenuSpritesConfig.iconsID)?
                    .map(\.image) ?? []
                let continueIcon = menuIcons.indices.contains(MenuSpritesConfig.Icon.continueGame.rawValue)
                    ? menuIcons[MenuSpritesConfig.Icon.continueGame.rawValue]
                    : nil
                let newGameIcon = menuIcons.indices.contains(MenuSpritesConfig.Icon.newGame.rawValue)
                    ? menuIcons[MenuSpritesConfig.Icon.newGame.rawValue]
                    : nil
                let exitIcon = menuIcons.indices.contains(MenuSpritesConfig.Icon.exit.rawValue)
                    ? menuIcons[MenuSpritesConfig.Icon.exit.rawValue]
                    : nil
                LevelDetailOverlay(
                    levelName: selectedLevel.displayName,
                    nameStringID: selectedLevel.nameStringID,
                    mode: detailMode,
                    startIcon: detailMode == .continueAdventure ? continueIcon : newGameIcon,
                    secondaryIcon: detailMode == .continueAdventure ? newGameIcon : exitIcon,
                    onStart: {
                        startLevel(selectedLevel, launchMode: detailMode.launchMode)
                    },
                    onStartOver: {
                        let stars = session.playerState?.totalStars ?? 0
                        self.detailMode = .replay(highestStars: stars)
                    },
                    onDismiss: {
                        dismissLevelDetail()
                    }
                )
            }
        }
        .playScreenMusic("level_select")
        .onAppear { MemoryProbe.mark("level-select") }
        .task {
            await session.refreshContinueEligibility()
            // Assets are warmed on the loading screen; refresh icons if progression changed.
            let ids = viewModel.inventoryTreasureIDs(progressionEpoch: progressionEpoch)
            inventoryIcons = viewModel.refreshInventoryIcons(ids: ids)
            await loadCurrentPlayerAvatar()
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

        // Final planet cleared with a full rack — campaign victory after the artifact lands.
        let allLevelsComplete = viewModel.completedLevels.count == viewModel.levels.count
        if celebratingUnlockResource == nil, allLevelsComplete {
            await presentCampaignWinIfNeeded()
        }
    }

    @MainActor
    private func presentCampaignWinIfNeeded() async {
        guard !campaignWinActive else { return }
        campaignWinActive = true
        campaignWinScrimOpacity = 0
        campaignWinTextOpacity = 0
        campaignWinInteractive = false
        campaignWinArtifactsOffsetY = 0
        campaignWinSparklesActive = false

        withAnimation(.easeInOut(duration: Self.campaignWinScrimFadeSeconds)) {
            campaignWinScrimOpacity = 1
        }
        try? await Task.sleep(
            nanoseconds: UInt64(Self.campaignWinScrimFadeSeconds * 1_000_000_000)
        )
        guard !Task.isCancelled else { return }

        BackgroundMusicController.shared.applyScreen(named: "win_game")
        Strings.speak("campaign_win_congratulations")
        campaignWinSparklesActive = true
        withAnimation(.easeIn(duration: Self.campaignWinTextFadeSeconds)) {
            campaignWinTextOpacity = 1
        }
        withAnimation(.easeOut(duration: Self.campaignWinArtifactsLiftSeconds)) {
            campaignWinArtifactsOffsetY = -Self.campaignWinArtifactsLiftPoints
        }
        campaignWinInteractive = true

        // Match SparkleBurstView emit window, then clear so idle gleam can resume.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled else { return }
        campaignWinSparklesActive = false
    }

    /// Inventory rack starts in the bottom band, then lifts when the win text fades in.
    private var campaignWinArtifacts: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 16) {
                Color.clear
                    .frame(width: 52, height: 52)
                InventoryRackView(
                    session: session,
                    inventoryLevels: viewModel.inventoryLevels(progressionEpoch: progressionEpoch),
                    inventoryTreasureIDs: viewModel.inventoryTreasureIDs(progressionEpoch: progressionEpoch),
                    isContentReady: showsContent,
                    celebratingInventoryResource: nil,
                    celebrationRevealed: true,
                    inventorySparklesActive: campaignWinSparklesActive,
                    inventoryIcons: $inventoryIcons
                )
                .frame(maxWidth: AppChrome.maxContentWidth)
                .frame(maxWidth: .infinity)
                Color.clear
                    .frame(width: 52, height: 52)
            }
        }
        .offset(y: campaignWinArtifactsOffsetY)
        .appScreenContentPadding()
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
                completedHighScores: viewModel.completedHighScores,
                dadModeUnlocked: viewModel.dadModeUnlocked(progressionEpoch: progressionEpoch),
                celebratingUnlockResource: celebratingUnlockResource,
                celebrationRevealed: celebrationRevealed,
                planetSparklesActive: planetSparklesActive,
                playerLocationResourceName: playerLocationResourceName,
                playerAvatarImage: playerAvatarImage,
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
                    accessibilityLabel: Strings.text("button_back")
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
                    accessibilityLabel: Strings.text("level_select_dad_mode")
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

    private var playerLocationResourceName: String? {
        playerAvatarReady ? viewModel.lastPlayedResourceName : nil
    }

    @MainActor
    private func loadCurrentPlayerAvatar() async {
        defer { playerAvatarReady = true }
        guard let name = session.currentPlayerName,
              let data = await session.playerStore.loadAvatar(for: name) else {
            playerAvatarImage = nil
            return
        }
        playerAvatarImage = PlayerAvatarImage.uiImage(from: data)
    }

    private func handleLevelTap(_ level: LevelDescriptor) {
        if let message = viewModel.handleLevelTap(
            level,
            progressionEpoch: progressionEpoch
        ) {
            playMenuSound("button_click")
            messageOverlay = message
            return
        }

        playMenuSound("button_click")
        let mode = viewModel.detailMode(for: level.resourceName)
        if mode == .firstStart {
            Strings.speak(level.nameStringID)
        }
        selectedLevel = level
        detailMode = mode
    }

    private func dismissLevelDetail() {
        selectedLevel = nil
        detailMode = nil
    }

    private func startLevel(_ level: LevelDescriptor, launchMode: GameLaunchMode) {
        dismissLevelDetail()
        Task {
            if launchMode == .newGame,
               viewModel.dadModeUnlocked(progressionEpoch: progressionEpoch) {
                await session.applyDadModeProgression(to: level.resourceName)
            }
            do {
                try session.selectLevel(resourceName: level.resourceName)
                router.navigate(to: .preparing(launchMode))
            } catch {
                // Ignore invalid/missing level resources.
            }
        }
    }
}
