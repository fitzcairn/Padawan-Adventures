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
        let navigation = LandscapeNavigationController(rootViewController: LoadingViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.view.backgroundColor = .black
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: AppOrientation.mask))
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {}

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {}
}
