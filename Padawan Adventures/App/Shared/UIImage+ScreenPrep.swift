import UIKit

extension UIImage {
    /// Decodes the bitmap so the first SwiftUI/UIKit paint does not hitch or flash empty.
    func preparedForScreen() -> UIImage {
        preparingForDisplay() ?? self
    }
}
