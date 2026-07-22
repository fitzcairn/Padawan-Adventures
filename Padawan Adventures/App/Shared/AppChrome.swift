import SwiftUI

enum AppChrome {
    static let backgroundColor = Color.black
    static let primaryTextColor = Color.white
    static let secondaryTextColor = Color(white: 0.65)
    static let buttonBackgroundColor = Color(white: 0.92)
    static let buttonForegroundColor = Color.black
    static let maxContentWidth: CGFloat = 420

    static var versionBuildString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }
}

extension View {
    func appScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppChrome.backgroundColor.ignoresSafeArea())
    }

    func appReadableWidth() -> some View {
        frame(maxWidth: AppChrome.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}

struct AppTitleText: View {
    let text: String
    var size: CGFloat = 28
    var weight: Font.Weight = .semibold
    var color: Color = AppChrome.primaryTextColor

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

struct AppLargeButton: View {
    let title: String
    var accessibilityID: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(AppChrome.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityIdentifier(accessibilityID ?? title)
    }
}
