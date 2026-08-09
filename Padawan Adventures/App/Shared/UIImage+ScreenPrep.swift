import UIKit

extension UIImage {
    /// Decodes the bitmap so the first SwiftUI/UIKit paint does not hitch or flash empty.
    ///
    /// `nonisolated` so background loaders (e.g. `BackgroundLibrary`) can decode off the
    /// main actor. `preparingForDisplay()` is documented as safe to call from any thread.
    nonisolated func preparedForScreen() -> UIImage {
        preparingForDisplay() ?? self
    }
}
