import SwiftUI

extension View {
    /// Applies background music from `Resources/Screens/<name>.yaml` when the view appears.
    func playScreenMusic(_ screenName: String) -> some View {
        onAppear {
            BackgroundMusicController.shared.applyScreen(named: screenName)
        }
    }
}
