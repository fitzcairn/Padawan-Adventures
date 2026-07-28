import SwiftUI
import UIKit

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let levels: [LevelDescriptor]
    private let screenBackground: String?

    @State private var messageOverlay: MessageKind?
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
    /// Resource whose treasure should fade in (first completion this session).
    @State private var celebratingInventoryResource: String?
    /// Planet that should animate from locked → unlocked.
    @State private var celebratingUnlockResource: String?
    /// When false during a celebration, show the pre-unlock visuals; then animate to true.
    @State private var celebrationRevealed = true
    @State private var inventorySparklesActive = false
    @State private var planetSparklesActive = false

    /// Planet diameter as a fraction of available content width (~18% ≈ 150pt on phone landscape).
    private static let planetDiameterFraction: CGFloat = 0.18
    /// Gap between planets relative to planet diameter (keeps strip density consistent across sizes).
    private static let planetSpacingToDiameter: CGFloat = 0.26
    /// Vertical jitter half-range relative to planet diameter.
    private static let planetJitterToDiameter: CGFloat = 0.32
    private let inventoryIconSide: CGFloat = 52
    private static let celebrationHoldNanoseconds: UInt64 = 350_000_000
    private static let celebrationRevealSeconds: TimeInterval = 0.85
    private static let celebrationSparkleNanoseconds: UInt64 = 1_200_000_000

    init(
        session: AppSession,
        router: FlowRouter,
        levels: [LevelDescriptor]? = nil
    ) {
        self.session = session
        self.router = router
        let resolvedLevels = levels ?? LevelCatalog.loadFromBundle()
        self.levels = resolvedLevels
        self.screenBackground = (try? ScreenConfig.loadFromBundle(named: "level_select"))?.background

        // Seed celebration from session so the first frame already hides the new item / lock.
        let pending = session.pendingLevelSelectCelebration
        let ordered = resolvedLevels.map(\.resourceName)
        _celebratingInventoryResource = State(initialValue: pending)
        _celebratingUnlockResource = State(
            initialValue: pending.flatMap {
                LevelProgression.resourceUnlockedByCompleting($0, orderedLevels: ordered)
            }
        )
        _celebrationRevealed = State(initialValue: pending == nil)

        // Prefer already-warmed treasure icons so inventory never flashes SF Symbols.
        var seededIcons: [String: UIImage] = [:]
        for level in resolvedLevels {
            if let id = level.treasure, let image = session.treasureIcons.uiImage(id: id) {
                seededIcons[id] = image
            }
        }
        _inventoryIcons = State(initialValue: seededIcons)
        // Bootstrap warms planets / icons / coin; show content on first frame when present.
        let planetsReady = resolvedLevels.allSatisfy { level in
            level.sprite == nil
                || session.spriteLibrary.uiImage(id: level.resourceName, named: "idle") != nil
        }
        _isContentReady = State(initialValue: planetsReady && ScoreCoinIcon.uiImage() != nil)
    }

    /// Earned parts in catalog order; completing a level is what grants its treasure.
    private var inventoryLevels: [LevelDescriptor] {
        _ = progressionEpoch
        let completed = completedLevels
        return levels.filter { completed.contains($0.resourceName) }
    }

    private var inventoryTreasureIDs: [String] {
        inventoryLevels.compactMap(\.treasure)
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
            AppScreen(
                backgroundNamed: screenBackground,
                backgroundLibrary: session.backgroundLibrary
            ) {
                if isContentReady {
                    VStack(spacing: 0) {
                        starCountHeader
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
                    }
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("levelSelect.loading")
                }
            }

            if isContentReady {
                // Measure full-screen safe areas (AppScreen zeroes child insets) so arrows
                // sit clear of the Dynamic Island in landscape.
                GeometryReader { geo in
                    let insets = ScreenLayout.insets(size: geo.size, safeArea: geo.safeAreaInsets)
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
        .playScreenMusic("level_select")
        .task {
            // Assets are warmed on the loading screen; refresh icons if progression changed.
            refreshInventoryIcons(ids: inventoryTreasureIDs)
            isContentReady = true
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
            orderedLevels: orderedResourceNames
        )
        celebrationRevealed = false
        inventorySparklesActive = false
        planetSparklesActive = false

        // Warm the new treasure icon before fading it in.
        if let treasureID = levels.first(where: { $0.resourceName == completed })?.treasure {
            await session.ensureTreasureIconsLoaded(ids: [treasureID])
            if let image = session.treasureIcons.uiImage(id: treasureID) {
                inventoryIcons[treasureID] = image
            }
        }

        try? await Task.sleep(nanoseconds: Self.celebrationHoldNanoseconds)
        guard !Task.isCancelled else { return }

        inventorySparklesActive = true
        planetSparklesActive = celebratingUnlockResource != nil
        withAnimation(.easeIn(duration: Self.celebrationRevealSeconds)) {
            celebrationRevealed = true
        }

        try? await Task.sleep(nanoseconds: Self.celebrationSparkleNanoseconds)
        guard !Task.isCancelled else { return }
        inventorySparklesActive = false
        planetSparklesActive = false
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

    private var planetStrip: some View {
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

    private func scrollHintArrow(systemName: String, visible: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(AppChrome.primaryTextColor)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: visible)
            .accessibilityHidden(true)
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
            handleLevelTap(level)
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
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            ForEach(inventoryLevels, id: \.resourceName) { level in
                inventoryIcon(for: level)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 72)
        .task(id: inventoryTreasureIDs) {
            guard isContentReady else { return }
            let ids = inventoryTreasureIDs
            await session.ensureTreasureIconsLoaded(ids: ids)
            refreshInventoryIcons(ids: ids)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("levelSelect.inventory")
        .accessibilityLabel("Inventory")
    }

    private func refreshInventoryIcons(ids: [String]) {
        var icons: [String: UIImage] = [:]
        for id in ids {
            if let image = session.treasureIcons.uiImage(id: id) {
                icons[id] = image
            }
        }
        inventoryIcons = icons
    }

    @ViewBuilder
    private func inventoryIcon(for level: LevelDescriptor) -> some View {
        let isCelebrating = celebratingInventoryResource == level.resourceName
        let opacity: Double = (isCelebrating && !celebrationRevealed) ? 0 : 1

        ZStack {
            if let id = level.treasure, let image = inventoryIcons[id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: inventoryIconSide, height: inventoryIconSide)
                    // Parts stand upright in the sheets; lay them flat along the rack.
                    .rotationEffect(.degrees(90))
                    .accessibilityIdentifier("levelSelect.inventory.\(id)")
                    .accessibilityLabel(level.displayName)
            } else {
                Image(systemName: level.artifact)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
                    .frame(width: inventoryIconSide, height: inventoryIconSide)
                    .accessibilityIdentifier("levelSelect.inventory.\(level.artifact)")
            }

            if isCelebrating {
                SparkleBurstView(isActive: inventorySparklesActive, diameter: inventoryIconSide)
                    .frame(width: inventoryIconSide, height: inventoryIconSide)
                    .allowsHitTesting(false)
            }
        }
        .opacity(opacity)
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
