import SwiftUI

struct SettingsView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var preferences: AudioPreferences

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        _preferences = State(initialValue: session.audioPreferences)
    }

    var body: some View {
        @Bindable var preferences = preferences

        AppScreen {
            VStack(spacing: 24) {
                AppTitleText(
                    text: Strings.text("settings_title"),
                    size: 28,
                    weight: .semibold,
                    speakID: "settings_title"
                )
                    .accessibilityIdentifier("settings.title")

                Spacer()

                VStack(spacing: 28) {
                    // No mute toggle: letter/word cues are gameplay-critical, so SFX
                    // stay enabled and only volume is adjustable.
                    volumeRow(
                        label: Strings.text("settings_sound_effects"),
                        labelID: "settings.soundEffects.label",
                        sliderValue: Binding(
                            get: { Double(preferences.soundEffectsVolume) },
                            set: { preferences.soundEffectsVolume = Float($0) }
                        ),
                        sliderID: "settings.soundEffects.volume"
                    )

                    settingsRow(
                        checkboxLabel: Strings.text("settings_music"),
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

                Spacer()

                AppLargeButton(
                    title: Strings.text("button_back"),
                    accessibilityID: "settings.back"
                ) {
                    router.popOrShowMenu()
                }
                .frame(maxWidth: 280)
            }
        }
        .playScreenMusic("settings")
        .onDisappear {
            Task {
                await session.persistCurrentSettings()
            }
        }
    }

    @ViewBuilder
    private func volumeRow(
        label: String,
        labelID: String,
        sliderValue: Binding<Double>,
        sliderID: String
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(AppFont.swiftUI(size: 18, weight: .medium))
                .foregroundStyle(AppChrome.primaryTextColor)
                .appCopyShadow()
                .frame(maxWidth: 180, alignment: .leading)
                .accessibilityIdentifier(labelID)

            AppSlider(
                value: sliderValue,
                accessibilityID: sliderID
            )
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
