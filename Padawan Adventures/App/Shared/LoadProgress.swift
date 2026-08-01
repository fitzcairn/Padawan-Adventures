import SwiftUI
import UIKit


enum LoadProgress {
    /// Maps a local 0...1 fraction into an overall progress window.
    static func map(_ local: Double, from start: Double, to end: Double) -> Double {
        let clamped = min(1, max(0, local))
        return start + clamped * (end - start)
    }
}
