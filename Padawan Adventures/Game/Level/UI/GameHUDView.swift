import UIKit

final class GameHUDView: UIView {
    var onFleeTapped: (() -> Void)?

    private let config: HudConfig
    private let fleeButton: UIButton
    private let heartsStack: UIStackView
    private let boltsStack: UIStackView
    private let heartImage: UIImage?
    private let boltImage: UIImage?
    private let scoreLabel = UILabel()
    private let coinHost = UIView()
    private let coinImageView: UIImageView
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    private var displayedStarCount = 0
    private var starAwardTask: Task<Void, Never>?
    private var sparkleLayer: CAEmitterLayer?
    private var sparkleStopWorkItem: DispatchWorkItem?

    private static let hudIconFadeDuration: TimeInterval = 0.2
    private static let starStepNanoseconds: UInt64 = 280_000_000
    private static let sparkleLingerNanoseconds: UInt64 = 700_000_000

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
        addIcon(image: boltImage, to: boltsStack, animated: true)
    }

    func removeHeart() {
        removeIcon(from: heartsStack, animated: true)
    }

    func removeBolt() {
        removeIcon(from: boltsStack, animated: true)
    }

    func setVitals(health: Int, energy: Int) {
        clearIcons(in: heartsStack)
        clearIcons(in: boltsStack)
        for _ in 0..<max(health, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
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

    /// Sparkles the HUD coin and counts the score label from `from` up to `to`.
    @MainActor
    func animateStarAward(from: Int, to: Int) async {
        let start = max(from, 0)
        let end = max(to, start)
        starAwardTask?.cancel()
        stopCoinSparkles(immediate: true)

        displayedStarCount = start
        scoreLabel.text = "\(start)"
        scoreLabel.transform = .identity
        guard end > start else { return }

        let task = Task { @MainActor in
            self.startCoinSparkles()
            for value in (start + 1)...end {
                try? await Task.sleep(nanoseconds: Self.starStepNanoseconds)
                guard !Task.isCancelled else { return }
                self.displayedStarCount = value
                self.scoreLabel.text = "\(value)"
                self.pulseScoreLabel()
            }
            try? await Task.sleep(nanoseconds: Self.sparkleLingerNanoseconds)
            guard !Task.isCancelled else { return }
            self.stopCoinSparkles(immediate: false)
        }
        starAwardTask = task
        await task.value
        if starAwardTask == task {
            starAwardTask = nil
        }
    }

    private func setup(healthCount: Int, energyCount: Int, starsCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
        for _ in 0..<max(energyCount, 0) {
            addIcon(image: boltImage, to: boltsStack, animated: false)
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

    private func addIcon(image: UIImage?, to stack: UIStackView, animated: Bool) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        let size = CGFloat(config.iconSize)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])

        imageView.alpha = animated ? 0 : 1
        // Avoid UIStackView's implicit layout animation fighting SpriteKit's frame.
        UIView.performWithoutAnimation {
            stack.addArrangedSubview(imageView)
            stack.layoutIfNeeded()
        }

        guard animated else { return }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            imageView.alpha = 1
        }
    }

    private func removeIcon(from stack: UIStackView, animated: Bool) {
        guard let icon = stack.arrangedSubviews.last else { return }
        let remove = {
            UIView.performWithoutAnimation {
                stack.removeArrangedSubview(icon)
                icon.removeFromSuperview()
                stack.layoutIfNeeded()
            }
        }
        guard animated else {
            remove()
            return
        }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: { icon.alpha = 0 },
            completion: { _ in remove() }
        )
    }

    private func clearIcons(in stack: UIStackView) {
        UIView.performWithoutAnimation {
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            stack.layoutIfNeeded()
        }
    }

    private static func makeIconStack(spacing: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(spacing)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        return stack
    }

    private func makeScoreRow(starsCount: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(config.scoreTextGap)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        stack.clipsToBounds = false

        let size = CGFloat(config.iconSize)
        coinHost.translatesAutoresizingMaskIntoConstraints = false
        coinHost.isUserInteractionEnabled = false
        coinHost.clipsToBounds = false
        if coinImageView.superview !== coinHost {
            coinHost.addSubview(coinImageView)
            NSLayoutConstraint.activate([
                coinHost.widthAnchor.constraint(equalToConstant: size),
                coinHost.heightAnchor.constraint(equalToConstant: size),
                coinImageView.centerXAnchor.constraint(equalTo: coinHost.centerXAnchor),
                coinImageView.centerYAnchor.constraint(equalTo: coinHost.centerYAnchor),
            ])
        }

        scoreLabel.text = "\(max(starsCount, 0))"
        scoreLabel.textColor = .white
        scoreLabel.font = AppFont.uiKit(size: 22, weight: .semibold)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.isUserInteractionEnabled = false
        scoreLabel.applyAppCopyShadow()

        stack.addArrangedSubview(coinHost)
        stack.addArrangedSubview(scoreLabel)
        return stack
    }

    private func pulseScoreLabel() {
        scoreLabel.layer.removeAnimation(forKey: "scorePulse")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.18
        pulse.toValue = 1
        pulse.duration = 0.22
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scoreLabel.layer.add(pulse, forKey: "scorePulse")
    }

    private func startCoinSparkles() {
        stopCoinSparkles(immediate: true)
        coinHost.layoutIfNeeded()

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        let side = max(coinHost.bounds.width, CGFloat(config.iconSize))
        emitter.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
        emitter.emitterPosition = CGPoint(x: coinHost.bounds.midX, y: coinHost.bounds.midY)
        emitter.zPosition = 1

        let cell = CAEmitterCell()
        cell.contents = Self.sparkleParticleImage().cgImage
        cell.birthRate = 36
        cell.lifetime = 0.7
        cell.lifetimeRange = 0.25
        cell.velocity = side * 0.55
        cell.velocityRange = side * 0.25
        cell.emissionRange = .pi * 2
        cell.scale = 0.22
        cell.scaleRange = 0.12
        cell.scaleSpeed = -0.2
        cell.alphaSpeed = -1.2
        cell.color = UIColor(red: 1, green: 0.84, blue: 0.35, alpha: 0.95).cgColor
        cell.alphaRange = 0.25
        cell.spin = 2
        cell.spinRange = 4

        emitter.emitterCells = [cell]
        coinHost.layer.addSublayer(emitter)
        sparkleLayer = emitter
    }

    private func stopCoinSparkles(immediate: Bool) {
        sparkleStopWorkItem?.cancel()
        sparkleStopWorkItem = nil
        guard let emitter = sparkleLayer else { return }
        emitter.birthRate = 0
        if immediate {
            emitter.removeFromSuperlayer()
            sparkleLayer = nil
            return
        }
        let work = DispatchWorkItem { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            if self?.sparkleLayer === emitter {
                self?.sparkleLayer = nil
            }
        }
        sparkleStopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func sparkleParticleImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else {
                return
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
    }

    private static let fleeButtonSize: CGFloat = 52

    private static func makeFleeButton() -> UIButton {
        let symbol = UIImage.SymbolConfiguration(
            pointSize: fleeButtonSize * 0.42,
            weight: .semibold
        )
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "figure.run", withConfiguration: symbol)
        configuration.baseForegroundColor = AppChrome.uiButtonForegroundColor
        configuration.baseBackgroundColor = AppChrome.uiButtonBackgroundColor
        configuration.background.strokeColor = AppChrome.uiButtonOutlineColor
        configuration.background.strokeWidth = AppChrome.buttonOutlineWidth
        configuration.background.cornerRadius = fleeButtonSize / 2
        configuration.cornerStyle = .fixed
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Flee the planet!"
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: fleeButtonSize),
            button.heightAnchor.constraint(equalToConstant: fleeButtonSize),
        ])
        return button
    }

    @objc private func fleeTapped() {
        onFleeTapped?()
    }
}
