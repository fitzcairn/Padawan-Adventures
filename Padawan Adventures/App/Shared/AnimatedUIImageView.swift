import SwiftUI
import UIKit

/// Loops upright UIKit frames in SwiftUI using atlas frame durations.
struct AnimatedUIImageView: View {
    let frames: [(image: UIImage, duration: TimeInterval)]

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.clear
            } else if frames.count == 1 {
                Image(uiImage: frames[0].image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                TimelineView(.animation) { context in
                    Image(uiImage: frame(at: context.date).image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
        }
    }

    private func frame(at date: Date) -> (image: UIImage, duration: TimeInterval) {
        let total = frames.reduce(0.0) { $0 + max($1.duration, 0.000_001) }
        guard total > 0 else { return frames[0] }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }
        for frame in frames {
            let d = max(frame.duration, 0.000_001)
            if t < d { return frame }
            t -= d
        }
        return frames[frames.count - 1]
    }
}
