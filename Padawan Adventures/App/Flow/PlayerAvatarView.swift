import SwiftUI
import UIKit

/// Circular player thumbnail matching the player-select row.
struct PlayerAvatarView: View {
    var image: UIImage?
    var accessibilityID: String

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppChrome.secondaryTextColor)
                    .padding(4)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityIdentifier(accessibilityID)
    }
}
