import SwiftUI

/// Shared status line + optional progress bar for bootstrap screens.
struct LoadingScreenScaffold<Extra: View>: View {
    let statusText: String
    let statusAccessibilityID: String
    var progress: Double?
    var progressAccessibilityID: String?
    @ViewBuilder var extra: () -> Extra

    init(
        statusText: String,
        statusAccessibilityID: String,
        progress: Double? = nil,
        progressAccessibilityID: String? = nil,
        @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }
    ) {
        self.statusText = statusText
        self.statusAccessibilityID = statusAccessibilityID
        self.progress = progress
        self.progressAccessibilityID = progressAccessibilityID
        self.extra = extra
    }

    var body: some View {
        VStack(spacing: 28) {
            extra()
            AppTitleText(text: statusText, size: statusFontSize, weight: .semibold)
                .accessibilityIdentifier(statusAccessibilityID)

            if let progress, let progressAccessibilityID {
                AppProgressBar(progress: progress, accessibilityID: progressAccessibilityID)
                    .frame(maxWidth: 280)
                    .appReadableWidth()
            }
        }
    }

    private var statusFontSize: CGFloat {
        statusAccessibilityID.hasPrefix("loading.") ? 32 : 28
    }
}
