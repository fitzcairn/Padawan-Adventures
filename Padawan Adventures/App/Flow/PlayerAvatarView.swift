import SwiftUI
import UIKit

/// Circular player thumbnail matching the player-select row.
struct PlayerAvatarView: View {
    enum Style {
        case plain
        case console
    }

    static let defaultSide: CGFloat = 48

    var image: UIImage?
    var accessibilityID: String
    var side: CGFloat = defaultSide
    var style: Style = .plain

    var body: some View {
        Group {
            switch style {
            case .plain:
                avatarFill
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            case .console:
                StarWarsConsoleFrame(shape: .circle, showsScanlines: false) {
                    avatarFill
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(width: consolePlateSize.width, height: consolePlateSize.height)
            }
        }
        .accessibilityIdentifier(accessibilityID)
    }

    private var consolePlateSize: CGSize {
        StarWarsConsoleChrome.plateSize(forContent: CGSize(width: side, height: side))
    }

    @ViewBuilder
    private var avatarFill: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppChrome.secondaryTextColor)
                .padding(side * 4 / Self.defaultSide)
        }
    }
}
