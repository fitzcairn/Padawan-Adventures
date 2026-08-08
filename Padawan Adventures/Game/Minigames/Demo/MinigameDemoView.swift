import Combine
import SpriteKit
import SwiftUI

@MainActor
final class MinigameDemoController<Scene>: ObservableObject
where Scene: MinigameScene & MinigameDemoStage {
    @Published private(set) var scene: Scene?

    private let timing: MinigameDemoRunner.Timing
    /// Delay before the demo starts, so the instructions voice-over is not
    /// talked over by game audio.
    private let leadInSeconds: TimeInterval
    private var runnerTask: Task<Void, Never>?
    private var coinLayer: MinigameDemoCoinLayer?
    private var host: MinigameSceneHost<Scene>?

    init(
        prepare: (() async -> Void)? = nil,
        make: @escaping (CGSize) -> Scene,
        timing: MinigameDemoRunner.Timing = .init(),
        leadInSeconds: TimeInterval
    ) {
        self.timing = timing
        self.leadInSeconds = leadInSeconds
        host = MinigameSceneHost<Scene>(
            prepare: prepare,
            make: make,
            onReady: { [weak self] created in
                // Deliberately no delegate: the demo must never award stars or
                // trigger MinigameResultOverlay.
                self?.scene = created
                self?.start(on: created)
            }
        )
    }

    func ensureScene(size: CGSize) { host?.ensureScene(size: size) }
    func updateSceneSizeIfNeeded(_ size: CGSize) { host?.updateSceneSizeIfNeeded(size) }

    private func start(on scene: Scene) {
        let cursor = MinigameDemoCursor.make(
            diameter: min(scene.size.width, scene.size.height) * 0.07
        )
        cursor.position = CGPoint(x: scene.size.width * 0.5, y: scene.size.height * 0.2)
        scene.addChild(cursor)

        let coins = MinigameDemoCoinLayer(scene: scene)
        coinLayer = coins
        let pointer = MinigameDemoPointer(scene: scene, cursor: cursor)
        let runner = MinigameDemoRunner(
            stage: scene, pointer: pointer, coins: coins, timing: timing
        )
        runnerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(leadInSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await runner.run()
        }
    }

    /// Must run before the real minigame is built, or demo audio and SKActions
    /// bleed into it.
    func stop() {
        runnerTask?.cancel()
        runnerTask = nil
        coinLayer?.teardown()
        coinLayer = nil
        scene?.removeAllActions()
        scene?.isPaused = true
        scene = nil
        host = nil
        SoundEffectsController.shared.fadeOutAndStopAll()
    }
}

struct MinigameDemoView<Scene>: View where Scene: MinigameScene & MinigameDemoStage {
    @StateObject private var controller: MinigameDemoController<Scene>

    init(
        prepare: (() async -> Void)? = nil,
        make: @escaping (CGSize) -> Scene,
        timing: MinigameDemoRunner.Timing = .init(),
        leadInSeconds: TimeInterval
    ) {
        _controller = StateObject(
            wrappedValue: MinigameDemoController(
                prepare: prepare,
                make: make,
                timing: timing,
                leadInSeconds: leadInSeconds
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OverlayChrome.backgroundColor
                if let scene = controller.scene {
                    SpriteKitSceneView(scene: scene)
                }
            }
            .onAppear { controller.ensureScene(size: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                controller.updateSceneSizeIfNeeded(newSize)
            }
        }
        .ignoresSafeArea()
        .onDisappear { controller.stop() }
    }
}
