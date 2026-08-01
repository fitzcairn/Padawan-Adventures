import UIKit

extension GameHUDView {
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

    func pulseScoreLabel() {
        scoreLabel.layer.removeAnimation(forKey: "scorePulse")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.18
        pulse.toValue = 1
        pulse.duration = 0.22
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scoreLabel.layer.add(pulse, forKey: "scorePulse")
    }

    func startCoinSparkles() {
        stopCoinSparkles(immediate: true)
        coinHost.layoutIfNeeded()

        let side = max(coinHost.bounds.width, CGFloat(config.iconSize))
        let emitter = GoldSparkleEmitter.makeLayer(
            side: side,
            position: CGPoint(x: coinHost.bounds.midX, y: coinHost.bounds.midY)
        )
        coinHost.layer.addSublayer(emitter)
        sparkleLayer = emitter
    }

    func stopCoinSparkles(immediate: Bool) {
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
}
