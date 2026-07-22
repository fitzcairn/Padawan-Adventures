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

    @Test func reentrancyIgnoresSecondPresentWhileBusy() {
        var fadeCompletions: [() -> Void] = []
        var presentedCount = 0
        var dismissedCount = 0

        let presenter = FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: { completion in fadeCompletions.append(completion) },
            present: { _ in presentedCount += 1 },
            dismiss: { _, completion in
                dismissedCount += 1
                completion()
            }
        ))

        var resolveCount = 0
        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { done in
                resolveCount += 1
                done()
            }
        )
        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { done in
                resolveCount += 1
                done()
            }
        )

        #expect(fadeCompletions.count == 1)
        #expect(presentedCount == 0)
        #expect(presenter.isBusy)

        fadeCompletions[0]()
        #expect(presentedCount == 1)
        #expect(fadeCompletions.count == 1)
        #expect(resolveCount == 0)
        #expect(dismissedCount == 0)
    }

    @Test func fadeThenPresentWaitsForFadeCompletion() {
        var fadeCompletion: (() -> Void)?
        var presented = false

        let presenter = FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: { completion in fadeCompletion = completion },
            present: { _ in presented = true },
            dismiss: { _, completion in completion() }
        ))

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { done in done() }
        )

        #expect(fadeCompletion != nil)
        #expect(!presented)

        fadeCompletion?()
        #expect(presented)
    }

    @Test func skipFadePresentsImmediately() {
        var fadeCalled = false
        var presented = false

        let presenter = FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: { _ in fadeCalled = true },
            present: { _ in presented = true },
            dismiss: { _, completion in completion() }
        ))

        presenter.present(
            fadeWorldOut: false,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    YouWinView(onFinished: finish)
                }
            },
            onResolved: { done in done() }
        )

        #expect(!fadeCalled)
        #expect(presented)
        #expect(presenter.isBusy)
    }

    @Test func finishOrderingDismissesThenResolvesThenUnlocks() {
        enum Step: Equatable {
            case present
            case dismiss
            case resolve
            case unlocked
        }

        var steps: [Step] = []
        var presentedVC: FullscreenOverlayHost?

        let presenter = FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: { completion in completion() },
            present: { viewController in
                steps.append(.present)
                presentedVC = viewController as? FullscreenOverlayHost
            },
            dismiss: { _, completion in
                steps.append(.dismiss)
                completion()
            }
        ))

        presenter.present(
            fadeWorldOut: true,
            makeViewController: { makeHost() },
            onResolved: { done in
                steps.append(.resolve)
                done()
                steps.append(.unlocked)
            }
        )

        #expect(steps == [.present])
        #expect(presenter.isBusy)

        presentedVC?.finish()

        #expect(steps == [.present, .dismiss, .resolve, .unlocked])
        #expect(!presenter.isBusy)
    }

    @Test func completionRunsExactlyOnce() {
        var presentedVC: FullscreenOverlayHost?
        var resolveCount = 0

        let presenter = FullscreenOverlayPresenter(dependencies: .init(
            fadeWorldOut: { completion in completion() },
            present: { viewController in
                presentedVC = viewController as? FullscreenOverlayHost
            },
            dismiss: { _, completion in completion() }
        ))

        presenter.present(
            fadeWorldOut: false,
            makeViewController: { makeHost() },
            onResolved: { done in
                resolveCount += 1
                done()
            }
        )

        presentedVC?.finish()
        #expect(resolveCount == 1)
        #expect(!presenter.isBusy)

        // A second finish after unlock should not re-trigger the old resolve closure.
        presentedVC?.finish()
        #expect(resolveCount == 1)
    }
}
