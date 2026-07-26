import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct BackgroundCoverTests {
    @Test func landscapeImageCoversPortraitViewport() {
        let image = CGSize(width: 200, height: 100)
        let viewport = CGSize(width: 100, height: 200)
        let size = BackgroundCover.displaySize(image: image, viewport: viewport)

        #expect(size.height == viewport.height)
        #expect(size.width >= viewport.width)
        #expect(abs((size.width / size.height) - (image.width / image.height)) < 0.000_1)
    }

    @Test func portraitImageCoversLandscapeViewport() {
        let image = CGSize(width: 100, height: 200)
        let viewport = CGSize(width: 200, height: 100)
        let size = BackgroundCover.displaySize(image: image, viewport: viewport)

        #expect(size.width == viewport.width)
        #expect(size.height >= viewport.height)
        #expect(abs((size.width / size.height) - (image.width / image.height)) < 0.000_1)
    }

    @Test func matchingAspectFillsExactly() {
        let image = CGSize(width: 16, height: 9)
        let viewport = CGSize(width: 160, height: 90)
        let size = BackgroundCover.displaySize(image: image, viewport: viewport)

        #expect(size.width == viewport.width)
        #expect(size.height == viewport.height)
    }
}
