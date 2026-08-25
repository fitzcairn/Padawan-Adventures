import SwiftUI
import UIKit

@MainActor
@Observable
final class PlayerSelectModel {
    var playerNames: [String] = []
    var avatarDataByName: [String: Data] = [:]
    var isShowingNewPlayerAlert = false
    var isShowingDeleteConfirm = false
    var isShowingDuplicateNameAlert = false
    var newPlayerName = ""
    var playerPendingDelete: String?
    var attemptedDuplicateName = ""
    var isCreatingAvatar = false

    private let session: AppSession
    private let frontCamera: any FrontCameraAvailability

    init(
        session: AppSession,
        frontCamera: any FrontCameraAvailability = LiveFrontCameraAvailability()
    ) {
        self.session = session
        self.frontCamera = frontCamera
    }

    enum CreatePlayerOutcome: Equatable {
        case failed
        case showSelfie
        case showMenu
    }

    func reloadPlayers() async {
        playerNames = (try? await session.playerStore.listPlayers()) ?? []
        var avatars: [String: Data] = [:]
        for name in playerNames {
            if let data = await session.playerStore.loadAvatar(for: name) {
                avatars[name] = data
            }
        }
        avatarDataByName = avatars
    }

    func selectPlayer(named name: String) async -> Bool {
        do {
            try await session.bindPlayer(name: name)
            return true
        } catch {
            await reloadPlayers()
            return false
        }
    }

    func beginCreatePlayer() {
        newPlayerName = ""
        isShowingNewPlayerAlert = true
    }

    func createPlayer() async -> CreatePlayerOutcome {
        let trimmed = PlayerStateStore.normalizedName(newPlayerName)
        guard !trimmed.isEmpty else {
            isShowingNewPlayerAlert = true
            return .failed
        }

        do {
            try await session.createAndBindPlayer(name: trimmed)
        } catch PlayerStateError.nameNotUnique {
            attemptedDuplicateName = trimmed
            isShowingDuplicateNameAlert = true
            return .failed
        } catch {
            newPlayerName = trimmed
            isShowingNewPlayerAlert = true
            return .failed
        }

        if frontCamera.isFrontCameraAvailable {
            return .showSelfie
        }

        isCreatingAvatar = true
        defer { isCreatingAvatar = false }
        let jpeg = await SillyFaceAvatarGenerator.generateJPEG(seedName: trimmed)
        if !jpeg.isEmpty {
            try? await session.playerStore.saveAvatar(jpeg, for: trimmed)
        }
        return .showMenu
    }

    func confirmDelete(playerName: String) {
        playerPendingDelete = playerName
        isShowingDeleteConfirm = true
    }

    func deletePendingPlayer() async {
        guard let name = playerPendingDelete else { return }
        try? await session.deletePlayer(name: name)
        playerPendingDelete = nil
        await reloadPlayers()
    }

    func retryAfterDuplicate() {
        newPlayerName = attemptedDuplicateName
        isShowingNewPlayerAlert = true
    }
}

struct PlayerSelectView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var model: PlayerSelectModel
    @State private var isContentReady = false

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        _model = State(initialValue: PlayerSelectModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        AppScreen {
            if isContentReady {
                VStack(spacing: 16) {
                    AppTitleText(
                        text: Strings.text("player_select_title"),
                        size: 28,
                        weight: .semibold
                    )
                        .accessibilityIdentifier("playerSelect.title")

                    ScrollView {
                        VStack(spacing: 12) {
                            if model.playerNames.isEmpty {
                                AppTitleText(
                                    text: Strings.text("player_select_empty"),
                                    size: 16,
                                    weight: .regular,
                                    color: AppChrome.secondaryTextColor
                                )
                                .accessibilityIdentifier("playerSelect.empty")
                            } else {
                                ForEach(model.playerNames, id: \.self) { name in
                                    playerRow(name: name)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: AppChrome.maxContentWidth * 0.75)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                    AppLargeButton(
                        title: Strings.text("button_new"),
                        accessibilityID: "playerSelect.new"
                    ) {
                        model.beginCreatePlayer()
                    }
                    .disabled(model.isCreatingAvatar)
                    .frame(maxWidth: AppChrome.maxContentWidth * 0.75)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("playerSelect.loading")
            }
        }
        .playScreenMusic("player_select")
        .task {
            await model.reloadPlayers()
            isContentReady = true
        }
        .alert(Strings.text("player_new_title"), isPresented: $model.isShowingNewPlayerAlert) {
            TextField(Strings.text("player_name_placeholder"), text: $model.newPlayerName)
                .textInputAutocapitalization(.words)
            Button(Strings.text("button_cancel"), role: .cancel) {
                playMenuSound("button_click")
            }
            Button(Strings.text("button_ok")) {
                playMenuSound("button_click")
                Task {
                    switch await model.createPlayer() {
                    case .failed:
                        break
                    case .showSelfie:
                        router.showPlayerSelfie()
                    case .showMenu:
                        router.showMenu()
                    }
                }
            }
        } message: {
            Text(Strings.text("player_new_message"))
        }
        .alert(Strings.text("player_delete_title"), isPresented: $model.isShowingDeleteConfirm) {
            Button(Strings.text("button_cancel"), role: .cancel) {
                playMenuSound("button_click")
                model.playerPendingDelete = nil
            }
            Button(Strings.text("button_delete"), role: .destructive) {
                playMenuSound("button_click")
                Task { await model.deletePendingPlayer() }
            }
        } message: {
            Text(
                Strings.text(
                    "player_delete_message",
                    ["name": model.playerPendingDelete ?? ""]
                )
            )
        }
        .alert(
            Strings.text("player_name_taken_title"),
            isPresented: $model.isShowingDuplicateNameAlert
        ) {
            Button(Strings.text("button_ok")) {
                playMenuSound("button_click")
                model.retryAfterDuplicate()
            }
        } message: {
            Text(Strings.text("player_name_taken_message"))
        }
    }

    private func playerRow(name: String) -> some View {
        HStack(spacing: 12) {
            PlayerAvatarView(
                image: model.avatarDataByName[name].flatMap(PlayerAvatarImage.uiImage(from:)),
                accessibilityID: "playerSelect.avatar.\(name)"
            )

            AppLargeButton(
                title: name,
                accessibilityID: "playerSelect.player.\(name)"
            ) {
                Task {
                    if await model.selectPlayer(named: name) {
                        router.showMenu()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            AppCircularIconButton(
                systemName: "trash",
                size: 44,
                accessibilityID: "playerSelect.delete.\(name)",
                accessibilityLabel: Strings.text("button_delete")
            ) {
                model.confirmDelete(playerName: name)
            }
        }
    }
}
