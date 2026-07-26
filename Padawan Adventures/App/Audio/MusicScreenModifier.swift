import SwiftUI

extension View {
    /// Applies background music from `screens.<name>` in `Resources/Config/screens.yaml` when the view appears.
    func playScreenMusic(_ screenName: String) -> some View {
        onAppear {
            BackgroundMusicController.shared.applyScreen(named: screenName)
        }
    }
}
