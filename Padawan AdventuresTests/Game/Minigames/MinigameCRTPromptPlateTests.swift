import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct MinigameCRTPromptPlateTests {
    /// Reconstructs the content box `promptRegions` feeds into `plateSize(forPromptContent:)`.
    private func contentBox(pictureSide: CGFloat, wordContent: CGSize) -> CGSize {
        let picture = max(pictureSide, 0)
        let band = max(wordContent.height, 1)
        let gap = picture > 0 ? picture * MinigameCRTPromptPlate.pictureWordGapScale : 0
        let gutter = MinigameCRTPromptPlate.iconSide(
            pictureAreaHeight: picture > 0 ? picture : band
        )
        return CGSize(
            width: max(picture, max(wordContent.width, 1)) + gutter * 2,
            height: picture + gap + band
        )
    }

    @Test func screenMatchesContentForLandscapePlate() {
        let word = CGSize(width: 220, height: 36)
        let pictureSide: CGFloat = 48
        let regions = MinigameCRTPromptPlate.promptRegions(
            pictureSide: pictureSide,
            wordContent: word
        )
        let content = contentBox(pictureSide: pictureSide, wordContent: word)
        let screen = StarWarsConsoleChrome.screenRect(for: regions.plateSize)
        #expect(abs(screen.width - content.width) < 0.5)
        #expect(abs(screen.height - content.height) < 0.5)
        #expect(regions.plateSize.width >= regions.plateSize.height)
    }

    @Test func screenMatchesContentForPortraitPlate() {
        // A tall word band is needed so content height exceeds width after the icon gutters.
        let word = CGSize(width: 20, height: 50)
        let pictureSide: CGFloat = 80
        let regions = MinigameCRTPromptPlate.promptRegions(
            pictureSide: pictureSide,
            wordContent: word
        )
        let content = contentBox(pictureSide: pictureSide, wordContent: word)
        let screen = StarWarsConsoleChrome.screenRect(for: regions.plateSize)
        #expect(abs(screen.width - content.width) < 0.5)
        #expect(abs(screen.height - content.height) < 0.5)
        #expect(regions.plateSize.height > regions.plateSize.width)
    }

    @Test func wordBandSitsAtBottomOfScreen() {
        let word = CGSize(width: 80, height: 32)
        let pictureSide: CGFloat = 96
        let regions = MinigameCRTPromptPlate.promptRegions(
            pictureSide: pictureSide,
            wordContent: word
        )
        let screen = StarWarsConsoleChrome.screenRect(for: regions.plateSize)
        #expect(abs(regions.wordBandRect.minY - screen.minY) < 0.01)
        #expect(abs(regions.wordBandRect.height - word.height) < 0.01)
        #expect(regions.wordAnchor.x == 0)
        #expect(abs(regions.pictureRect.minY - regions.wordBandRect.maxY) < 0.01)
        #expect(abs(regions.pictureRect.maxY - screen.maxY) < 0.01)
    }

    @Test func pictureAndWordRegionsDoNotOverlap() {
        let regions = MinigameCRTPromptPlate.promptRegions(
            pictureSide: 100,
            wordContent: CGSize(width: 60, height: 30)
        )
        #expect(!regions.pictureRect.intersects(regions.wordBandRect))
    }

    @Test func wordOnlyPromptHasNoPictureRegion() {
        let word = CGSize(width: 90, height: 34)
        let regions = MinigameCRTPromptPlate.promptRegions(pictureSide: 0, wordContent: word)
        #expect(regions.pictureRect.height == 0)
        let chromeOnly = word.height / StarWarsConsoleChrome.contentScale
        #expect(regions.plateSize.height <= chromeOnly + 1)
    }

    @Test func playIconSitsInUpperRightOfPictureRegion() {
        let image = UIImage(systemName: "dog.fill") ?? UIImage()
        let prompt = MinigameCRTPromptPlate.makePrompt(
            image: image,
            pictureSide: 100,
            wordContent: CGSize(width: 70, height: 30),
            name: "testPrompt"
        )
        guard let icon = MinigamePlaySoundIcon.find(in: prompt.plate) else {
            Issue.record("expected play icon child")
            return
        }
        let iconFrame = CGRect(
            x: icon.position.x - icon.size.width * 0.5,
            y: icon.position.y - icon.size.height * 0.5,
            width: icon.size.width,
            height: icon.size.height
        )
        #expect(prompt.regions.pictureRect.contains(iconFrame))
        #expect(icon.position.x > 0)
        #expect(icon.position.y > prompt.regions.pictureRect.midY)
    }

    @Test func attachPlayIconSitsInUpperRightOfScreen() {
        let plateSize = CGSize(width: 200, height: 72)
        let plate = SKSpriteNode(color: .darkGray, size: plateSize)
        let screen = StarWarsConsoleChrome.screenRect(for: plateSize)
        MinigameCRTPromptPlate.attachPlayIcon(to: plate, areaHeight: screen.height)
        guard let icon = MinigamePlaySoundIcon.find(in: plate) else {
            Issue.record("expected play icon child")
            return
        }
        let iconFrame = CGRect(
            x: icon.position.x - icon.size.width * 0.5,
            y: icon.position.y - icon.size.height * 0.5,
            width: icon.size.width,
            height: icon.size.height
        )
        #expect(screen.contains(iconFrame))
        #expect(icon.position.x > 0)
        #expect(icon.position.y > 0)
        #expect(icon.xScale == 1)
    }

    @Test func attachPlayIconLeadingSitsInUpperLeftAndMirrors() {
        let plateSize = CGSize(width: 200, height: 72)
        let plate = SKSpriteNode(color: .darkGray, size: plateSize)
        let screen = StarWarsConsoleChrome.screenRect(for: plateSize)
        MinigameCRTPromptPlate.attachPlayIcon(
            to: plate,
            areaHeight: screen.height,
            edge: .leading
        )
        guard let icon = MinigamePlaySoundIcon.find(in: plate) else {
            Issue.record("expected play icon child")
            return
        }
        let iconFrame = CGRect(
            x: icon.position.x - icon.size.width * 0.5,
            y: icon.position.y - icon.size.height * 0.5,
            width: icon.size.width,
            height: icon.size.height
        )
        #expect(screen.contains(iconFrame))
        #expect(icon.position.x < 0)
        #expect(icon.position.y > 0)
        #expect(icon.xScale == -1)
    }

    @Test func regionHitTestResolvesPictureWordAndMiss() {
        let image = UIImage(systemName: "dog.fill") ?? UIImage()
        let prompt = MinigameCRTPromptPlate.makePrompt(
            image: image,
            pictureSide: 100,
            wordContent: CGSize(width: 70, height: 30),
            name: "testPrompt"
        )
        let scene = SKScene(size: CGSize(width: 400, height: 800))
        prompt.plate.position = CGPoint(x: 200, y: 600)
        scene.addChild(prompt.plate)

        let wordLocal = CGPoint(x: 0, y: prompt.regions.wordBandRect.midY)
        let pictureLocal = CGPoint(
            x: prompt.regions.pictureRect.maxX - 8,
            y: prompt.regions.pictureRect.maxY - 8
        )
        let wordScene = prompt.plate.convert(wordLocal, to: scene)
        let pictureScene = prompt.plate.convert(pictureLocal, to: scene)
        let miss = CGPoint(x: 10, y: 10)

        #expect(prompt.region(at: wordScene) == .word)
        #expect(prompt.region(at: pictureScene) == .picture)
        #expect(prompt.region(at: miss) == nil)
    }
}
