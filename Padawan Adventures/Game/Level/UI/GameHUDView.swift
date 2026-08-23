import SwiftUI
import UIKit

final class GameHUDView: UIView {
    var onFleeTapped: (() -> Void)?

    let config: HudConfig
    let fleeButton: UIButton
    let heartsStack: UIStackView
    let boltsStack: UIStackView
    let heartImage: UIImage?
    let boltImage: UIImage?
    let scoreLabel = UILabel()
    let coinHost = UIView()
    let coinImageView: UIImageView
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    var displayedStarCount = 0
    var starAwardTask: Task<Void, Never>?
    var sparkleLayer: CAEmitterLayer?
    var sparkleStopWorkItem: DispatchWorkItem?
    var onInventorySlotTapped: ((Int, String) -> Void)?
    private var merchantCatalog: [String: MerchantItemDefinition] = [:]
    private var inventorySlots: [String] = PlayerGameState.emptyItemSlots
    private var inventoryHosting: UIHostingController<InventorySlotStack>?
    private let inventoryHostView = UIView()
    private var inventoryHeightConstraint: NSLayoutConstraint?
    private var fadingSlotItems: [Int: String] = [:]
    private var fadeTasks: [Int: Task<Void, Never>] = [:]
    private var lastInventoryHudHeight: CGFloat = 0

    static let hudIconFadeDuration: TimeInterval = 0.2
    static let starStepNanoseconds: UInt64 = 280_000_000
    static let sparkleLingerNanoseconds: UInt64 = 700_000_000
    init(
        config: HudConfig,
        healthCount: Int = 0,
        energyCount: Int = 0,
        starsCount: Int = 0,
        inventorySlots: [String] = PlayerGameState.emptyItemSlots,
        merchantCatalog: [String: MerchantItemDefinition] = [:]
    ) {
        self.config = config
        self.fleeButton = Self.makeFleeButton()
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.boltsStack = Self.makeIconStack(spacing: config.iconSpacing)
        // Trailing-aligned row that grows left as icons are inserted.
        self.boltsStack.semanticContentAttribute = .forceRightToLeft
        let size = CGFloat(config.iconSize)
        self.heartImage = HudVitalIcon.health.makeUIImage(pointSize: size)
        self.boltImage = HudVitalIcon.energy.makeUIImage(pointSize: size)
        self.coinImageView = ScoreCoinIcon.makeImageView(side: size)
        self.displayedStarCount = max(starsCount, 0)
        self.inventorySlots = PlayerGameState.normalizedItemSlots(inventorySlots)
        self.merchantCatalog = merchantCatalog
        super.init(frame: .zero)
        setup(healthCount: healthCount, energyCount: energyCount, starsCount: starsCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let fleePoint = convert(point, to: fleeButton)
        if fleeButton.bounds.contains(fleePoint) {
            return fleeButton.hitTest(fleePoint, with: event) ?? fleeButton
        }
        let inventoryPoint = convert(point, to: inventoryHostView)
        if inventoryHostView.bounds.contains(inventoryPoint) {
            return inventoryHostView.hitTest(inventoryPoint, with: event)
        }
        return nil
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        edgeInsets.update()
    }

    func addHeart() {
        addIcon(image: heartImage, to: heartsStack, animated: true)
    }

    func addBolt() {
        guard EnergyMechanic.isEnabled else { return }
        addIcon(image: boltImage, to: boltsStack, animated: true)
    }

    func removeHeart() {
        removeIcon(from: heartsStack, animated: true)
    }

    func removeBolt() {
        guard EnergyMechanic.isEnabled else { return }
        removeIcon(from: boltsStack, animated: true)
    }

    func setVitals(health: Int, energy: Int) {
        clearIcons(in: heartsStack)
        clearIcons(in: boltsStack)
        for _ in 0..<max(health, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
        guard EnergyMechanic.isEnabled else { return }
        for _ in 0..<max(energy, 0) {
            addIcon(image: boltImage, to: boltsStack, animated: false)
        }
    }

    func setStars(_ count: Int) {
        starAwardTask?.cancel()
        starAwardTask = nil
        stopCoinSparkles(immediate: true)
        displayedStarCount = max(count, 0)
        scoreLabel.text = "\(displayedStarCount)"
        scoreLabel.transform = .identity
    }

    func setInventorySlots(
        _ slots: [String],
        catalog: [String: MerchantItemDefinition]? = nil
    ) {
        inventorySlots = PlayerGameState.normalizedItemSlots(slots)
        if let catalog {
            merchantCatalog = catalog
        }
        if fadingSlotItems.isEmpty {
            rebuildInventoryRoot()
        } else {
            withAnimation(.easeOut(duration: InventorySlotStack.useFadeDuration)) {
                rebuildInventoryRoot()
            }
        }
    }

    private func useInventorySlot(index: Int, itemID: String) {
        guard fadingSlotItems[index] == nil else { return }
        fadingSlotItems[index] = itemID
        withAnimation(.easeOut(duration: InventorySlotStack.useFadeDuration)) {
            rebuildInventoryRoot()
        }
        onInventorySlotTapped?(index, itemID)
        fadeTasks[index]?.cancel()
        fadeTasks[index] = Task { @MainActor in
            let nanos = UInt64(InventorySlotStack.useFadeDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            fadingSlotItems[index] = nil
            fadeTasks[index] = nil
            rebuildInventoryRoot()
        }
    }

    func embedInventory(in parent: UIViewController) {
        guard let host = inventoryHosting, host.parent == nil else { return }
        parent.addChild(host)
        host.didMove(toParent: parent)
    }

    func setup(healthCount: Int, energyCount: Int, starsCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
        if EnergyMechanic.isEnabled {
            for _ in 0..<max(energyCount, 0) {
                addIcon(image: boltImage, to: boltsStack, animated: false)
            }
        }

        let score = makeScoreRow(starsCount: starsCount)
        fleeButton.addTarget(self, action: #selector(fleeTapped), for: .touchUpInside)

        addSubview(heartsStack)
        addSubview(boltsStack)
        addSubview(score)
        addSubview(fleeButton)
        installInventoryHost()

        let heartsTop = heartsStack.topAnchor.constraint(equalTo: topAnchor)
        let heartsLeading = heartsStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        let boltsTop = boltsStack.topAnchor.constraint(equalTo: topAnchor)
        let boltsTrailing = boltsStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        let scoreBottom = score.bottomAnchor.constraint(equalTo: bottomAnchor)
        let scoreLeading = score.leadingAnchor.constraint(equalTo: leadingAnchor)
        let fleeBottom = fleeButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        let fleeTrailing = fleeButton.trailingAnchor.constraint(equalTo: trailingAnchor)

        edgeInsets.addTop(heartsTop)
        edgeInsets.addLeading(heartsLeading)
        edgeInsets.addTop(boltsTop)
        edgeInsets.addTrailing(boltsTrailing)
        edgeInsets.addBottom(scoreBottom)
        edgeInsets.addLeading(scoreLeading)
        edgeInsets.addBottom(fleeBottom)
        edgeInsets.addTrailing(fleeTrailing)

        NSLayoutConstraint.activate([
            heartsTop,
            heartsLeading,

            boltsTop,
            boltsTrailing,

            scoreBottom,
            scoreLeading,

            fleeBottom,
            fleeTrailing,
        ])
        edgeInsets.update()
    }

    private func installInventoryHost() {
        inventoryHostView.translatesAutoresizingMaskIntoConstraints = false
        inventoryHostView.backgroundColor = .clear
        addSubview(inventoryHostView)

        let host = UIHostingController(rootView: makeInventoryStack())
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false
        inventoryHostView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: inventoryHostView.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: inventoryHostView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: inventoryHostView.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: inventoryHostView.bottomAnchor),
        ])
        inventoryHosting = host

        let trailing = inventoryHostView.trailingAnchor.constraint(equalTo: trailingAnchor)
        let centerY = inventoryHostView.centerYAnchor.constraint(equalTo: centerYAnchor)
        let height = inventoryHostView.heightAnchor.constraint(equalToConstant: 1)
        inventoryHeightConstraint = height
        edgeInsets.addTrailing(trailing)
        NSLayoutConstraint.activate([
            trailing,
            centerY,
            height,
            inventoryHostView.widthAnchor.constraint(
                equalTo: heightAnchor,
                multiplier: InventorySlotLayout.columnWidthFraction
            ),
        ])
        updateInventoryHostHeight(for: bounds.height)
    }

    private func makeInventoryStack() -> InventorySlotStack {
        InventorySlotStack(
            slots: inventorySlots,
            catalog: merchantCatalog,
            hudHeight: max(bounds.height, 1),
            interaction: .world,
            fadingItems: fadingSlotItems,
            onTapOccupied: { [weak self] index, itemID in
                self?.useInventorySlot(index: index, itemID: itemID)
            }
        )
    }

    private func rebuildInventoryRoot() {
        inventoryHosting?.rootView = makeInventoryStack()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeInsets.update()
        updateInventoryHostHeight(for: bounds.height)
        if let sparkleLayer {
            sparkleLayer.emitterPosition = CGPoint(x: coinHost.bounds.midX, y: coinHost.bounds.midY)
            let side = max(coinHost.bounds.width, CGFloat(config.iconSize))
            sparkleLayer.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
        }
    }

    private func updateInventoryHostHeight(for hudHeight: CGFloat) {
        guard hudHeight > 1, abs(hudHeight - lastInventoryHudHeight) > 1 else { return }
        lastInventoryHudHeight = hudHeight
        let layout = InventorySlotLayout.compute(
            hudHeight: hudHeight,
            availableHeight: hudHeight
        )
        inventoryHeightConstraint?.constant = layout.clusterHeight
        rebuildInventoryRoot()
    }
}
