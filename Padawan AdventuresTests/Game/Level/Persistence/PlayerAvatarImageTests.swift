import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Padawan_Adventures

struct PlayerAvatarImageTests {
    @Test func circleDiameterUsesEightyPercentArea() {
        let size = CGSize(width: 100, height: 100)
        let diameter = PlayerAvatarImage.circleDiameter(forPreviewSize: size)
        let expected = 2 * sqrt(0.8 * 10_000 / .pi)
        #expect(abs(diameter - expected) < 0.0001)
    }

    @Test func makeThumbnailJPEGProduces200x200() {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format)
            .image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            }

        let data = PlayerAvatarImage.makeThumbnailJPEG(from: source)
        #expect(data != nil)

        let image = PlayerAvatarImage.uiImage(from: data!)
        #expect(image != nil)
        #expect(Int(image!.size.width.rounded()) == 200)
        #expect(Int(image!.size.height.rounded()) == 200)
    }

    @Test func proceduralSillyFaceReturnsNonEmptyJPEG() {
        let data = SillyFaceAvatarGenerator.proceduralJPEG(seedName: "TestPadawan")
        #expect(!data.isEmpty)
        #expect(PlayerAvatarImage.uiImage(from: data) != nil)
    }
}
