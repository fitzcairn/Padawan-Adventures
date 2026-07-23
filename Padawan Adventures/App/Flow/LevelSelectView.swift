import SwiftUI

struct LevelSelectView: View {
    let session: AppSession
    let router: FlowRouter
    private let levels: [LevelDescriptor]

    @State private var messageOverlay: MessageKind?
    @State private var showPassword = false
    /// Bumps when Dad mode / progression changes so buttons re-read session state.
    @State private var progressionEpoch = 0

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
            VStack(spacing: 16) {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 22, weight: .semibold))
                    Text("\(session.playerState?.totalStars ?? 0)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppChrome.primaryTextColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("levelSelect.totalStars")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(levels, id: \.resourceName) { level in
                            levelButton(for: level)
                        }
                    }
                    .padding(.horizontal)
                }

                inventorySection
                    .padding(.horizontal, 24)
                    .frame(maxWidth: AppChrome.maxContentWidth)

                Spacer()

                AppLargeButton(title: "Back", accessibilityID: "levelSelect.back") {
                    if router.path.isEmpty {
                        router.showMenu()
                    } else {
                        router.pop()
                    }
                }
                .frame(maxWidth: 280)
                .padding(.bottom, 24)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showPassword = true
                    } label: {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppChrome.buttonForegroundColor)
                            .frame(width: 52, height: 52)
                            .background(AppChrome.buttonBackgroundColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("levelSelect.dadModeLock")
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
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

    @ViewBuilder
    private func levelButton(for level: LevelDescriptor) -> some View {
        let state = LevelProgression.unlockState(
            for: level.resourceName,
            orderedLevels: orderedResourceNames,
            completed: completedLevels,
            dadModeUnlocked: dadModeUnlocked
        )
        let background: Color = state == .completed
            ? Color.green
            : AppChrome.buttonBackgroundColor
        let opacity: Double = (!dadModeUnlocked && state == .locked) ? 0.5 : 1

        AppLargeButton(
            title: level.displayName,
            accessibilityID: "levelSelect.\(level.resourceName)",
            backgroundColor: background,
            opacity: opacity
        ) {
            handleLevelTap(level)
        }
        .frame(minWidth: 160)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Inventory")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppChrome.primaryTextColor)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
