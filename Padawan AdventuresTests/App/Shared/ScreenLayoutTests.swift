import SwiftUI
import Testing
import UIKit
@testable import Padawan_Adventures

struct ScreenLayoutTests {
    @Test func usesPercentWhenLargerThanSafeArea() {
        let size = CGSize(width: 1000, height: 800)
        let safe = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        let insets = ScreenLayout.insets(size: size, safeArea: safe)

        #expect(insets.top == 20)
        #expect(insets.bottom == 20)
        #expect(insets.leading == 25)
        #expect(insets.trailing == 25)
    }

    @Test func usesSafeAreaWhenLargerThanPercent() {
        let size = CGSize(width: 400, height: 300)
        let safe = EdgeInsets(top: 44, leading: 47, bottom: 21, trailing: 47)

        let insets = ScreenLayout.insets(size: size, safeArea: safe)

        #expect(insets.top == 44)
        #expect(insets.bottom == 21)
        #expect(insets.leading == 47)
        #expect(insets.trailing == 47)
    }

    @Test func uiInsetsMatchesSwiftUIInsets() {
        let size = CGSize(width: 1024, height: 768)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        let ui = ScreenLayout.uiInsets(size: size, safeArea: safe)
        let swift = ScreenLayout.insets(
            size: size,
            safeArea: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)
        )

        #expect(ui.top == swift.top)
        #expect(ui.left == swift.leading)
        #expect(ui.bottom == swift.bottom)
        #expect(ui.right == swift.trailing)
        #expect(ui.top == size.height * ScreenLayout.edgeInsetFraction)
        #expect(ui.left == size.width * ScreenLayout.edgeInsetFraction)
        #expect(ui.bottom == 20)
        #expect(ui.right == size.width * ScreenLayout.edgeInsetFraction)
    }

    @Test func edgeInsetFractionIsTwoPointFivePercent() {
        #expect(ScreenLayout.edgeInsetFraction == 0.025)
    }

    @Test @MainActor func prefersNonZeroProxySafeAreaOverWindowFallback() {
        let proxy = EdgeInsets(top: 0, leading: 59, bottom: 0, trailing: 21)
        let resolved = ScreenLayout.safeArea(fromProxy: proxy)
        #expect(resolved.leading == 59)
        #expect(resolved.trailing == 21)
    }
}
