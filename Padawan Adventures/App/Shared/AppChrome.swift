import SwiftUI
import UIKit

enum AppChrome {
    static let backgroundColor = Color.black
    static let primaryTextColor = Color.white
    static let secondaryTextColor = Color(white: 0.65)
    static let buttonBackgroundColor = Color(red: 36 / 255, green: 90 / 255, blue: 133 / 255)
    static let buttonForegroundColor = Color.white
    static let buttonOutlineColor = Color(red: 9 / 255, green: 135 / 255, blue: 232 / 255)
    static let buttonOutlineWidth: CGFloat = 2
    static let copyShadowColor = Color(red: 36 / 255, green: 90 / 255, blue: 133 / 255)
    static let copyShadowRadius: CGFloat = 0
    static let copyShadowY: CGFloat = 2
    static let controlAccentColor = Color(white: 0.92)
    static let maxContentWidth: CGFloat = 420

    static var versionBuildString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }

    static var uiButtonBackgroundColor: UIColor {
        UIColor(red: 36 / 255, green: 90 / 255, blue: 133 / 255, alpha: 1)
    }
    static var uiButtonForegroundColor: UIColor { .white }
    static var uiButtonOutlineColor: UIColor {
        UIColor(red: 9 / 255, green: 135 / 255, blue: 232 / 255, alpha: 1)
    }
    static var uiCopyShadowColor: UIColor {
        UIColor(red: 36 / 255, green: 90 / 255, blue: 133 / 255, alpha: 1)
    }

    /// #245a85 drop shadow for non-button copy.
    static func applyCopyShadow(to layer: CALayer) {
        layer.shadowColor = uiCopyShadowColor.cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = copyShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: copyShadowY)
        layer.masksToBounds = false
    }
}

enum AppFont {
    /// PostScript name — use for UIFont, Font.custom, and SKLabelNode.fontName.
    static let name = "Conthrax-SemiBold"

    /// SwiftUI text. `weight` is ignored (single face); kept so call sites can mirror old `.system(size:weight:)` shape.
    static func swiftUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = weight
        return .custom(name, size: size)
    }

    /// UIKit labels / attributed strings / button transformers.
    static func uiKit(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
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

    var body: some View {
        Text(text)
            .font(AppFont.swiftUI(size: size, weight: weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .appCopyShadow()
    }
}

struct AppLargeButton: View {
    let title: String
    var accessibilityID: String? = nil
    var backgroundColor: Color = AppChrome.buttonBackgroundColor
    var opacity: Double = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .accessibilityValue(isOn ? "checked" : "unchecked")
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
        .accessibilityValue(Text("\(Int((normalized(value) * 100).rounded())) percent"))
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

/// Non-interactive left-to-right fill bar for bootstrap / takeoff loading.
struct AppProgressBar: View {
    var progress: Double
    var height: CGFloat = 12
    var trackColor: Color = Color(white: 0.25)
    var fillColor: Color = AppChrome.controlAccentColor
    var accessibilityID: String? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(width * clamped, clamped > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityIdentifier(accessibilityID ?? "progress.bar")
        .accessibilityValue(Text("\(Int((min(1, max(0, progress)) * 100).rounded())) percent"))
    }
}

enum LoadProgress {
    /// Maps a local 0...1 fraction into an overall progress window.
    static func map(_ local: Double, from start: Double, to end: Double) -> Double {
        let clamped = min(1, max(0, local))
        return start + clamped * (end - start)
    }
}
