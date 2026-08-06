import SwiftUI
import UIKit


extension View {
    func appScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppChrome.backgroundColor.ignoresSafeArea())
    }

    func appReadableWidth() -> some View {
        frame(maxWidth: AppChrome.maxContentWidth)
            .frame(maxWidth: .infinity)
    }

    /// #245a85 fill with #0987e8 outline (no drop shadow).
    func appButtonChrome<S: Shape>(
        _ shape: S,
        fill: Color = AppChrome.buttonBackgroundColor
    ) -> some View {
        background(fill, in: shape)
            .overlay(shape.stroke(AppChrome.buttonOutlineColor, lineWidth: AppChrome.buttonOutlineWidth))
    }

    /// #245a85 drop shadow for non-button copy.
    func appCopyShadow() -> some View {
        shadow(
            color: AppChrome.copyShadowColor,
            radius: AppChrome.copyShadowRadius,
            x: 0,
            y: AppChrome.copyShadowY
        )
    }
}

extension UILabel {
    func applyAppCopyShadow() {
        AppChrome.applyCopyShadow(to: layer)
    }
}

struct AppTitleText: View {
    let text: String
    var size: CGFloat = 28
    var weight: Font.Weight = .semibold
    var color: Color = AppChrome.primaryTextColor
    /// When set, tapping the title plays this string's voice-over clip.
    var speakID: String? = nil

    var body: some View {
        Text(text)
            .font(AppFont.swiftUI(size: size, weight: weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .appCopyShadow()
            .modifier(OptionalSpeakOnTap(speakID: speakID))
    }
}

private struct OptionalSpeakOnTap: ViewModifier {
    let speakID: String?

    func body(content: Content) -> some View {
        if let speakID {
            content
                .contentShape(Rectangle())
                .onTapGesture { Strings.speak(speakID) }
        } else {
            content
        }
    }
}

struct AppLargeButton: View {
    let title: String
    var accessibilityID: String? = nil
    var backgroundColor: Color = AppChrome.buttonBackgroundColor
    var opacity: Double = 1
    /// Shared `audio.yaml` FX event played on tap (`nil` = silent).
    var soundEvent: String? = "button_click"
    let action: () -> Void

    var body: some View {
        Button {
            playMenuSound(soundEvent)
            action()
        } label: {
            Text(title)
                .font(AppFont.swiftUI(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .appButtonChrome(RoundedRectangle(cornerRadius: 12), fill: backgroundColor)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .frame(minHeight: 44)
        .accessibilityIdentifier(accessibilityID ?? title)
    }
}

/// Circular chrome control (back, lock, etc.) — filled chrome with light SF Symbol.
struct AppCircularIconButton: View {
    let systemName: String
    var size: CGFloat = 52
    var accessibilityID: String? = nil
    var accessibilityLabel: String? = nil
    /// Shared `audio.yaml` FX event played on tap (`nil` = silent).
    var soundEvent: String? = "button_click"
    let action: () -> Void

    var body: some View {
        Button {
            playMenuSound(soundEvent)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .frame(width: size, height: size)
                .appButtonChrome(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? systemName)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct AppCheckbox: View {
    @Binding var isOn: Bool
    var label: String
    var isEnabled: Bool = true
    var boxSize: CGFloat = 28
    var cornerRadius: CGFloat = 6
    var borderColor: Color = AppChrome.primaryTextColor
    var fillColor: Color = AppChrome.controlAccentColor
    var checkColor: Color = Color.black
    var labelColor: Color = AppChrome.primaryTextColor
    var font: Font = AppFont.swiftUI(size: 18, weight: .medium)
    var accessibilityID: String? = nil

    var body: some View {
        Button {
            guard isEnabled else { return }
            playMenuSound("button_click")
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isOn ? fillColor : Color.clear)
                        )
                        .frame(width: boxSize, height: boxSize)

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: boxSize * 0.55, weight: .bold))
                            .foregroundStyle(checkColor)
                    }
                }

                Text(label)
                    .font(font)
                    .foregroundStyle(labelColor)
                    .appCopyShadow()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityID ?? label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(
            isOn ? Strings.text("control_checked") : Strings.text("control_unchecked")
        )
    }
}

struct AppSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var isEnabled: Bool = true
    var trackHeight: CGFloat = 6
    var thumbSize: CGFloat = 22
    var activeTrackColor: Color = AppChrome.controlAccentColor
    var inactiveTrackColor: Color = Color(white: 0.35)
    var thumbColor: Color = AppChrome.primaryTextColor
    var disabledOpacity: Double = 0.4
    var accessibilityID: String? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let progress = normalized(value)
            let thumbX = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(inactiveTrackColor)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(activeTrackColor)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)

                Circle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: clampThumbX(thumbX, width: width), y: geo.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let fraction = min(1, max(0, drag.location.x / width))
                        value = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: max(thumbSize, 44))
        .opacity(isEnabled ? 1 : disabledOpacity)
        .allowsHitTesting(isEnabled)
        .accessibilityIdentifier(accessibilityID ?? "slider")
        .accessibilityValue(
            Text(
                Strings.text(
                    "control_percent",
                    ["percent": String(Int((normalized(value) * 100).rounded()))]
                )
            )
        )
    }

    private func normalized(_ value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private func clampThumbX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let half = thumbSize / 2
        return min(width - half, max(half, x))
    }
}

/// Plays a shared menu UI FX event from `audio.yaml` (missing events/assets are ignored).
func playMenuSound(_ event: String?) {
    guard let event, !event.isEmpty else { return }
    SoundEffectsController.shared.playCommon(event: event)
}

/// Non-interactive left-to-right fill bar for bootstrap / takeoff loading.
struct AppProgressBar: View {
    var progress: Double
    var height: CGFloat = 32
    var accessibilityID: String? = nil

    var body: some View {
        StarWarsConsoleProgressBar(progress: progress)
            .frame(height: height)
            .accessibilityIdentifier(accessibilityID ?? "progress.bar")
            .accessibilityValue(
                Text(
                    Strings.text(
                        "control_percent",
                        ["percent": String(Int((min(1, max(0, progress)) * 100).rounded()))]
                    )
                )
            )
    }
}
