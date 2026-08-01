import CoreGraphics
import Foundation

nonisolated struct IsometricConfig: Equatable, Sendable {
    /// Locked on-screen tile footprint (floor diamond width × height).
    var tileWidth: CGFloat = 40
    var tileHeight: CGFloat = 40
    var wallHeight: CGFloat = 40
    var storyHeight: CGFloat = 40
    /// Max stories used to interleave story into depth without burying lower stories
    /// under an entire upper-story layer.
    var maxStories: Int = 1
}
