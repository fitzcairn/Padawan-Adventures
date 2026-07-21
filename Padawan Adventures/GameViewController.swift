//
//  GameViewController.swift
//  Padawan Adventures
//

import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    private let world: GameWorld
    private let isoConfig: IsometricConfig
    private let saveService: GameSaveService?

    init(world: GameWorld, isoConfig: IsometricConfig, saveService: GameSaveService?) {
        self.world = world
        self.isoConfig = isoConfig
        self.saveService = saveService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = self.view as? SKView else { return }

        let scene = GameScene(
            size: CGSize(width: 1024, height: 768),
            world: world,
            isoConfig: isoConfig,
            saveService: saveService
        )
        scene.scaleMode = .aspectFill
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        view.showsFPS = true
        view.showsNodeCount = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var prefersStatusBarHidden: Bool {
        true
    }
}
