import SwiftUI
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct FullscreenOverlayPresenterTests {
    private func makeHost() -> FullscreenOverlayHost {
        FullscreenOverlayHost { _ in
            Color.clear
        }
    }

    private func makePresenter(
        fadeWorldOut: @escaping (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void = { _, completion in completion() },
        fadeWorldIn: @escaping (_ duration: TimeInterval, _ completion: @escaping () -> Void) -> Void = { _, completion in completion() },
        present: @escaping (UIViewController) -> Void = { _ in },
        dismiss: @escaping (UIViewController, @escaping () -> Void) -> Void = { _, completion in completion() }
    ) -> FullscreenOverlayPresenter {
        FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: fadeWorldOut,
            fadeWorldIn: fadeWorldIn,
            present: present,
            dismiss: dismiss
        ))
    }

    private func finishHost(_ host: FullscreenOverlayHost) {
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }
        host.loadViewIfNeeded()
        host.finish()
    }

    @Test func reentrancyIgnoresSecondPresentWhileBusy() {
        var fadeCompletions: [() -> Void] = []
        var presentedCount = 0

        let presenter = makePresenter(
            fadeWorldOut: { _, completion in fadeCompletions.append(completion) },
            present: { _ in presentedCount += 1 }
        )

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                returnToWorld.crossfadeToWorld { $0() }
            }
        )
        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                returnToWorld.crossfadeToWorld { $0() }
            }
        )

        #expect(fadeCompletions.count == 1)
        #expect(presentedCount == 0)
        #expect(presenter.isBusy)

        fadeCompletions[0]()
        #expect(presentedCount == 1)
    }

    @Test func fadeThenPresentWaitsForFadeCompletion() {
        var fadeCompletion: (() -> Void)?
        var fadeOutDuration: TimeInterval?
        var presented = false

        let presenter = makePresenter(
            fadeWorldOut: { duration, completion in
                fadeOutDuration = duration
                fadeCompletion = completion
            },
            present: { _ in presented = true }
        )

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                returnToWorld.crossfadeToWorld { $0() }
            }
        )

        #expect(fadeCompletion != nil)
        #expect(fadeOutDuration == WorldFade.duration)
        #expect(!presented)

        fadeCompletion?()
        #expect(presented)
    }

    @Test func skipFadePresentsImmediately() {
        var fadeCalled = false
        var presented = false

        let presenter = makePresenter(
            fadeWorldOut: { _, _ in fadeCalled = true },
            present: { _ in presented = true }
        )

        presenter.present(
            fadeWorldOut: false,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    YouWinView(onFinished: finish)
                }
            },
            onResolved: { returnToWorld in
                returnToWorld.dismissWhileCovered { $0() }
            }
        )

        #expect(!fadeCalled)
        #expect(presented)
        #expect(presenter.isBusy)
    }

    @Test func crossfadeToWorldFadesWorldInThenDismissesAndUnlocks() {
        enum Step: Equatable {
            case present
            case resolve
            case worldFadeIn
            case dismiss
            case unlocked
        }

        var steps: [Step] = []
        var presentedVC: FullscreenOverlayHost?

        var fadeInDuration: TimeInterval?
        let presenter = makePresenter(
            fadeWorldOut: { _, completion in completion() },
            fadeWorldIn: { duration, completion in
                fadeInDuration = duration
                steps.append(.worldFadeIn)
                completion()
            },
            present: { viewController in
                steps.append(.present)
                presentedVC = viewController as? FullscreenOverlayHost
            },
            dismiss: { _, completion in
                steps.append(.dismiss)
                completion()
            }
        )

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                steps.append(.resolve)
                returnToWorld.crossfadeToWorld { done in
                    done()
                    steps.append(.unlocked)
                }
            }
        )

        #expect(steps == [.present])
        #expect(presenter.isBusy)

        let host = try! #require(presentedVC)
        finishHost(host)

        #expect(steps == [.present, .resolve, .worldFadeIn, .dismiss, .unlocked])
        #expect(fadeInDuration == WorldFade.duration)
        #expect(!presenter.isBusy)
    }

    @Test func dismissWhileCoveredSkipsWorldFadeIn() {
        var worldFadeInCalled = false
        var presentedVC: FullscreenOverlayHost?
        var dismissed = false

        let presenter = makePresenter(
            fadeWorldOut: { _, completion in completion() },
            fadeWorldIn: { _, completion in
                worldFadeInCalled = true
                completion()
            },
            present: { viewController in
                presentedVC = viewController as? FullscreenOverlayHost
            },
            dismiss: { _, completion in
                dismissed = true
                completion()
            }
        )

        var unlocked = false
        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                returnToWorld.dismissWhileCovered { done in
                    done()
                    unlocked = true
                }
            }
        )

        let host = try! #require(presentedVC)
        finishHost(host)

        #expect(!worldFadeInCalled)
        #expect(dismissed)
        #expect(unlocked)
        #expect(!presenter.isBusy)
    }

    @Test func completionRunsExactlyOnce() {
        var presentedVC: FullscreenOverlayHost?
        var resolveCount = 0

        let presenter = makePresenter(
            fadeWorldOut: { _, completion in completion() },
            present: { viewController in
                presentedVC = viewController as? FullscreenOverlayHost
            }
        )

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { returnToWorld in
                resolveCount += 1
                returnToWorld.dismissWhileCovered { $0() }
            }
        )

        let host = try! #require(presentedVC)
        finishHost(host)
        #expect(resolveCount == 1)
        #expect(!presenter.isBusy)

        host.finish()
        #expect(resolveCount == 1)
    }
}
