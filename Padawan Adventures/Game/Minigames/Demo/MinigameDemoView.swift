import Combine
import SpriteKit
import SwiftUI

@MainActor
final class MinigameDemoController<Scene>: ObservableObject
where Scene: MinigameScene & MinigameDemoStage {
    @Published private(set) var scene: Scene?
    /// Bumped every cycle so `SpriteKitSceneView` is recreated and `didMove` is guaranteed.
    @Published private(set) var sceneEpoch: Int = 0

    private let prepare: (() async -> Void)?
    private let make: (CGSize) -> Scene
    private let timing: MinigameDemoRunner.Timing
    /// Delay after the pointer is shown before gestures start, so the tutorial
    /// voice-over has time to begin. Applied once per tutorial presentation.
    private let leadInSeconds: TimeInterval
    private let restartDelaySeconds: TimeInterval = 0.6
    private let buildTimeoutSeconds: TimeInterval = 5

    private var loopTask: Task<Void, Never>?
    private var coinLayer: MinigameDemoCoinLayer?
    /// Latest sanitized layout size; the next cycle's scene is built at this size.
    private var size = MinigameSceneHost<Scene>.minimumSize
    /// Set only by `stop()` when the tutorial is dismissed. Cleared if the view
    /// re-appears so a spurious `onDisappear` cannot permanently kill the demo.
    private var didStop = false
    /// Voice-over lead-in runs only at the start of the tutorial, never on demo loops.
    private var didApplyLeadIn = false

    init(
        prepare: (() async -> Void)? = nil,
        make: @escaping (CGSize) -> Scene,
        timing: MinigameDemoRunner.Timing = .init(),
        leadInSeconds: TimeInterval
    ) {
        self.prepare = prepare
        self.make = make
        self.timing = timing
        self.leadInSeconds = leadInSeconds
    }

    func ensureScene(size: CGSize) {
        self.size = MinigameSceneHost<Scene>.sanitized(size)
        // SwiftUI overlay transitions can fire onDisappear/onAppear briefly. `stop()`
        // cancels the loop; allow a fresh start when the view is shown again.
        if didStop {
            didStop = false
            didApplyLeadIn = false
            loopTask?.cancel()
            loopTask = nil
        }
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            await self?.runLoop()
            // Clear so a later `ensureScene` can start a new loop after a clean exit.
            self?.loopTask = nil
        }
    }

    /// Only records the size. Resizing a live scene runs `rebuildLayout`, and five of the
    /// seven demo scenes call `removeAllChildren()` there, which would delete the cursor
    /// and the coins mid-demo. The next cycle picks the new size up instead.
    func updateSceneSizeIfNeeded(_ size: CGSize) {
        self.size = MinigameSceneHost<Scene>.sanitized(size)
    }

    private func runLoop() async {
        await prepare?()
        while !Task.isCancelled, !didStop {
            let awarded = await runCycle()
            if Task.isCancelled || didStop { return }
            // A stage that never becomes ready would otherwise spin forever.
            guard awarded > 0 else { return }
            try? await Task.sleep(
                nanoseconds: UInt64(restartDelaySeconds * 1_000_000_000)
            )
        }
    }

    /// Builds a fresh scene, drives one full demo, tears the cycle's nodes down, and
    /// returns the coins awarded.
    private func runCycle() async -> Int {
        // Deliberately no delegate: the demo must never award stars or trigger
        // MinigameResultOverlay.
        let applyLeadIn = !didApplyLeadIn && leadInSeconds > 0
        // Suppress before `buildContent` so combat_start / loops / word prompts never
        // begin under the tutorial voice-over. `sfx_ui_*` VO still plays.
        if applyLeadIn {
            SoundEffectsController.shared.setGameplaySFXSuppressed(true)
        }
        let scene = make(size)
        if applyLeadIn {
            // Freeze before present so SKAction timers cannot advance during lead-in.
            scene.isPaused = true
        }
        self.scene = scene
        self.sceneEpoch += 1

        // Yield so SwiftUI can mount / swap `SpriteKitSceneView` before we poll.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Most demo scenes call `removeAllChildren()` while building, so the cursor and
        // the coin layer cannot be attached until `buildContent` has returned.
        guard await waitUntilBuilt(scene) else {
            if applyLeadIn {
                SoundEffectsController.shared.setGameplaySFXSuppressed(false)
            }
            return 0
        }

        let cursor = MinigameDemoCursorNode(
            side: min(scene.size.width, scene.size.height) * 0.24
        )
        cursor.position = CGPoint(x: scene.size.width * 0.5, y: scene.size.height * 0.2)
        scene.addChild(cursor)

        let coins = MinigameDemoCoinLayer(scene: scene)
        coinLayer = coins
        let runner = MinigameDemoRunner(
            stage: scene,
            pointer: MinigameDemoPointer(scene: scene, cursor: cursor),
            coins: coins,
            timing: timing
        )

        if applyLeadIn {
            didApplyLeadIn = true
            // Pointer is already visible. Arena stays frozen while the voice-over
            // begins. Looped cycles skip this — VO only plays once on appear.
            try? await Task.sleep(nanoseconds: UInt64(leadInSeconds * 1_000_000_000))
            SoundEffectsController.shared.setGameplaySFXSuppressed(false)
            guard !Task.isCancelled, !didStop else { return 0 }
            scene.demoResumeGameplayAudio()
            scene.isPaused = false
        }
        guard !Task.isCancelled, !didStop else { return 0 }

        let awarded = await runner.run()

        coins.teardown()
        coinLayer = nil
        cursor.removeFromParent()
        scene.removeAllActions()
        scene.isPaused = true
        return awarded
    }

    /// Polls until the scene is in an `SKView` and `buildContent` has finished.
    private func waitUntilBuilt(_ scene: Scene) async -> Bool {
        let deadline = Date().addingTimeInterval(buildTimeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled || didStop { return false }
            if scene.view != nil, scene.didSetup { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Must run before the real minigame is built, or demo audio and SKActions
    /// bleed into it.
    func stop() {
        didStop = true
        loopTask?.cancel()
        loopTask = nil
        coinLayer?.teardown()
        coinLayer = nil
        scene?.removeAllActions()
        scene?.isPaused = true
        scene = nil
        SoundEffectsController.shared.setGameplaySFXSuppressed(false)
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
                    // `id` forces a fresh SKView per cycle so `didMove` / `didSetup` always
                    // fire — `updateUIView` alone is not enough when SwiftUI coalesces updates.
                    SpriteKitSceneView(scene: scene)
                        .id(controller.sceneEpoch)
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
