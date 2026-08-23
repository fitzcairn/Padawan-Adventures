import Combine
import SpriteKit
import SwiftUI
import UIKit

struct MerchantMinigameView: View {
    let appSession: AppSession
    let resourceName: String
    let tileSeed: UInt64
    let onFinished: (MinigameOutcome) -> Void

    @StateObject private var session: MerchantShopSession

    init(
        appSession: AppSession,
        resourceName: String,
        tileSeed: UInt64,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) {
        self.appSession = appSession
        self.resourceName = resourceName
        self.tileSeed = tileSeed
        self.onFinished = onFinished
        _session = StateObject(
            wrappedValue: MerchantShopSession(
                appSession: appSession,
                resourceName: resourceName,
                tileSeed: tileSeed
            )
        )
    }

    var body: some View {
        MinigameShellView(
            scene: session.scene,
            accessibilityRootID: "minigame.merchant",
            ensureScene: session.ensureScene(size:),
            updateSceneSize: session.updateSceneSizeIfNeeded(_:),
            includesHUDLayer: false,
            onLeave: { onFinished(.abandoned) },
            leaveEnabled: session.activeModal == nil && session.draggedID == nil,
            hud: { EmptyView() },
            overlay: { merchantOverlay }
        )
        .onAppear { session.playStartFxIfNeeded() }
    }

    @ViewBuilder
    private var merchantOverlay: some View {
        GeometryReader { geo in
            let insets = ScreenLayout.insets(
                size: geo.size,
                safeArea: ScreenLayout.safeArea(fromProxy: geo.safeAreaInsets)
            )
            let hudHeight = geo.size.height
            let displayed = MerchantWares.aspectFit(imageSize: session.backgroundImageSize, in: geo.size)
            let disk = MerchantWares.disk(in: displayed)
            let slotSide = InventorySlotLayout.compute(
                hudHeight: hudHeight,
                availableHeight: hudHeight
            ).side
            let layout = MerchantWares.layout(
                itemIDs: session.matWareIDs,
                diskCenter: disk.center,
                radius: disk.radius,
                slotSide: slotSide,
                pixelSizes: session.warePixelSizes
            )
            ZStack {
                waresLayer(layout: layout, size: geo.size)

                InventorySlotStack(
                    slots: session.slots,
                    catalog: session.catalog,
                    hudHeight: hudHeight,
                    interaction: .shop,
                    highlightedIndex: session.highlightedSlot
                )
                .frame(width: hudHeight * InventorySlotLayout.columnWidthFraction)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, insets.leading)
                .allowsHitTesting(false)

                coinHUD
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)

                dragSprite(layout: layout)

                if session.burstProgress < 1 {
                    MerchantCoinBurstOverlay(
                        origin: CGPoint(x: geo.size.width / 2, y: geo.size.height - 48),
                        progress: session.burstProgress
                    )
                }

                switch session.activeModal {
                case .inspect(let id):
                    if let item = session.catalog[id] {
                        MerchantInspectModal(itemID: id, item: item) {
                            session.activeModal = nil
                        }
                    }
                case .replace(let id, let slot):
                    MerchantReplaceModal(
                        onCancel: { session.cancelReplace() },
                        onConfirm: { Task { await session.confirmReplace(itemID: id, slot: slot) } }
                    )
                case .none:
                    EmptyView()
                }
            }
            .coordinateSpace(name: "merchantShop")
            .onPreferenceChange(InventorySlotFrameKey.self) { session.slotFrames = $0 }
        }
    }

    private var coinHUD: some View {
        HStack(spacing: 10) {
            ScoreCoinIcon.Image(side: 36)
            Text("\(session.displayedCoins)")
                .font(AppFont.swiftUI(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .appCopyShadow()
                .accessibilityIdentifier("merchant.coins")
        }
    }

    @ViewBuilder
    private func waresLayer(layout: MerchantWaresLayout, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.stacks, id: \.itemID) { stack in
                if let item = session.catalog[stack.itemID] {
                    MerchantWareStackView(
                        itemID: stack.itemID,
                        item: item,
                        price: item.displayedPrice(levelOrder: session.levelOrder),
                        frame: stack,
                        isPickedUp: session.draggedID == stack.itemID,
                        flashesRed: session.flashingID == stack.itemID
                            && session.draggedID != stack.itemID,
                        enabled: session.canBeginWareGesture(stack.itemID)
                    ) { event in
                        session.handleWareGesture(itemID: stack.itemID, event: event)
                    }
                    .frame(width: stack.bounds.width, height: stack.bounds.height)
                    .position(x: stack.bounds.midX, y: stack.bounds.midY)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(session.activeModal == nil && !session.isReturningHome)
    }

    @ViewBuilder
    private func dragSprite(layout: MerchantWaresLayout) -> some View {
        if let itemID = session.draggedID,
           let item = session.catalog[itemID],
           let stack = layout.stacks.first(where: { $0.itemID == itemID })
        {
            MerchantWareSpriteView(itemID: itemID, sprite: item.sprite, showsShadow: true)
                .frame(width: stack.spriteFrame.width, height: stack.spriteFrame.height)
                .overlay {
                    if session.flashingID == itemID {
                        Color.red.opacity(0.45)
                    }
                }
                .position(
                    x: stack.spriteFrame.midX + session.dragTranslation.width,
                    y: stack.spriteFrame.midY + session.dragTranslation.height
                )
                .animation(
                    session.isReturningHome
                        ? .easeInOut(duration: session.returnAnimationDuration)
                        : nil,
                    value: session.dragTranslation
                )
                .transition(.identity)
                .zIndex(50)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

enum MerchantWareGesture {
    case changed(translation: CGSize, location: CGPoint)
    case ended(translation: CGSize, location: CGPoint)
}

private struct MerchantWareStackView: View {
    let itemID: String
    let item: MerchantItemDefinition
    let price: Int
    let frame: MerchantWareStackFrame
    let isPickedUp: Bool
    let flashesRed: Bool
    let enabled: Bool
    let onGesture: (MerchantWareGesture) -> Void

    var body: some View {
        let local = frame.bounds
        ZStack(alignment: .topLeading) {
            MerchantWareSpriteView(itemID: itemID, sprite: item.sprite, showsShadow: true)
                .frame(width: frame.spriteFrame.width, height: frame.spriteFrame.height)
                .opacity(isPickedUp ? 0 : 1)
                .position(x: localX(frame.spriteFrame.midX), y: localY(frame.spriteFrame.midY))
                .overlay {
                    if flashesRed {
                        Color.red.opacity(0.45)
                    }
                }
                .allowsHitTesting(false)

            ScoreCoinIcon.Image(side: frame.coinFrame.width)
                .position(x: localX(frame.coinFrame.midX), y: localY(frame.coinFrame.midY))
                .allowsHitTesting(false)

            Text("\(price)")
                .font(AppFont.swiftUI(size: max(12, frame.priceFrame.height * 0.85), weight: .bold))
                .foregroundStyle(StarWarsConsolePalette.crtBlue)
                .shadow(color: StarWarsConsolePalette.crtGlow, radius: 2)
                .position(x: localX(frame.priceFrame.midX), y: localY(frame.priceFrame.midY))
                .allowsHitTesting(false)

            Color.clear
                .frame(width: frame.spriteFrame.width, height: frame.spriteFrame.height)
                .contentShape(Rectangle())
                .position(x: localX(frame.spriteFrame.midX), y: localY(frame.spriteFrame.midY))
                .gesture(drag)
                .zIndex(20)
        }
        .frame(width: local.width, height: local.height)
        .allowsHitTesting(enabled)
        .accessibilityIdentifier("merchant.ware.\(itemID)")
    }

    private func localX(_ x: CGFloat) -> CGFloat {
        x - frame.bounds.minX
    }

    private func localY(_ y: CGFloat) -> CGFloat {
        y - frame.bounds.minY
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("merchantShop"))
            .onChanged { value in
                guard enabled else { return }
                onGesture(.changed(translation: value.translation, location: value.location))
            }
            .onEnded { value in
                guard enabled else { return }
                onGesture(.ended(translation: value.translation, location: value.location))
            }
    }
}

@MainActor
final class MerchantShopSession: ObservableObject {
    enum Modal: Equatable {
        case inspect(String)
        case replace(itemID: String, slot: Int)
    }

    let appSession: AppSession
    let resourceName: String
    let catalog: [String: MerchantItemDefinition]
    let wareIDs: [String]
    let levelOrder: Int

    @Published var scene: MerchantScene?
    @Published var slots: [String]
    @Published var displayedCoins: Int
    @Published var activeModal: Modal?
    @Published var draggedID: String?
    @Published var dragTranslation: CGSize = .zero
    @Published var highlightedSlot: Int?
    @Published var flashingID: String?
    @Published var isReturningHome = false
    @Published var returnAnimationDuration: TimeInterval = 0.32
    @Published var slotFrames: [Int: CGRect] = [:]
    @Published var burstProgress: CGFloat = 1
    @Published var warePixelSizes: [String: CGSize] = [:]
    @Published private var purchasedThisVisit: Set<String> = []

    var backgroundImageSize: CGSize {
        appSession.backgroundLibrary.uiImage(named: "merchant-bg")?.size
            ?? CGSize(width: 16, height: 9)
    }

    private let backgroundLibrary: BackgroundLibrary
    private var dragIsMove = false
    private var spendTask: Task<Void, Never>?
    private var returnTask: Task<Void, Never>?
    private let tapSlop: CGFloat = 12
    private let spendDuration: TimeInterval = 1.2
    private var didPlayStartFx = false

    private lazy var sceneHost = MinigameSceneHost<MerchantScene>(
        prepare: { [backgroundLibrary] in
            await backgroundLibrary.ensureLoaded(named: "merchant-bg")
        },
        make: { [backgroundLibrary] size in
            MerchantScene(
                size: size,
                backgroundImage: backgroundLibrary.uiImage(named: "merchant-bg")
            )
        },
        onReady: { [weak self] created in
            self?.scene = created
        }
    )

    init(appSession: AppSession, resourceName: String, tileSeed: UInt64) {
        self.appSession = appSession
        self.resourceName = resourceName
        self.catalog = appSession.itemsConfig.merchant
        self.levelOrder = max(appSession.selectedLevel.order, 1)
        self.wareIDs = MerchantWares.selectIDs(
            catalog: appSession.itemsConfig.merchant,
            levelOrder: appSession.selectedLevel.order,
            seed: tileSeed
        )
        self.slots = PlayerGameState.normalizedItemSlots(appSession.playerState?.itemSlots ?? [])
        self.displayedCoins = appSession.playerState?.levels[resourceName]?.starsCurrent ?? 0
        self.backgroundLibrary = appSession.backgroundLibrary
        var sizes: [String: CGSize] = [:]
        for (id, item) in catalog {
            sizes[id] = MerchantWareIcon.pixelSize(id: id, sprite: item.sprite)
        }
        self.warePixelSizes = sizes
    }

    func ensureScene(size: CGSize) {
        sceneHost.ensureScene(size: size)
    }

    func updateSceneSizeIfNeeded(_ size: CGSize) {
        sceneHost.updateSceneSizeIfNeeded(size)
    }

    func playStartFxIfNeeded() {
        guard !didPlayStartFx else { return }
        didPlayStartFx = true
        SoundEffectsController.shared.play(
            event: "contact",
            from: appSession.npcsConfig.fx(for: MerchantSpawner.npcID)
        )
    }

    func isSoldOut(_ itemID: String) -> Bool {
        guard let item = catalog[itemID] else { return false }
        let held = MerchantItemDefinition.heldCount(itemID: itemID, in: slots)
        return !item.canHoldAnother(held: held)
    }

    /// Wares still offered on the mat. A successful buy (or already holding the cap)
    /// removes the sprite and price from the background.
    var matWareIDs: [String] {
        wareIDs.filter { !purchasedThisVisit.contains($0) && !isSoldOut($0) }
    }

    func canBeginWareGesture(_ itemID: String) -> Bool {
        activeModal == nil
            && !isReturningHome
            && (draggedID == nil || draggedID == itemID)
    }

    func handleWareGesture(itemID: String, event: MerchantWareGesture) {
        switch event {
        case .changed(let translation, let location):
            guard !isReturningHome, activeModal == nil else { return }
            if hypot(translation.width, translation.height) >= tapSlop {
                dragIsMove = true
                draggedID = itemID
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = translation
                    highlightedSlot = MerchantPurchase.slotIndex(containing: location, frames: slotFrames)
                }
            }
        case .ended(let translation, let location):
            let wasDrag = dragIsMove
            dragIsMove = false
            if wasDrag {
                highlightedSlot = MerchantPurchase.slotIndex(containing: location, frames: slotFrames)
                Task { await resolveDrop(itemID: itemID, at: location) }
            } else {
                clearLift()
                if hypot(translation.width, translation.height) < tapSlop {
                    activeModal = .inspect(itemID)
                }
            }
        }
    }

    private func resolveDrop(itemID: String, at location: CGPoint) async {
        let price = catalog[itemID]?.displayedPrice(levelOrder: levelOrder) ?? 0
        let coins = appSession.playerState?.levels[resourceName]?.starsCurrent ?? 0
        let slot = MerchantPurchase.slotIndex(containing: location, frames: slotFrames)
        let outcome = MerchantPurchase.outcome(
            itemID: itemID,
            slotIndex: slot,
            slots: slots,
            price: price,
            coins: coins,
            limit: catalog[itemID]?.limit ?? 0
        )
        switch outcome {
        case .ignoredOutside, .sameItemInSlot:
            await returnWareHome(playError: false)
        case .soldOut, .cannotAfford:
            await returnWareHome(playError: true)
        case .purchaseEmptySlot:
            guard let slot else {
                await returnWareHome(playError: false)
                return
            }
            await completePurchase(itemID: itemID, slot: slot, price: price)
        case .confirmReplace:
            guard let slot else {
                await returnWareHome(playError: false)
                return
            }
            activeModal = .replace(itemID: itemID, slot: slot)
        }
    }

    func cancelReplace() {
        activeModal = nil
        returnTask?.cancel()
        returnTask = Task { await returnWareHome(playError: false) }
    }

    func confirmReplace(itemID: String, slot: Int) async {
        let price = catalog[itemID]?.displayedPrice(levelOrder: levelOrder) ?? 0
        activeModal = nil
        await completePurchase(itemID: itemID, slot: slot, price: price)
    }

    private func completePurchase(itemID: String, slot: Int, price: Int) async {
        let previousDisplayed = displayedCoins
        let spent = await appSession.purchaseMerchantWare(
            resourceName: resourceName,
            itemID: itemID,
            slot: slot,
            price: price
        )
        guard spent else {
            await returnWareHome(playError: true)
            return
        }
        purchasedThisVisit.insert(itemID)
        slots = PlayerGameState.normalizedItemSlots(appSession.playerState?.itemSlots ?? slots)
        clearLift()
        SoundEffectsController.shared.play(trackID: "merchant-purchase")
        displayedCoins = previousDisplayed
        burstProgress = 0
        Strings.speak("merchant_coins_spent")
        animateSpend(from: previousDisplayed, to: previousDisplayed - price, amount: price)
    }

    private func returnWareHome(playError: Bool) async {
        guard draggedID != nil else { return }
        if playError {
            SoundEffectsController.shared.playCommon(event: "error")
            flashingID = draggedID
        }
        returnAnimationDuration = MerchantDragMotion.returnDuration(for: dragTranslation)
        isReturningHome = true
        withAnimation(.easeInOut(duration: returnAnimationDuration)) {
            dragTranslation = .zero
            highlightedSlot = nil
        }
        let nanos = UInt64(returnAnimationDuration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
        guard !Task.isCancelled else { return }
        clearLift()
    }

    private func clearLift() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draggedID = nil
            dragTranslation = .zero
            highlightedSlot = nil
            isReturningHome = false
            flashingID = nil
        }
    }

    private func animateSpend(from: Int, to: Int, amount: Int) {
        spendTask?.cancel()
        spendTask = Task { @MainActor in
            let steps = 20
            let stepNanos = UInt64((spendDuration / Double(steps)) * 1_000_000_000)
            for step in 0...steps {
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let remaining = max(0, Int((Double(amount) * (1 - t)).rounded()))
                displayedCoins = from - (amount - remaining)
                burstProgress = CGFloat(t)
                if step < steps {
                    try? await Task.sleep(nanoseconds: stepNanos)
                }
            }
            displayedCoins = to
            burstProgress = 1
        }
    }
}

enum MerchantDragMotion {
    /// Time for a lifted ware to ease back onto the mat. Scales with travel so
    /// short cancels stay snappy and long drags still look smooth.
    static func returnDuration(for translation: CGSize) -> TimeInterval {
        let distance = hypot(translation.width, translation.height)
        return min(0.48, max(0.22, TimeInterval(distance / 850)))
    }
}
