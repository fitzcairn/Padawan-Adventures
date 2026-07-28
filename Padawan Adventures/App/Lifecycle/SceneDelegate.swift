//
//  SceneDelegate.swift
//  Padawan Adventures
//
//  Created by Steve Martin on 7/21/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        // Match app chrome so the system launch surface never flashes white.
        window.backgroundColor = .black
        window.rootViewController = LandscapeSwiftUIHost(rootView: FlowRootView())
        window.makeKeyAndVisible()
        self.window = window

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: AppOrientation.mask))
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        BackgroundMusicController.shared.resumeFromBackground()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        BackgroundMusicController.shared.pauseForBackground()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        BackgroundMusicController.shared.resumeFromBackground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        BackgroundMusicController.shared.pauseForBackground()
    }
}
