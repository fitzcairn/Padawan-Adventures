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

    static let hudIconFadeDuration: TimeInterval = 0.2
    static let starStepNanoseconds: UInt64 = 280_000_000
    static let sparkleLingerNanoseconds: UInt64 = 700_000_000
    init(
        config: HudConfig,
        healthCount: Int = 0,
        energyCount: Int = 0,
        starsCount: Int = 0
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
        super.init(frame: .zero)
        setup(healthCount: healthCount, energyCount: energyCount, starsCount: starsCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === fleeButton || hit?.isDescendant(of: fleeButton) == true {
            return hit
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeInsets.update()
        if let sparkleLayer {
            sparkleLayer.emitterPosition = CGPoint(x: coinHost.bounds.midX, y: coinHost.bounds.midY)
            let side = max(coinHost.bounds.width, CGFloat(config.iconSize))
            sparkleLayer.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
        }
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
}
