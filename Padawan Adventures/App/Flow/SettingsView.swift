import SwiftUI

struct SettingsView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var preferences = AudioPreferences.shared

    var body: some View {
        @Bindable var preferences = preferences

        VStack(spacing: 24) {
            AppTitleText(text: "Settings", size: 28, weight: .semibold)
                .padding(.top, 24)
                .accessibilityIdentifier("settings.title")

            Spacer()

            VStack(spacing: 28) {
                settingsRow(
                    checkboxLabel: "Sound Effects",
                    checkboxID: "settings.soundEffects.enabled",
                    isOn: $preferences.soundEffectsEnabled,
                    sliderValue: Binding(
                        get: { Double(preferences.soundEffectsVolume) },
                        set: { preferences.soundEffectsVolume = Float($0) }
                    ),
                    sliderID: "settings.soundEffects.volume"
                )

                settingsRow(
                    checkboxLabel: "Music",
                    checkboxID: "settings.music.enabled",
                    isOn: $preferences.musicEnabled,
                    sliderValue: Binding(
                        get: { Double(preferences.musicVolume) },
                        set: { preferences.musicVolume = Float($0) }
                    ),
                    sliderID: "settings.music.volume"
                )
            }
            .appReadableWidth()
            .padding(.horizontal)

            Spacer()

            AppLargeButton(title: "Back", accessibilityID: "settings.back") {
                if router.path.isEmpty {
                    router.showMenu()
                } else {
                    router.pop()
                }
            }
            .frame(maxWidth: 280)
            .padding(.bottom, 24)
        }
        .appScreenBackground()
        .playScreenMusic("settings")
        .onDisappear {
            Task {
                await session.persistCurrentSettings()
            }
        }
    }

    @ViewBuilder
    private func settingsRow(
        checkboxLabel: String,
        checkboxID: String,
        isOn: Binding<Bool>,
        sliderValue: Binding<Double>,
        sliderID: String
    ) -> some View {
        HStack(spacing: 16) {
            AppCheckbox(
                isOn: isOn,
                label: checkboxLabel,
                accessibilityID: checkboxID
            )
            .frame(maxWidth: 180, alignment: .leading)

            AppSlider(
                value: sliderValue,
                isEnabled: isOn.wrappedValue,
                accessibilityID: sliderID
            )
        }
    }
}
