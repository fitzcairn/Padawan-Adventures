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
        guard let windowScene = scene as? UIWindowScene else {
            GameLogger.fault(.lifecycle, "scene is not a UIWindowScene; no window created")
            return
        }
        GameLogger.mark(.lifecycle, "scene willConnect")

        let window = UIWindow(windowScene: windowScene)
        // Match app chrome so the system launch surface never flashes white.
        window.backgroundColor = .black
        window.rootViewController = LandscapeSwiftUIHost(rootView: FlowRootView())
        window.makeKeyAndVisible()
        self.window = window

        enforceLandscape(on: windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene {
            enforceLandscape(on: windowScene)
        }
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

    /// Re-asserts the landscape mask. `UIRequiresFullScreen` keeps iPad out of portrait, and
    /// this covers the window geometry the scene comes back with after a rotation elsewhere.
    private func enforceLandscape(on windowScene: UIWindowScene) {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: AppOrientation.mask))
        window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
